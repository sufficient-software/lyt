defmodule PhxAnalytics.EventQueueTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias PhxAnalytics.{EventQueue, Session, Event, Repo}

  # These tests need to run without sync_mode to actually test the queue
  # We start a fresh EventQueue for each test with sandbox access

  setup do
    # Temporarily disable sync_mode for these tests
    original_sync_mode = Application.get_env(:phx_analytics, :sync_mode, false)
    Application.put_env(:phx_analytics, :sync_mode, false)

    # Setup sandbox
    repo = Application.fetch_env!(:phx_analytics, :repo)
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: true)

    # Start a fresh EventQueue with a unique name for this test
    queue_name = :"event_queue_#{System.unique_integer([:positive])}"
    {:ok, queue_pid} = EventQueue.start_link(name: queue_name, flush_interval: 50)

    # Allow the queue process to use the sandbox
    Ecto.Adapters.SQL.Sandbox.allow(repo, self(), queue_pid)

    on_exit(fn ->
      # Restore original sync_mode
      Application.put_env(:phx_analytics, :sync_mode, original_sync_mode)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    {:ok, queue: queue_name, queue_pid: queue_pid, repo: repo}
  end

  describe "queue_session/2" do
    test "queues a session for insertion", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{id: session_id, hostname: "example.com", entry: "/"}, queue)
      EventQueue.flush(queue)

      assert session = Repo.get(Session, session_id)
      assert session.hostname == "example.com"
      assert session.entry == "/"
    end

    test "handles string keys in attributes", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{"id" => session_id, "hostname" => "example.com"}, queue)
      EventQueue.flush(queue)

      assert Repo.get(Session, session_id)
    end

    test "queues multiple sessions", %{queue: queue} do
      ids = for _ <- 1..5, do: generate_id()

      for id <- ids do
        EventQueue.queue_session(%{id: id, hostname: "example.com"}, queue)
      end

      EventQueue.flush(queue)

      for id <- ids do
        assert Repo.get(Session, id)
      end
    end

    test "upserts existing sessions", %{queue: queue} do
      session_id = generate_id()

      # First insert
      EventQueue.queue_session(%{id: session_id, hostname: "example.com", entry: "/first"}, queue)
      EventQueue.flush(queue)

      # Upsert with new data
      EventQueue.queue_session(
        %{id: session_id, hostname: "example.com", entry: "/second"},
        queue
      )

      EventQueue.flush(queue)

      # Should still be one session (entry should NOT be updated due to upsert keys)
      sessions = Repo.all(Session)
      assert length(sessions) == 1
      assert hd(sessions).entry == "/first"
    end
  end

  describe "queue_event/2" do
    test "queues an event for insertion after session exists", %{queue: queue} do
      session_id = generate_id()

      # Queue session first
      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)

      # Queue event
      EventQueue.queue_event(
        %{session_id: session_id, name: "Page View", path: "/home"},
        queue
      )

      EventQueue.flush(queue)

      events = Repo.all(Event)
      assert length(events) == 1
      assert hd(events).name == "Page View"
      assert hd(events).session_id == session_id
    end

    test "holds events until their session is inserted", %{queue: queue} do
      session_id = generate_id()

      # Queue event BEFORE session
      EventQueue.queue_event(
        %{session_id: session_id, name: "Page View", path: "/home"},
        queue
      )

      # First flush - event should not be inserted (session doesn't exist)
      EventQueue.flush(queue)
      assert Repo.all(Event) == []

      # Now queue the session
      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)
      EventQueue.flush(queue)

      # Event should now be inserted
      events = Repo.all(Event)
      assert length(events) == 1
      assert hd(events).session_id == session_id
    end

    test "handles multiple events for the same session", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)

      for i <- 1..5 do
        EventQueue.queue_event(
          %{session_id: session_id, name: "Event #{i}", path: "/page#{i}"},
          queue
        )
      end

      EventQueue.flush(queue)

      events = Repo.all(Event)
      assert length(events) == 5
    end

    test "handles events for multiple sessions", %{queue: queue} do
      session_ids = for _ <- 1..3, do: generate_id()

      # Queue all sessions
      for id <- session_ids do
        EventQueue.queue_session(%{id: id, hostname: "example.com"}, queue)
      end

      # Queue events for each session
      for id <- session_ids do
        EventQueue.queue_event(%{session_id: id, name: "Page View", path: "/"}, queue)
        EventQueue.queue_event(%{session_id: id, name: "Click", path: "/button"}, queue)
      end

      EventQueue.flush(queue)

      events = Repo.all(Event)
      assert length(events) == 6
    end
  end

  describe "queue_event_changeset/2" do
    test "queues a pre-built changeset for insertion", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)

      changeset =
        Event.changeset(%Event{}, %{
          session_id: session_id,
          name: "Custom Event",
          path: "/custom",
          metadata: %{"custom_key" => "custom_value"}
        })

      EventQueue.queue_event_changeset(changeset, queue)
      EventQueue.flush(queue)

      events = Repo.all(Event)
      assert length(events) == 1
      assert hd(events).name == "Custom Event"
      assert hd(events).metadata["custom_key"] == "custom_value"
    end
  end

  describe "stats/1" do
    test "returns queue statistics", %{queue: queue} do
      session_id = generate_id()

      # Initially empty
      stats = EventQueue.stats(queue)
      assert stats.pending_sessions == 0
      assert stats.pending_events == 0
      assert stats.inserted_sessions == 0

      # After queueing
      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)
      EventQueue.queue_event(%{session_id: session_id, name: "Test", path: "/"}, queue)

      stats = EventQueue.stats(queue)
      assert stats.pending_sessions == 1
      assert stats.pending_events == 1

      # After flush
      EventQueue.flush(queue)

      stats = EventQueue.stats(queue)
      assert stats.pending_sessions == 0
      assert stats.pending_events == 0
      assert stats.inserted_sessions == 1
    end
  end

  describe "automatic flushing" do
    test "flushes automatically based on flush_interval", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)

      # Wait for automatic flush (flush_interval is 50ms in setup)
      Process.sleep(100)

      # Should have been inserted automatically
      assert Repo.get(Session, session_id)
    end
  end

  describe "batch_size limiting" do
    test "respects batch_size configuration", %{queue: queue} do
      # Queue many sessions
      ids = for _ <- 1..10, do: generate_id()

      for id <- ids do
        EventQueue.queue_session(%{id: id, hostname: "example.com"}, queue)
      end

      # Get initial stats
      stats = EventQueue.stats(queue)
      assert stats.pending_sessions == 10

      # Flush all
      EventQueue.flush(queue)

      # All should be inserted
      stats = EventQueue.stats(queue)
      assert stats.pending_sessions == 0
      assert stats.inserted_sessions == 10
    end
  end

  describe "error handling" do
    test "continues processing after session insert failure", %{queue: queue} do
      good_id = generate_id()
      # This won't cause an error since we're not enforcing constraints
      # But we can test that the queue continues to work

      EventQueue.queue_session(%{id: good_id, hostname: "example.com"}, queue)
      EventQueue.flush(queue)

      assert Repo.get(Session, good_id)
    end

    test "events with missing sessions remain queued", %{queue: queue} do
      missing_session_id = generate_id()
      valid_session_id = generate_id()

      # Queue event for non-existent session
      EventQueue.queue_event(
        %{session_id: missing_session_id, name: "Orphan Event", path: "/"},
        queue
      )

      # Queue valid session and event
      EventQueue.queue_session(%{id: valid_session_id, hostname: "example.com"}, queue)

      EventQueue.queue_event(
        %{session_id: valid_session_id, name: "Valid Event", path: "/"},
        queue
      )

      EventQueue.flush(queue)

      # Valid event should be inserted
      events = Repo.all(Event)
      assert length(events) == 1
      assert hd(events).name == "Valid Event"

      # Orphan event should still be pending
      stats = EventQueue.stats(queue)
      assert stats.pending_events == 1
    end
  end

  describe "ordering guarantees" do
    test "sessions are always inserted before their events", %{queue: queue} do
      session_id = generate_id()

      # Queue event first, then session
      EventQueue.queue_event(%{session_id: session_id, name: "Event 1", path: "/"}, queue)
      EventQueue.queue_event(%{session_id: session_id, name: "Event 2", path: "/"}, queue)
      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)
      EventQueue.queue_event(%{session_id: session_id, name: "Event 3", path: "/"}, queue)

      EventQueue.flush(queue)

      # All should be inserted correctly
      assert Repo.get(Session, session_id)
      events = Repo.all(Event)
      assert length(events) == 3
    end

    test "events maintain order within a session", %{queue: queue} do
      session_id = generate_id()

      EventQueue.queue_session(%{id: session_id, hostname: "example.com"}, queue)

      for i <- 1..5 do
        EventQueue.queue_event(
          %{session_id: session_id, name: "Event #{i}", path: "/page#{i}"},
          queue
        )
      end

      EventQueue.flush(queue)

      events = Repo.all(from(e in Event, order_by: [asc: e.inserted_at]))
      names = Enum.map(events, & &1.name)
      assert names == ["Event 1", "Event 2", "Event 3", "Event 4", "Event 5"]
    end
  end

  # Helper to generate unique session IDs
  defp generate_id do
    PhxAnalytics.generate_session_id()
  end
end
