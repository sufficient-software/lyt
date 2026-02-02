defmodule Lyt.Test.TestLiveTrackAll do
  use Phoenix.LiveView
  use Lyt, track_all: true, exclude: ["excluded_event", "heartbeat"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :value, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("tracked_event", params, socket) do
    {:noreply, assign(socket, :value, params["value"])}
  end

  @impl true
  def handle_event("another_tracked", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("excluded_event", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("heartbeat", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Test LiveView with Track All</h1>
      <button phx-click="tracked_event" phx-value-value="test">Tracked</button>
      <button phx-click="another_tracked">Another Tracked</button>
      <button phx-click="excluded_event">Excluded</button>
      <button phx-click="heartbeat">Heartbeat</button>
    </div>
    """
  end
end
