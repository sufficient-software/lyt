defmodule Lyt.IntegrationTest do
  use Lyt.IntegrationCase

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
      session_cookie = conn.cookies["lyt_session"]

      # Second request with same session cookie
      conn2 =
        build_conn()
        |> put_req_cookie("lyt_session", session_cookie)
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

      # The event name defaults to the event handler name
      events = all_events()
      tracked_event = Enum.find(events, &(&1.name == "increment"))
      assert tracked_event != nil
      assert tracked_event.metadata["params"] != nil
    end

    test "does not track unannotated handle_event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")
      initial_event_count = event_count()

      # Click the untracked button
      render_click(view, "decrement")

      # Should not have created a new event
      assert event_count() == initial_event_count
    end

    test "tracks handle_event with custom metadata function", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      # Click the tracked with metadata button
      render_click(view, "tracked_with_metadata", %{"value" => "custom_value"})

      # Find event with custom metadata merged in
      events = all_events()

      metadata_event =
        Enum.find(events, fn e ->
          e.metadata != nil && e.metadata["custom"] == "custom_value"
        end)

      assert metadata_event != nil
      # Name defaults to event name when not specified
      assert metadata_event.name == "tracked_with_metadata"
      # Params are also included
      assert metadata_event.metadata["params"]["value"] == "custom_value"
    end

    test "tracks handle_event with custom name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      render_click(view, "custom_name_event")

      events = all_events()
      custom_event = Enum.find(events, &(&1.name == "Custom Event Name"))
      assert custom_event != nil
    end

    test "tracks handle_event with custom name and static metadata", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test")

      render_click(view, "full_custom_event")

      events = all_events()
      custom_event = Enum.find(events, &(&1.name == "Full Custom"))
      assert custom_event != nil
      assert custom_event.metadata["source"] == "test"
      assert custom_event.metadata["category"] == "button"
      # Params are still included
      assert custom_event.metadata["params"] != nil
    end
  end

  describe "include list tracking" do
    test "tracks events in the include list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-include")
      initial_event_count = event_count()

      # Click an included event
      render_click(view, "included_event", %{"value" => "test"})

      # Should have created an event
      assert event_count() == initial_event_count + 1
    end

    test "tracks multiple events in the include list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-include")
      initial_event_count = event_count()

      render_click(view, "included_event", %{"value" => "test"})
      render_click(view, "another_included")

      # Should have created two events
      assert event_count() == initial_event_count + 2
    end

    test "does not track events not in the include list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-include")
      initial_event_count = event_count()

      # Click a non-included event
      render_click(view, "not_included")

      # Should not have created an event
      assert event_count() == initial_event_count
    end
  end

  describe "track_all with exclude list" do
    test "tracks events not in the exclude list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-track-all")
      initial_event_count = event_count()

      render_click(view, "tracked_event", %{"value" => "test"})

      assert event_count() == initial_event_count + 1
    end

    test "tracks multiple events not in exclude list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-track-all")
      initial_event_count = event_count()

      render_click(view, "tracked_event", %{"value" => "test"})
      render_click(view, "another_tracked")

      assert event_count() == initial_event_count + 2
    end

    test "does not track events in the exclude list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-track-all")
      initial_event_count = event_count()

      render_click(view, "excluded_event")
      render_click(view, "heartbeat")

      # Neither excluded event should create analytics events
      assert event_count() == initial_event_count
    end
  end

  describe "before_save callback" do
    test "module-level before_save allows event to be saved", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-before-save")
      initial_event_count = event_count()

      render_click(view, "normal_event")

      assert event_count() == initial_event_count + 1
    end

    test "module-level before_save can halt event saving", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-before-save")

      # First click sets should_track to false
      render_click(view, "halted_event")
      initial_event_count = event_count()

      # Second click should be halted by before_save
      render_click(view, "normal_event")

      assert event_count() == initial_event_count
    end

    test "decorator-level before_save takes precedence over module-level", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-before-save")
      initial_event_count = event_count()

      # This event has a decorator-level before_save that always halts
      render_click(view, "decorator_halted")

      assert event_count() == initial_event_count
    end

    test "before_save can modify the changeset", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/live-test-before-save")

      render_click(view, "modify_event")

      events = all_events()
      modified_event = Enum.find(events, &(&1.name == "Modified Event Name"))
      assert modified_event != nil
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
        |> put_req_header("referer", "https://google.com/search?q=test")
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
