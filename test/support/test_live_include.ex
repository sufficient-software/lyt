defmodule Lyt.Test.TestLiveInclude do
  use Phoenix.LiveView
  use Lyt, include: ["included_event", "another_included"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :value, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("included_event", params, socket) do
    {:noreply, assign(socket, :value, params["value"])}
  end

  @impl true
  def handle_event("another_included", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("not_included", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Test LiveView with Include List</h1>
      <button phx-click="included_event" phx-value-value="test">Included</button>
      <button phx-click="another_included">Another Included</button>
      <button phx-click="not_included">Not Included</button>
    </div>
    """
  end
end
