defmodule Lyt.IntegrationCase do
  @moduledoc """
  This module defines the test case to be used by integration tests
  that require a full Phoenix/LiveView stack.

  ## Usage

      defmodule MyIntegrationTest do
        use Lyt.IntegrationCase

        test "tracks page views", %{conn: conn} do
          {:ok, view, _html} = live(conn, "/live-test")

          # Verify session was created
          assert [session] = all_sessions()
          assert session.entry == "/live-test"
        end
      end

  ## Available Helpers

  - `all_sessions/0` - Returns all analytics sessions
  - `all_events/0` - Returns all analytics events
  - `events_for_session/1` - Returns events for a specific session
  - `clear_analytics/0` - Clears all sessions and events
  - `live/2` - Mount a LiveView (from Phoenix.LiveViewTest)
  - `render_click/2,3` - Click an element in a LiveView
  - `render_patch/2` - Patch navigate a LiveView
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Lyt.IntegrationCase

      alias Lyt.{Session, Event, Repo}

      @endpoint Lyt.Test.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo(), shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Ensure telemetry handlers are attached for each test
    ensure_telemetry_attached()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Returns all analytics sessions ordered by insertion time.
  """
  def all_sessions do
    import Ecto.Query
    repo().all(from(s in Lyt.Session, order_by: [asc: s.inserted_at]))
  end

  @doc """
  Returns all analytics events ordered by timestamp.
  """
  def all_events do
    import Ecto.Query
    repo().all(from(e in Lyt.Event, order_by: [asc: e.timestamp]))
  end

  @doc """
  Returns all events for a specific session.
  """
  def events_for_session(session_id) do
    import Ecto.Query

    repo().all(
      from(e in Lyt.Event,
        where: e.session_id == ^session_id,
        order_by: [asc: e.timestamp]
      )
    )
  end

  @doc """
  Clears all analytics data (sessions and events).
  """
  def clear_analytics do
    repo().delete_all(Lyt.Event)
    repo().delete_all(Lyt.Session)
  end

  @doc """
  Returns the count of sessions.
  """
  def session_count do
    repo().aggregate(Lyt.Session, :count)
  end

  @doc """
  Returns the count of events.
  """
  def event_count do
    repo().aggregate(Lyt.Event, :count)
  end

  defp repo do
    Application.fetch_env!(:lyt, :repo)
  end

  defp ensure_telemetry_attached do
    handlers = :telemetry.list_handlers([:phoenix, :live_view, :mount, :stop])

    unless Enum.any?(handlers, fn %{id: id} -> id == "lyt" end) do
      Lyt.attach()
    end
  end
end
