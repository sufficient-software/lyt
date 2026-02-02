defmodule LytTest.PlugTest do
  use Lyt.Test.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Lyt.{Session, Event, Repo}

  @opts Lyt.Plug.init([])
  @session_opts Plug.Session.init(store: :cookie, key: "_lyt_key", signing_salt: "salt")

  defp configure_session(conn) do
    conn
    |> Map.put(:secret_key_base, String.duplicate("a", 64))
    |> Plug.Session.call(@session_opts)
    |> fetch_query_params()
    |> fetch_session()
  end

  test "creates a session and event on request" do
    conn =
      conn(:get, "/test_path?utm_source=test_source")
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
      )
      |> put_req_header("referer", "http://example.com")
      |> configure_session()
      |> Lyt.Plug.call(@opts)
      |> send_resp(200, "OK")

    assert Map.has_key?(get_resp_cookies(conn), "lyt_session")
    assert get_session(conn, "lyt_session")

    session = Repo.one(Session)
    assert session
    assert session.hostname == "www.example.com"
    assert session.referrer == "http://example.com"
    assert session.entry == "/test_path"
    assert session.utm_source == "test_source"

    event = Repo.one(Event)
    assert event
    assert event.session_id == session.id
    assert event.name == "Page View"
    assert event.path == "/test_path"
    assert event.hostname == "www.example.com"
    assert event.query == "utm_source=test_source"
  end

  test "uses custom event name if provided in opts" do
    opts = Lyt.Plug.init(event_name: "Custom Event")

    conn(:get, "/custom_event_path")
    |> configure_session()
    |> Lyt.Plug.call(opts)
    |> send_resp(200, "OK")

    event = Repo.one(Event)
    assert event.name == "Custom Event"
  end

  test "handles missing user-agent and referrer headers gracefully" do
    conn(:get, "/no_headers_path")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    session = Repo.one(Session)
    assert session
    assert session.browser == "Unknown"
    assert session.referrer == nil

    event = Repo.one(Event)
    assert event
    assert event.session_id == session.id
    assert event.path == "/no_headers_path"
  end

  test "creates a new session if no session cookie is present" do
    conn(:get, "/new_session_path")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    session = Repo.one(Session)
    assert session
  end

  test "reuses existing session for same client (same user-agent and IP)" do
    # First request creates a session
    conn(:get, "/first_path")
    |> put_req_header("user-agent", "TestBrowser/1.0")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    session = Repo.one(Session)
    assert session

    # Second request with same user-agent and IP should reuse the session
    conn(:get, "/second_path")
    |> put_req_header("user-agent", "TestBrowser/1.0")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    all_sessions = Repo.all(Session)
    assert length(all_sessions) == 1
    assert session.id == hd(all_sessions).id

    events = Repo.all(Event)
    assert length(events) == 2
    assert Enum.all?(events, &(&1.session_id == session.id))
  end

  test "creates different sessions for different clients" do
    # First request
    conn(:get, "/path")
    |> put_req_header("user-agent", "Browser/1.0")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    # Second request with different user-agent
    conn(:get, "/path")
    |> put_req_header("user-agent", "DifferentBrowser/2.0")
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    all_sessions = Repo.all(Session)
    assert length(all_sessions) == 2
  end
end
