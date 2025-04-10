defmodule PhxAnalytics.Telemetry do
  require Logger
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_) do
    children = []

    case attach() do
      :ok ->
        Logger.info("Attached analytics to telemetry")

      _ ->
        Logger.error("Failed to attach analytics to telemetry")
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp attach() do
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

  def handle_event([:phoenix, :live_view, :mount, :stop], _measurement, _metadata, _config) do
    # Check if this is the first live view of the session
    #   - if it is, we want to ignore this one because the plug handler should have already gotten the view
    #   - is there a request id I can get somewhere?
    # Store a view in the database
  end

  def handle_event(
        [:phoenix, :live_view, :handle_params, :stop],
        _measurement,
        _metadata,
        _config
      ) do
    # Check if this is the first instance of handle params or not, if it is then the
    # analytics event is handled by mount or plug
    # At minimum, update the URI appropriately
  end

  def handle_event([:phoenix, :live_view, :handle_event, :stop], _measurement, metadata, _config) do
    if is_event_tracked?(metadata) do
      # Create an event
    end
  end

  def is_event_tracked?(metadata) do
    socket = metadata.socket
    view = socket.view
    tracking_rules = view.phx_analytics_tracked_events()
    Enum.find(tracking_rules, &tracking_rule_match?(view, metadata.event, &1)) != nil
  end

  def tracking_rule_match?(_view, observed_event, {:handle_event, [tracked_event]})
      when observed_event == tracked_event,
      do: true

  def tracking_rule_match?(_view, _event, _rule), do: false
end
