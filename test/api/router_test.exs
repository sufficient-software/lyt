defmodule LytTest.API.RouterTest do
  use Lyt.Test.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Lyt.{Session, Event, Repo}
  alias Lyt.API.Router

  @opts Router.init([])

  defp call_router(conn) do
    conn
    |> Router.call(@opts)
  end

  defp json_conn(method, path, body \\ nil) do
    conn = conn(method, path, body && Jason.encode!(body))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0")
  end

  describe "POST /event" do
    test "creates session and event on first request" do
      conn =
        json_conn(:post, "/event", %{"name" => "Page View", "path" => "/home"})
        |> call_router()

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      # Session should be created
      session = Repo.one(Session)
      assert session
      assert session.hostname == "www.example.com"

      # Event should be created with session reference
      event = Repo.one(Event)
      assert event
      assert event.name == "Page View"
      assert event.path == "/home"
      assert event.session_id == session.id
    end

    test "same client gets same session on subsequent requests" do
      # First request
      conn1 =
        json_conn(:post, "/event", %{"name" => "Page View", "path" => "/home"})
        |> call_router()

      assert conn1.status == 200

      # Second request with same user agent and IP
      conn2 =
        json_conn(:post, "/event", %{"name" => "Click", "path" => "/home"})
        |> call_router()

      assert conn2.status == 200

      # Should have 1 session and 2 events
      sessions = Repo.all(Session)
      assert length(sessions) == 1

      events = Repo.all(Event)
      assert length(events) == 2
      assert Enum.all?(events, &(&1.session_id == hd(sessions).id))
    end

    test "different user agents get different sessions" do
      conn1 =
        json_conn(:post, "/event", %{"name" => "Page View", "path" => "/home"})
        |> call_router()

      assert conn1.status == 200

      conn2 =
        conn(:post, "/event", Jason.encode!(%{"name" => "Page View", "path" => "/home"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("user-agent", "Mozilla/5.0 Firefox/89.0")
        |> call_router()

      assert conn2.status == 200

      sessions = Repo.all(Session)
      assert length(sessions) == 2
    end

    test "includes metadata in event" do
      conn =
        json_conn(:post, "/event", %{
          "name" => "Button Click",
          "path" => "/dashboard",
          "metadata" => %{"button_id" => "signup", "variant" => "blue"}
        })
        |> call_router()

      assert conn.status == 200

      event = Repo.one(Event)
      assert event.metadata == %{"button_id" => "signup", "variant" => "blue"}
    end

    test "captures screen dimensions on session" do
      conn =
        json_conn(:post, "/event", %{
          "name" => "Page View",
          "path" => "/home",
          "screen_width" => 1920,
          "screen_height" => 1080
        })
        |> call_router()

      assert conn.status == 200

      session = Repo.one(Session)
      assert session.screen_width == 1920
      assert session.screen_height == 1080
    end

    test "captures UTM parameters on session" do
      conn =
        json_conn(:post, "/event", %{
          "name" => "Page View",
          "path" => "/home",
          "utm_source" => "google",
          "utm_medium" => "cpc",
          "utm_campaign" => "spring_sale"
        })
        |> call_router()

      assert conn.status == 200

      session = Repo.one(Session)
      assert session.utm_source == "google"
      assert session.utm_medium == "cpc"
      assert session.utm_campaign == "spring_sale"
    end

    test "returns validation error when name is missing" do
      conn =
        json_conn(:post, "/event", %{"path" => "/home"})
        |> call_router()

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert body["error"] == "validation_error"
      assert body["details"]["name"]
    end

    test "returns validation error when name is empty" do
      conn =
        json_conn(:post, "/event", %{"name" => "", "path" => "/home"})
        |> call_router()

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
    end
  end

  describe "POST /events (batch)" do
    test "creates multiple events in a batch" do
      conn =
        json_conn(:post, "/events", %{
          "events" => [
            %{"name" => "Page View", "path" => "/home"},
            %{"name" => "Scroll", "metadata" => %{"depth" => 50}},
            %{"name" => "Click", "path" => "/home", "metadata" => %{"element" => "cta"}}
          ]
        })
        |> call_router()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert body["queued"] == 3

      events = Repo.all(Event)
      assert length(events) == 3

      # All events should have the same session
      session_ids = events |> Enum.map(& &1.session_id) |> Enum.uniq()
      assert length(session_ids) == 1
    end

    test "returns validation error when events is not an array" do
      conn =
        json_conn(:post, "/events", %{"events" => "not an array"})
        |> call_router()

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert body["details"]["events"]
    end

    test "returns validation error when events array is empty" do
      conn =
        json_conn(:post, "/events", %{"events" => []})
        |> call_router()

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
    end

    test "returns validation error for invalid events in batch" do
      conn =
        json_conn(:post, "/events", %{
          "events" => [
            %{"name" => "Valid Event"},
            %{"path" => "/missing-name"},
            %{"name" => "Another Valid"}
          ]
        })
        |> call_router()

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      # Should indicate which event failed
      assert Map.has_key?(body["details"], "events[1].name")
    end
  end

  describe "session derivation" do
    test "derives consistent session ID from same request data" do
      # Make two identical requests
      conn1 = json_conn(:post, "/event", %{"name" => "Event 1"}) |> call_router()
      conn2 = json_conn(:post, "/event", %{"name" => "Event 2"}) |> call_router()

      assert conn1.status == 200
      assert conn2.status == 200

      # Should have created only one session
      assert length(Repo.all(Session)) == 1
      assert length(Repo.all(Event)) == 2
    end

    test "derives different session ID for different IPs" do
      conn1 =
        json_conn(:post, "/event", %{"name" => "Event 1"})
        |> Map.put(:remote_ip, {192, 168, 1, 1})
        |> call_router()

      conn2 =
        json_conn(:post, "/event", %{"name" => "Event 2"})
        |> Map.put(:remote_ip, {192, 168, 1, 2})
        |> call_router()

      assert conn1.status == 200
      assert conn2.status == 200

      # Should have created two sessions
      assert length(Repo.all(Session)) == 2
    end
  end

  describe "error handling" do
    test "returns 404 for unknown endpoints" do
      conn =
        json_conn(:get, "/unknown")
        |> call_router()

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert body["error"] == "not_found"
    end
  end

  describe "before_save callback" do
    setup do
      # Store original config
      original = Application.get_env(:lyt, Lyt.API.Router)

      on_exit(fn ->
        if original do
          Application.put_env(:lyt, Lyt.API.Router, original)
        else
          Application.delete_env(:lyt, Lyt.API.Router)
        end
      end)

      :ok
    end

    test "allows events when callback returns {:ok, changeset}" do
      Application.put_env(:lyt, Lyt.API.Router,
        before_save: fn changeset, _conn -> {:ok, changeset} end
      )

      conn =
        json_conn(:post, "/event", %{"name" => "Test Event"})
        |> call_router()

      assert conn.status == 200
      assert length(Repo.all(Event)) == 1
    end

    test "halts events when callback returns :halt" do
      Application.put_env(:lyt, Lyt.API.Router, before_save: fn _changeset, _conn -> :halt end)

      conn =
        json_conn(:post, "/event", %{"name" => "Test Event"})
        |> call_router()

      # Should still return success (silent drop)
      assert conn.status == 200
      # But no event should be created
      assert length(Repo.all(Event)) == 0
    end

    test "callback can modify the changeset" do
      Application.put_env(:lyt, Lyt.API.Router,
        before_save: fn changeset, _conn ->
          {:ok, Ecto.Changeset.put_change(changeset, :name, "Modified Name")}
        end
      )

      conn =
        json_conn(:post, "/event", %{"name" => "Original Name"})
        |> call_router()

      assert conn.status == 200
      event = Repo.one(Event)
      assert event.name == "Modified Name"
    end
  end
end
