defmodule PhxAnalytics.Test.TestLive do
  use Phoenix.LiveView
  use PhxAnalytics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :id, params["id"])}
  end

  @impl true
  @analytics true
  def handle_event("increment", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  @impl true
  def handle_event("decrement", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
  end

  @impl true
  @analytics metadata: &__MODULE__.event_metadata/1
  def handle_event("tracked_with_metadata", params, socket) do
    {:noreply, assign(socket, :last_params, params)}
  end

  @impl true
  @analytics name: "Custom Event Name"
  def handle_event("custom_name_event", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  @analytics name: "Full Custom", metadata: %{"source" => "test", "category" => "button"}
  def handle_event("full_custom_event", _params, socket) do
    {:noreply, socket}
  end

  def event_metadata(params), do: %{"custom" => params["value"]}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Test LiveView</h1>
      <p>Count: <%= @count %></p>
      <p :if={assigns[:id]}>ID: <%= @id %></p>
      <button phx-click="increment">Increment</button>
      <button phx-click="decrement">Decrement</button>
      <button phx-click="tracked_with_metadata" phx-value-value="test">Tracked</button>
    </div>
    """
  end
end
