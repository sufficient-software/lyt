defmodule PhxAnalytics do
  @moduledoc """
  Documentation for `PhxAnalytics`.
  """

  alias PhxAnalytics.{Session, Event, Repo}

  def attach(_opts \\ []) do
    :telemetry.attach_many(
      <<"phx_analytics">>,
      [
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :handle_event, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert!(
      # without `returning: true`, it will optimistically return the data from the changeset
      # instead of the real values from the database
      returning: true,
      conflict_target: :id,
      on_conflict: {:replace, Session.upsert_keys()}
    )
  end

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} -> event
      {:error, _changeset} -> nil
    end
  end

  def parse_user_agent(user_agent) do
    case UAInspector.parse(user_agent) do
      %UAInspector.Result{
        client: %{name: client_name, version: client_version},
        os: %{name: os_name, version: os_version}
      } ->
        %{
          browser: client_name,
          browser_version: client_version,
          operating_system: os_name,
          operating_system_version: os_version
        }

      %UAInspector.Result.Bot{name: name} ->
        %{
          browser: name
        }

      _ ->
        %{browser: "Unknown"}
    end
  end

  def parse_utm(params \\ %{}) do
    %{
      utm_source: Map.get(params, "utm_source"),
      utm_medium: Map.get(params, "utm_medium"),
      utm_campaign: Map.get(params, "utm_campaign"),
      utm_term: Map.get(params, "utm_term"),
      utm_content: Map.get(params, "utm_content")
    }
  end

  def generate_session_id() do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Use PhxAnalytics in a LiveView module to enable event tracking.

  ## Options

    * `:track_all` - When `true`, tracks all handle_event calls automatically.
    * `:include` - A list of event names to track (without needing `@analytics`).
    * `:exclude` - A list of event names to exclude from tracking.

  When both `:include` and `:exclude` are provided, `:include` takes precedence
  (only included events are tracked, exclude is ignored).

  ## Examples

      # Track specific events without @analytics decorator
      use PhxAnalytics, include: ["submit_form", "click_button"]

      # Track all events except these
      use PhxAnalytics, track_all: true, exclude: ["ping", "heartbeat"]

      # Track all events
      use PhxAnalytics, track_all: true
  """
  defmacro __using__(opts) do
    quote do
      Module.register_attribute(__MODULE__, :_phx_analytics_tracked_functions, accumulate: true)
      Module.put_attribute(__MODULE__, :_phx_analytics_opts, unquote(opts))
      @before_compile PhxAnalytics
      @on_definition {PhxAnalytics, :__on_definition__}
      require PhxAnalytics
    end
  end

  defmacro __before_compile__(env) do
    tracked_event_handlers = Module.get_attribute(env.module, :_phx_analytics_tracked_functions)
    opts = Module.get_attribute(env.module, :_phx_analytics_opts) || []

    track_all = Keyword.get(opts, :track_all, false)
    include_list = Keyword.get(opts, :include, [])
    exclude_list = Keyword.get(opts, :exclude, [])

    quote do
      def phx_analytics_tracked_event_handlers do
        unquote(Macro.escape(tracked_event_handlers))
      end

      def phx_analytics_tracking_opts do
        %{
          track_all: unquote(track_all),
          include: unquote(include_list),
          exclude: unquote(exclude_list)
        }
      end
    end
  end

  def __on_definition__(env, kind, name, args, _guards, _body) do
    if Module.get_attribute(env.module, :analytics) do
      track_handler(env, kind, name, args)
    end
  end

  defp track_handler(env, kind, name, args) when kind in [:def, :defp] do
    tracked_info =
      case {name, args} do
        {:handle_event, [{:<<>>, _, [event_name]}, _params, _socket]} ->
          {name, [event_name]}

        {:handle_event, [event_name, _params, _socket]} when is_binary(event_name) ->
          {name, [event_name]}

        _ ->
          {name, []}
      end

    Module.put_attribute(env.module, :_phx_analytics_tracked_functions, tracked_info)
    Module.delete_attribute(env.module, :analytics)
  end

  def handle_event([:phoenix, :live_view, :mount, _], _measurement, metadata, _config) do
    uri =
      metadata
      |> get_in([:uri])
      |> URI.parse()

    session_id = get_in(metadata, [:session, session_cookie_name()])

    Process.put(:phx_analytics_uri, uri)
    Process.put(:phx_analytics_session_id, session_id)

    # Only record on connected mount, not static render, to avoid duplicate events.
    # Check socket.transport_pid - it's nil during static render, set during live mount.
    connected? =
      case metadata do
        %{socket: %{transport_pid: pid}} when is_pid(pid) -> true
        _ -> false
      end

    if connected? and not path_excluded?(uri.path) do
      %{
        session_id: session_id,
        name: "Live View",
        hostname: uri.host,
        path: uri.path,
        query: uri.query
      }
      |> create_event()
    end
  end

  def handle_event([:phoenix, :live_view, :handle_params, _], _measurement, metadata, _config) do
    uri =
      metadata
      |> get_in([:uri])
      |> URI.parse()

    previous_uri = Process.get(:phx_analytics_uri)
    session_id = Process.get(:phx_analytics_session_id)

    # Update stored URI for future comparisons
    Process.put(:phx_analytics_uri, uri)

    # Only create event if path changed (not on initial mount, which already creates an event)
    path_changed = previous_uri && previous_uri.path != uri.path

    if path_changed && !path_excluded?(uri.path) do
      %{
        session_id: session_id,
        name: "Live View",
        hostname: uri.host,
        path: uri.path,
        query: uri.query
      }
      |> create_event()
    end
  end

  def handle_event([:phoenix, :live_view, :handle_event, _], _measurement, metadata, _config) do
    uri = Process.get(:phx_analytics_uri)

    if uri && !path_excluded?(uri.path) do
      view = metadata.socket.view
      event_name = metadata.event

      is_tracked = event_tracked?(view, event_name)

      if is_tracked do
        session_id = Process.get(:phx_analytics_session_id)

        %{
          session_id: session_id,
          name: "Live View",
          hostname: uri.host,
          # TODO: filter params for sensitive data
          metadata: %{"params" => metadata.params},
          path: uri.path,
          query: uri.query
        }
        |> create_event()
      end
    end
  end

  def handle_event(_event, _, _, _) do
    # Skip unknown event handlers
  end

  defp event_tracked?(view, event_name) do
    # Get tracking options from the module
    opts =
      if function_exported?(view, :phx_analytics_tracking_opts, 0) do
        view.phx_analytics_tracking_opts()
      else
        %{track_all: false, include: [], exclude: []}
      end

    tracked_handlers =
      if function_exported?(view, :phx_analytics_tracked_event_handlers, 0) do
        view.phx_analytics_tracked_event_handlers()
      else
        []
      end

    # Check if explicitly tracked via @analytics decorator
    explicitly_tracked =
      Enum.any?(tracked_handlers, fn
        {:handle_event, [event]} -> event == event_name
        _ -> false
      end)

    cond do
      # If explicitly tracked with @analytics, always track
      explicitly_tracked ->
        true

      # If include list is provided, only track events in the list
      opts.include != [] ->
        event_name in opts.include

      # If track_all is true, track unless excluded
      opts.track_all ->
        event_name not in opts.exclude

      # Default: not tracked
      true ->
        false
    end
  end

  defp path_excluded?(nil), do: false

  defp path_excluded?(path) do
    excluded_paths = Application.get_env(:phx_analytics, :excluded_paths, [])

    Enum.any?(excluded_paths, fn excluded ->
      String.starts_with?(path, excluded)
    end)
  end

  defp session_cookie_name do
    Application.get_env(:phx_analytics, :session_cookie_name, "phx_analytics_session")
  end
end
