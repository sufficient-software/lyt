defmodule LytTest.PlugTest do
  use Lyt.Test.Case, async: true
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
      |> put_req_header("referrer", "http://example.com")
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

  test "reuses existing session if session cookie is present" do
    existing_session =
      %Session{id: "existing_session_id"}
      |> Repo.insert!()

    conn(:get, "/existing_session_path")
    |> put_resp_cookie("lyt_session", existing_session.id)
    |> configure_session()
    |> Lyt.Plug.call(@opts)
    |> send_resp(200, "OK")

    all_sessions = Repo.all(Session)
    assert length(all_sessions) == 1
    assert existing_session.id == hd(all_sessions).id

    event = Repo.one(Event)
    assert event
    assert event.session_id == existing_session.id
    assert event.path == "/existing_session_path"
  end
end
