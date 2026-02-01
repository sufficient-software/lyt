defmodule PhxAnalyticsTest do
  use PhxAnalytics.Test.Case
  doctest PhxAnalytics

  setup_all do
    # Telemetry is already attached in test_helper.exs
    :ok
  end

  describe inspect(&PhxAnalytics.create_session/1) do
    test "create a new session" do
      session =
        PhxAnalytics.create_session(%{
          hostname: "localhost",
          entry: "/"
        })

      assert session.id != nil
    end

    test "upserts session metadata" do
      session =
        PhxAnalytics.create_session(%{
          hostname: "localhost",
          entry: "/"
        })

      assert session.id != nil

      new_session =
        PhxAnalytics.create_session(%{
          id: session.id,
          hostname: "localhost",
          entry: "/",
          metadata: %{
            "user_id" => "user123"
          }
        })

      assert new_session.id == session.id
      assert new_session.metadata == %{"user_id" => "user123"}
    end

    test "upsert doesn't override session entry data" do
      session =
        PhxAnalytics.create_session(%{
          hostname: "localhost",
          entry: "/"
        })

      assert session.id != nil

      new_session =
        PhxAnalytics.create_session(%{
          id: session.id,
          hostname: "localhost",
          entry: "/path",
          metadata: %{
            "user_id" => "user123"
          }
        })

      assert new_session.id == session.id
      assert new_session.entry == "/"
    end
  end

  describe inspect(&PhxAnalytics.create_event/1) do
    setup do
      session = PhxAnalytics.create_session()
      %{session: session}
    end

    test "create a new event", %{session: session} do
      event =
        PhxAnalytics.create_event(%{
          session_id: session.id,
          name: "page_view",
          path: "/home"
        })

      assert event.session_id == session.id
      assert event.name == "page_view"
      assert event.path == "/home"
    end
  end

  describe "@analytics macro" do
    test "@analytics true flags a handle_event to get flagged for tracking" do
      with_binary_module(
        """
        defmodule Test do
          use PhxAnalytics

          @analytics true
          def handle_event("testing", _params, socket) do
            {:noreply, socket}
          end
        end
        """,
        fn mod ->
          assert mod.phx_analytics_tracked_event_handlers() == [
                   {:handle_event, "testing", %{}}
                 ]
        end
      )
    end

    test "no @analytics means no handle_event gets flagged for tracking" do
      with_binary_module(
        """
        defmodule Test do
          use PhxAnalytics

          def handle_event("testing", _params, socket) do
            {:noreply, socket}
          end
        end
        """,
        fn mod ->
          assert mod.phx_analytics_tracked_event_handlers() == []
        end
      )
    end

    test "@analytics can handle interspersed tracking" do
      with_binary_module(
        """
        defmodule Test do
          use PhxAnalytics

          @analytics true
          def handle_event("testing", _params, socket) do
            {:noreply, socket}
          end

          def handle_event("testing2", _params, socket) do
            {:noreply, socket}
          end

          @analytics false
          def handle_event("testing3", _params, socket) do
            {:noreply, socket}
          end

          @analytics true
          def handle_event("testing4", _params, socket) do
            {:noreply, socket}
          end
        end
        """,
        fn mod ->
          assert mod.phx_analytics_tracked_event_handlers() == [
                   {:handle_event, "testing4", %{}},
                   {:handle_event, "testing", %{}}
                 ]
        end
      )
    end
  end

  describe "telemetry handler" do
    test "mount handler" do
      session =
        PhxAnalytics.create_session(%{
          hostname: "http://example.com",
          entry: "/"
        })

      :telemetry.execute(
        [:phoenix, :live_view, :mount, :stop],
        %{},
        %{
          uri: "http://example.com",
          session: %{"phx_analytics_session" => session.id},
          socket: %{transport_pid: self()}
        }
      )

      events = PhxAnalytics.Repo.all(PhxAnalytics.Event)
      assert length(events) == 1
      assert events |> hd |> Map.get(:session_id) == session.id
    end

    test "handle_params handler" do
      session =
        PhxAnalytics.create_session(%{
          hostname: "http://example.com",
          entry: "/"
        })

      with_binary_module(
        """
        defmodule Test do
          use PhxAnalytics

          @analytics true
          def handle_event("testing", _params, socket) do
            {:noreply, socket}
          end


        end
        """,
        fn mod ->
          Process.put(:phx_analytics_session_id, session.id)
          Process.put(:phx_analytics_uri, URI.parse("http://example.com"))

          :telemetry.execute(
            [:phoenix, :live_view, :handle_event, :stop],
            %{},
            %{
              uri: "http://example.com",
              event: "testing",
              socket: %{view: mod},
              params: %{},
              session: %{"phx_analytics_session_id" => session.id}
            }
          )

          events = PhxAnalytics.Repo.all(PhxAnalytics.Event)
          assert length(events) == 1
          assert events |> hd |> Map.get(:session_id) == session.id
        end
      )
    end
  end
end
