defmodule PhxAnalytics.Test.TestLiveBeforeSave do
  use Phoenix.LiveView
  use PhxAnalytics, track_all: true, before_save: &__MODULE__.module_before_save/3

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :should_track, true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("normal_event", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("halted_event", _params, socket) do
    {:noreply, assign(socket, :should_track, false)}
  end

  @impl true
  @analytics before_save: &__MODULE__.decorator_before_save/3
  def handle_event("decorator_halted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  @analytics before_save: &__MODULE__.modify_changeset/3
  def handle_event("modify_event", _params, socket) do
    {:noreply, socket}
  end

  # Module-level before_save - halts if should_track is false
  def module_before_save(changeset, _opts, socket) do
    if socket.assigns.should_track do
      {:ok, changeset}
    else
      :halt
    end
  end

  # Decorator-level before_save - always halts
  def decorator_before_save(_changeset, _opts, _socket) do
    :halt
  end

  # Decorator-level before_save - modifies the changeset
  def modify_changeset(changeset, _opts, _socket) do
    {:ok, Ecto.Changeset.put_change(changeset, :name, "Modified Event Name")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Test LiveView with Before Save</h1>
      <button phx-click="normal_event">Normal</button>
      <button phx-click="halted_event">Halted</button>
      <button phx-click="decorator_halted">Decorator Halted</button>
      <button phx-click="modify_event">Modify</button>
    </div>
    """
  end
end
