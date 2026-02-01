defmodule PhxAnalytics.IntegrationTest do
  use PhxAnalytics.IntegrationCase

  describe "Plug integration" do
    test "creates session on regular page request", %{conn: conn} do
      conn = get(conn, "/plug-test")
      assert html_response(conn, 200) =~ "Test Page"

      # Session should be created
      assert [session] = all_sessions()
      assert session.entry == "/plug-test"
      assert session.hostname == "www.example.com"

      # Event should be created for non-LiveView page
      assert [event] = all_events()
      assert event.name == "Page View"
      assert event.path == "/plug-test"
      assert event.session_id == session.id
    end

    test "reuses existing session across requests", %{conn: conn} do
      # First request creates session
      conn = get(conn, "/plug-test")
      assert [session] = all_sessions()

      # Get the session cookie
      session_cookie = conn.cookies["phx_analytics_session"]

      # Second request with same session cookie
      conn2 =
        build_conn()
        |> put_req_cookie("phx_analytics_session", session_cookie)
        |> get("/plug-test")

      assert html_response(conn2, 200)

      # Should still be only one session
      assert [^session] = all_sessions()

      # But two events
      assert length(all_events()) == 2
    end
  end

  describe "LiveView integration" do
    test "creates session and event on LiveView mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/live-test")
      assert html =~ "Test LiveView"

      # Session should be created by the Plug
      assert [session] = all_sessions()
      assert session.entry == "/live-test"

      # Event should be created by telemetry handler
      assert [event] = all_events()
      assert event.name == "Live View"
      assert event.path == "/live-test"
      assert event.session_id == session.id
    end

    test "tracks handle_params on navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      # Navigate to a different path using patch
      html = render_patch(view, "/live-test/123")
      assert html =~ "ID: 123"

      # Should have events for both paths
      events = all_events()
      paths = Enum.map(events, & &1.path)
      assert "/live-test" in paths
      assert "/live-test/123" in paths
    end

    test "tracks annotated handle_event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      # Clear events from mount to isolate test
      initial_event_count = event_count()

      # Click the tracked button
      render_click(view, "increment")

      # Should have created an event for the tracked handle_event
      assert event_count() == initial_event_count + 1

      # The event is created with name "Live View" and metadata containing params
      events = all_events()
      tracked_event = Enum.find(events, &(&1.metadata != nil && &1.metadata["params"] != nil))
      assert tracked_event != nil
      assert tracked_event.name == "Live View"
    end

    test "does not track unannotated handle_event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")
      initial_event_count = event_count()

      # Click the untracked button
      render_click(view, "decrement")

      # Should not have created a new event
      assert event_count() == initial_event_count
    end

    test "tracks handle_event with custom metadata", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      # Click the tracked with metadata button
      render_click(view, "tracked_with_metadata", %{"value" => "custom_value"})

      # Find event with params in metadata
      events = all_events()

      metadata_event =
        Enum.find(events, fn e ->
          e.metadata != nil && e.metadata["params"] != nil &&
            e.metadata["params"]["value"] == "custom_value"
        end)

      assert metadata_event != nil
      assert metadata_event.name == "Live View"
    end
  end

  describe "session data" do
    test "captures browser info from user agent", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        |> get("/plug-test")

      assert html_response(conn, 200)

      [session] = all_sessions()
      assert session.browser == "Chrome"
      assert session.operating_system == "Mac"
    end

    test "captures referrer", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referrer", "https://google.com/search?q=test")
        |> get("/plug-test")

      assert html_response(conn, 200)

      [session] = all_sessions()
      assert session.referrer == "https://google.com/search?q=test"
    end

    test "captures UTM parameters", %{conn: conn} do
      conn =
        get(conn, "/plug-test?utm_source=newsletter&utm_medium=email&utm_campaign=spring_sale")

      assert html_response(conn, 200)

      [session] = all_sessions()
      assert session.utm_source == "newsletter"
      assert session.utm_medium == "email"
      assert session.utm_campaign == "spring_sale"
    end
  end
end
