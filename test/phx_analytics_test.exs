defmodule PhxAnalyticsTest do
  use PhxAnalytics.Test.Case
  doctest PhxAnalytics

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
end
