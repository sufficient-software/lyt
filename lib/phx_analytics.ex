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
    |> Repo.insert!()
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
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :_phx_analytics_tracked_functions, accumulate: true)
      @before_compile PhxAnalytics
      @on_definition {PhxAnalytics, :__on_definition__}
      require PhxAnalytics
    end
  end

  defmacro __before_compile__(env) do
    tracked_event_handlers = Module.get_attribute(env.module, :_phx_analytics_tracked_functions)

    quote do
      def phx_analytics_tracked_event_handlers do
        unquote(Macro.escape(tracked_event_handlers))
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

    session_id = get_in(metadata, [:session, "phx_analytics_session_id"])

    Process.put(:phx_analytics_uri, uri)
    Process.put(:phx_analytics_session_id, session_id)

    %{
      session_id: session_id,
      name: "Live View",
      hostname: uri.host,
      path: uri.path,
      query: uri.query
    }
    |> create_event()
  end

  def handle_event([:phoenix, :live_view, :handle_event, _], _measurement, metadata, _config) do
    tracked_events = metadata.socket.view.phx_analytics_tracked_event_handlers()

    is_tracked =
      !is_nil(
        Enum.find(tracked_events, fn
          {:handle_event, [event]} ->
            event == metadata.event

          _ ->
            false
        end)
      )

    if(is_tracked) do
      session_id = Process.get(:phx_analytics_session_id)
      uri = Process.get(:phx_analytics_uri)

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

  def handle_event(_, _, _, _) do
    # Skip unknown event handlers
  end
end
