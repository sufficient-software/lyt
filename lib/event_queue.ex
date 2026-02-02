defmodule Lyt.EventQueue do
  @moduledoc """
  A GenServer that queues analytics sessions and events for async database insertion.

  Sessions are always processed before their associated events to ensure foreign key
  constraints are satisfied. Events are held until their session has been inserted.

  ## Usage

      # Queue a session (must be done before queueing events for that session)
      Lyt.EventQueue.queue_session(%{id: "abc123", hostname: "example.com", ...})

      # Queue an event (will wait for session to be inserted first)
      Lyt.EventQueue.queue_event(%{session_id: "abc123", name: "Page View", ...})

  ## Configuration

      config :lyt, Lyt.EventQueue,
        flush_interval: 100,  # ms between flush attempts
        batch_size: 50,       # max items to process per flush
        max_session_cache: 10_000  # max inserted sessions to keep in memory
  """

  use GenServer

  alias Lyt.{Session, Event, Repo}

  @default_flush_interval 100
  @default_batch_size 50
  @default_max_session_cache 10_000

  defstruct sessions: %{},
            pending_sessions: :queue.new(),
            pending_events: :queue.new(),
            inserted_sessions: MapSet.new(),
            session_insert_order: :queue.new(),
            flush_ref: nil

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Queue a session for insertion. Sessions are inserted before any events
  that reference them.
  """
  def queue_session(attrs, server \\ __MODULE__) do
    GenServer.cast(server, {:queue_session, attrs})
  end

  @doc """
  Queue an event for insertion. The event will be held until its associated
  session has been inserted.
  """
  def queue_event(attrs, server \\ __MODULE__) do
    GenServer.cast(server, {:queue_event, attrs})
  end

  @doc """
  Queue an event changeset for insertion (used when before_save has already
  been applied). The event will be held until its associated session has been inserted.
  """
  def queue_event_changeset(changeset, server \\ __MODULE__) do
    GenServer.cast(server, {:queue_event_changeset, changeset})
  end

  @doc """
  Synchronously flush all pending items. Useful for testing.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @doc """
  Get the current queue stats. Useful for monitoring.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      flush_ref: schedule_flush(flush_interval(opts))
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_session, attrs}, state) do
    session_id = attrs[:id] || attrs["id"]

    state =
      state
      |> Map.update!(:sessions, &Map.put(&1, session_id, attrs))
      |> Map.update!(:pending_sessions, &:queue.in(session_id, &1))

    {:noreply, state}
  end

  def handle_cast({:queue_event, attrs}, state) do
    event_item = {:attrs, attrs}
    state = Map.update!(state, :pending_events, &:queue.in(event_item, &1))
    {:noreply, state}
  end

  def handle_cast({:queue_event_changeset, changeset}, state) do
    event_item = {:changeset, changeset}
    state = Map.update!(state, :pending_events, &:queue.in(event_item, &1))
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    state = do_flush(state, :all)
    {:reply, :ok, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      pending_sessions: :queue.len(state.pending_sessions),
      pending_events: :queue.len(state.pending_events),
      inserted_sessions: MapSet.size(state.inserted_sessions),
      sessions_in_memory: map_size(state.sessions)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush, state) do
    state = do_flush(state, batch_size())
    state = %{state | flush_ref: schedule_flush(flush_interval())}
    {:noreply, state}
  end

  # Private Functions

  defp do_flush(state, limit) do
    state
    |> flush_sessions(limit)
    |> flush_events(limit)
  end

  defp flush_sessions(state, limit) do
    {to_insert, remaining, count} = dequeue_n(state.pending_sessions, limit)

    inserted_ids =
      Enum.reduce(to_insert, [], fn session_id, acc ->
        case Map.get(state.sessions, session_id) do
          nil ->
            acc

          attrs ->
            case insert_session(attrs) do
              {:ok, _session} -> [session_id | acc]
              {:error, _} -> acc
            end
        end
      end)

    remaining_limit =
      case limit do
        :all -> :all
        n -> max(0, n - count)
      end

    # Track insertion order for LRU eviction
    new_insert_order =
      Enum.reduce(inserted_ids, state.session_insert_order, &:queue.in(&1, &2))

    new_inserted_sessions =
      Enum.reduce(inserted_ids, state.inserted_sessions, &MapSet.put(&2, &1))

    # Evict oldest sessions if cache is too large
    {final_inserted_sessions, final_insert_order} =
      trim_session_cache(new_inserted_sessions, new_insert_order)

    %{
      state
      | pending_sessions: remaining,
        inserted_sessions: final_inserted_sessions,
        session_insert_order: final_insert_order,
        sessions: Map.drop(state.sessions, inserted_ids)
    }
    |> maybe_continue_sessions(remaining_limit)
  end

  defp trim_session_cache(inserted_sessions, insert_order) do
    max_size = max_session_cache()
    current_size = MapSet.size(inserted_sessions)

    if current_size > max_size do
      # Remove oldest entries until we're at 90% of max to avoid constant trimming
      target_size = trunc(max_size * 0.9)
      to_remove = current_size - target_size

      {updated_sessions, updated_order} =
        Enum.reduce(1..to_remove, {inserted_sessions, insert_order}, fn _, {sessions, order} ->
          case :queue.out(order) do
            {{:value, session_id}, new_order} ->
              {MapSet.delete(sessions, session_id), new_order}

            {:empty, order} ->
              {sessions, order}
          end
        end)

      {updated_sessions, updated_order}
    else
      {inserted_sessions, insert_order}
    end
  end

  defp max_session_cache do
    Application.get_env(:lyt, __MODULE__, [])[:max_session_cache] ||
      @default_max_session_cache
  end

  defp maybe_continue_sessions(state, :all) do
    if :queue.is_empty(state.pending_sessions) do
      state
    else
      flush_sessions(state, :all)
    end
  end

  defp maybe_continue_sessions(state, 0), do: state
  defp maybe_continue_sessions(state, remaining), do: flush_sessions(state, remaining)

  defp flush_events(state, limit) do
    {to_process, remaining_queue} =
      partition_ready_events(state.pending_events, state.inserted_sessions, limit)

    Enum.each(to_process, fn
      {:attrs, attrs} ->
        insert_event_attrs(attrs)

      {:changeset, changeset} ->
        Repo.insert(changeset)
    end)

    %{state | pending_events: remaining_queue}
  end

  defp partition_ready_events(queue, inserted_sessions, limit) do
    partition_ready_events(queue, inserted_sessions, limit, [], :queue.new())
  end

  defp partition_ready_events(queue, _inserted_sessions, 0, ready, not_ready) do
    # Limit reached, put remaining back
    final_not_ready = :queue.join(not_ready, queue)
    {Enum.reverse(ready), final_not_ready}
  end

  defp partition_ready_events(queue, inserted_sessions, limit, ready, not_ready) do
    case :queue.out(queue) do
      {:empty, _} ->
        {Enum.reverse(ready), not_ready}

      {{:value, item}, rest} ->
        session_id = get_session_id(item)

        if MapSet.member?(inserted_sessions, session_id) do
          new_limit = if limit == :all, do: :all, else: limit - 1
          partition_ready_events(rest, inserted_sessions, new_limit, [item | ready], not_ready)
        else
          partition_ready_events(
            rest,
            inserted_sessions,
            limit,
            ready,
            :queue.in(item, not_ready)
          )
        end
    end
  end

  defp get_session_id({:attrs, attrs}), do: attrs[:session_id] || attrs["session_id"]

  defp get_session_id({:changeset, changeset}),
    do: Ecto.Changeset.get_field(changeset, :session_id)

  defp insert_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert(
      returning: true,
      conflict_target: :id,
      on_conflict: {:replace, Session.upsert_keys()}
    )
  end

  defp insert_event_attrs(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  defp dequeue_n(queue, :all) do
    items = :queue.to_list(queue)
    {items, :queue.new(), length(items)}
  end

  defp dequeue_n(queue, n) do
    dequeue_n(queue, n, [], 0)
  end

  defp dequeue_n(queue, 0, acc, count), do: {Enum.reverse(acc), queue, count}

  defp dequeue_n(queue, n, acc, count) do
    case :queue.out(queue) do
      {:empty, _} -> {Enum.reverse(acc), queue, count}
      {{:value, item}, rest} -> dequeue_n(rest, n - 1, [item | acc], count + 1)
    end
  end

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end

  defp flush_interval(opts \\ []) do
    Keyword.get(opts, :flush_interval) ||
      Application.get_env(:lyt, __MODULE__, [])[:flush_interval] ||
      @default_flush_interval
  end

  defp batch_size do
    Application.get_env(:lyt, __MODULE__, [])[:batch_size] ||
      @default_batch_size
  end
end
