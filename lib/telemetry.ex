defmodule PhxAnalytics.Telemetry do
  @moduledoc """
  Supervisor for PhxAnalytics processes.

  Starts the EventQueue GenServer and attaches telemetry handlers.

  Add this to your application supervision tree:

      children = [
        # ... other children
        PhxAnalytics.Telemetry
      ]
  """

  require Logger
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_) do
    children = [
      PhxAnalytics.EventQueue
    ]

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
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :handle_event, :stop]
      ],
      &PhxAnalytics.handle_event/4,
      nil
    )
  end
end
