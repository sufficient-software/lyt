defmodule PhxAnalytics do
  @moduledoc """
  Highly customizable analytics for Phoenix LiveView applications.

  PhxAnalytics provides automatic tracking of page views and custom events in Phoenix
  LiveView applications. It captures session data including browser information, UTM
  parameters, and custom metadata.

  ## Features

    * Automatic LiveView mount and navigation tracking
    * Custom event tracking with the `@analytics` decorator
    * Session management with device/browser detection
    * UTM parameter capture
    * Async event queuing for performance
    * Multi-database support (PostgreSQL, MySQL, SQLite3)

  ## Quick Start

  1. Add PhxAnalytics to your supervision tree:

      ```elixir
      # In your application.ex
      children = [
        MyApp.Repo,
        PhxAnalytics.Telemetry,
        # ... other children
      ]
      ```

  2. Add the Plug to your router pipeline:

      ```elixir
      # In your router.ex
      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug PhxAnalytics.Plug
        # ... other plugs
      end
      ```

  3. Configure your repo:

      ```elixir
      # In config/config.exs
      config :phx_analytics, :repo, MyApp.Repo
      ```

  4. Run migrations:

      ```elixir
      # In a migration file
      def up do
        PhxAnalytics.Migration.up()
      end

      def down do
        PhxAnalytics.Migration.down()
      end
      ```

  ## Tracking Custom Events

  Use the `@analytics` decorator in your LiveView modules to track specific events:

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        use PhxAnalytics

        @analytics true
        def handle_event("submit_form", params, socket) do
          # Your event handling code
          {:noreply, socket}
        end
      end

  You can also configure module-level tracking options:

      use PhxAnalytics, track_all: true, exclude: ["ping", "heartbeat"]

  See `__using__/1` for all available options.
  """

  alias PhxAnalytics.{Session, Event, Repo, EventQueue}

  @doc """
  Attach telemetry handlers manually.

  This is called automatically when using `PhxAnalytics.Telemetry` in your
  supervision tree. You only need to call this directly if you're not using
  the Telemetry supervisor.

  ## Example

      PhxAnalytics.attach()

  """
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

  @doc """
  Queue a session for async insertion.
  Returns a Session struct with the generated ID immediately (before DB insert).

  In sync mode (configured with `config :phx_analytics, sync_mode: true`), this
  will insert synchronously instead of queueing. Useful for testing.
  """
  def queue_session(attrs \\ %{}) do
    if sync_mode?() do
      create_session(attrs)
    else
      # Generate ID if not provided
      attrs = ensure_session_id(attrs)

      # Build the session struct to return immediately
      session = struct(Session, atomize_keys(attrs))

      # Queue for async insert
      EventQueue.queue_session(attrs)

      session
    end
  end

  @doc """
  Create a session synchronously. Use `queue_session/1` for async insertion.
  """
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

  @doc """
  Queue an event for async insertion.

  In sync mode (configured with `config :phx_analytics, sync_mode: true`), this
  will insert synchronously instead of queueing. Useful for testing.
  """
  def queue_event(attrs) do
    if sync_mode?() do
      create_event(attrs)
    else
      EventQueue.queue_event(attrs)
    end
  end

  @doc """
  Create an event synchronously. Use `queue_event/1` for async insertion.
  """
  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} -> event
      {:error, _changeset} -> nil
    end
  end

  defp ensure_session_id(attrs) when is_map(attrs) do
    id = attrs[:id] || attrs["id"] || generate_session_id()
    Map.put(attrs, :id, id)
  end

  defp sync_mode? do
    Application.get_env(:phx_analytics, :sync_mode, false)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end

  @doc """
  Parse a user-agent string to extract browser and operating system information.

  Returns a map with browser and OS details. Uses UAInspector for parsing.

  ## Return Value

  Returns a map with the following keys (when available):
    * `:browser` - Browser name (e.g., "Chrome", "Firefox", "Safari")
    * `:browser_version` - Browser version string
    * `:operating_system` - OS name (e.g., "Mac", "Windows", "Linux")
    * `:operating_system_version` - OS version string

  For bots, only `:browser` is returned with the bot name.

  ## Examples

      # Full user agent parsing
      PhxAnalytics.parse_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...")
      # => %{browser: "Safari", browser_version: "...", operating_system: "Mac", ...}

      # Bot detection
      PhxAnalytics.parse_user_agent("Googlebot/2.1 (+http://www.google.com/bot.html)")
      # => %{browser: "Googlebot"}

  """
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

  @doc """
  Extract UTM parameters from a map of query parameters.

  Returns a map with all UTM fields (source, medium, campaign, term, content).
  Values are `nil` if not present in the params.

  ## Examples

      iex> PhxAnalytics.parse_utm(%{"utm_source" => "google", "utm_medium" => "cpc"})
      %{
        utm_source: "google",
        utm_medium: "cpc",
        utm_campaign: nil,
        utm_term: nil,
        utm_content: nil
      }

  """
  def parse_utm(params \\ %{}) do
    %{
      utm_source: Map.get(params, "utm_source"),
      utm_medium: Map.get(params, "utm_medium"),
      utm_campaign: Map.get(params, "utm_campaign"),
      utm_term: Map.get(params, "utm_term"),
      utm_content: Map.get(params, "utm_content")
    }
  end

  @doc """
  Generate a cryptographically secure session ID.

  Returns a 64-character lowercase hexadecimal string (32 random bytes).

  ## Examples

      iex> id = PhxAnalytics.generate_session_id()
      iex> String.length(id)
      64

  """
  def generate_session_id() do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Use PhxAnalytics in a LiveView module to enable event tracking.

  ## Options

    * `:track_all` - When `true`, tracks all handle_event calls automatically.
    * `:include` - A list of event names to track (without needing `@analytics`).
    * `:exclude` - A list of event names to exclude from tracking.
    * `:before_save` - A function that receives `(changeset, opts, socket)` and returns
      `{:ok, changeset}` to proceed, or `:halt`/`nil` to cancel saving.

  When both `:include` and `:exclude` are provided, `:include` takes precedence
  (only included events are tracked, exclude is ignored).

  ## Examples

      # Track specific events without @analytics decorator
      use PhxAnalytics, include: ["submit_form", "click_button"]

      # Track all events except these
      use PhxAnalytics, track_all: true, exclude: ["ping", "heartbeat"]

      # Track all events
      use PhxAnalytics, track_all: true

      # Add a before_save callback at the module level
      use PhxAnalytics, before_save: &__MODULE__.filter_analytics/3

      def filter_analytics(changeset, _opts, socket) do
        if socket.assigns.user.admin? do
          {:ok, changeset}
        else
          :halt
        end
      end
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
    before_save = Keyword.get(opts, :before_save)

    quote do
      def phx_analytics_tracked_event_handlers do
        unquote(Macro.escape(tracked_event_handlers))
      end

      def phx_analytics_tracking_opts do
        %{
          track_all: unquote(track_all),
          include: unquote(include_list),
          exclude: unquote(exclude_list),
          before_save: unquote(before_save)
        }
      end
    end
  end

  def __on_definition__(env, kind, name, args, _guards, _body) do
    analytics_opts = Module.get_attribute(env.module, :analytics)

    if analytics_opts do
      track_handler(env, kind, name, args, analytics_opts)
    end
  end

  defp track_handler(env, kind, name, args, analytics_opts) when kind in [:def, :defp] do
    # Parse analytics options
    opts =
      case analytics_opts do
        true -> %{}
        opts when is_list(opts) -> Map.new(opts)
        _ -> %{}
      end

    tracked_info =
      case {name, args} do
        {:handle_event, [{:<<>>, _, [event_name]}, _params, _socket]} ->
          {:handle_event, event_name, opts}

        {:handle_event, [event_name, _params, _socket]} when is_binary(event_name) ->
          {:handle_event, event_name, opts}

        _ ->
          {name, nil, opts}
      end

    Module.put_attribute(env.module, :_phx_analytics_tracked_functions, tracked_info)
    Module.delete_attribute(env.module, :analytics)
  end

  @doc false
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
      |> queue_event()
    end
  end

  @doc false
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
      |> queue_event()
    end
  end

  @doc false
  def handle_event([:phoenix, :live_view, :handle_event, _], _measurement, metadata, _config) do
    uri = Process.get(:phx_analytics_uri)

    if uri && !path_excluded?(uri.path) do
      view = metadata.socket.view
      event_name = metadata.event

      case event_tracked?(view, event_name) do
        {true, opts, module_opts} ->
          session_id = Process.get(:phx_analytics_session_id)

          # Use custom name if provided, otherwise use the event name
          name = Map.get(opts, :name, event_name)

          # Build metadata - start with params, merge custom metadata if provided
          event_metadata =
            case Map.get(opts, :metadata) do
              nil ->
                %{"params" => metadata.params}

              custom when is_map(custom) ->
                Map.merge(%{"params" => metadata.params}, custom)

              custom_fn when is_function(custom_fn, 1) ->
                custom = custom_fn.(metadata.params)
                Map.merge(%{"params" => metadata.params}, custom)
            end

          attrs = %{
            session_id: session_id,
            name: name,
            hostname: uri.host,
            metadata: event_metadata,
            path: uri.path,
            query: uri.query
          }

          changeset = Event.changeset(%Event{}, attrs)

          # Get before_save callback - decorator level takes precedence over module level
          before_save_fn = Map.get(opts, :before_save) || Map.get(module_opts, :before_save)

          case run_before_save(before_save_fn, changeset, opts, metadata.socket) do
            {:ok, final_changeset} ->
              if sync_mode?() do
                Repo.insert(final_changeset)
              else
                EventQueue.queue_event_changeset(final_changeset)
              end

            _ ->
              :ok
          end

        false ->
          :ok
      end
    end
  end

  @doc false
  def handle_event(_event, _, _, _) do
    # Skip unknown event handlers
  end

  defp run_before_save(nil, changeset, _opts, _socket), do: {:ok, changeset}

  defp run_before_save(before_save_fn, changeset, opts, socket)
       when is_function(before_save_fn, 3) do
    case before_save_fn.(changeset, opts, socket) do
      {:ok, %Ecto.Changeset{} = cs} -> {:ok, cs}
      :halt -> :halt
      nil -> :halt
      _ -> :halt
    end
  end

  defp run_before_save(_invalid, changeset, _opts, _socket), do: {:ok, changeset}

  # Returns {true, opts, module_opts} if tracked, false otherwise
  # opts contains any overrides like :name, :metadata, or :before_save from the decorator
  # module_opts contains module-level options like :before_save
  defp event_tracked?(view, event_name) do
    # Get tracking options from the module
    module_opts =
      if function_exported?(view, :phx_analytics_tracking_opts, 0) do
        view.phx_analytics_tracking_opts()
      else
        %{track_all: false, include: [], exclude: [], before_save: nil}
      end

    tracked_handlers =
      if function_exported?(view, :phx_analytics_tracked_event_handlers, 0) do
        view.phx_analytics_tracked_event_handlers()
      else
        []
      end

    # Check if explicitly tracked via @analytics decorator and get its options
    explicit_tracking =
      Enum.find_value(tracked_handlers, fn
        {:handle_event, event, opts} when event == event_name -> {:found, opts}
        # Legacy format support
        {:handle_event, [event]} when event == event_name -> {:found, %{}}
        _ -> nil
      end)

    cond do
      # If explicitly tracked with @analytics, return true with options
      explicit_tracking != nil ->
        {:found, opts} = explicit_tracking
        {true, opts, module_opts}

      # If include list is provided, only track events in the list
      module_opts.include != [] ->
        if event_name in module_opts.include, do: {true, %{}, module_opts}, else: false

      # If track_all is true, track unless excluded
      module_opts.track_all ->
        if event_name not in module_opts.exclude, do: {true, %{}, module_opts}, else: false

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
