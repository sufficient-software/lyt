defmodule Lyt.API.Router do
  @moduledoc """
  REST API router for JavaScript analytics tracking.

  This router provides endpoints for tracking analytics events from JavaScript
  clients. Sessions are derived automatically from request data (user agent, IP,
  hostname), so clients can fire events immediately without waiting for session
  creation.

  ## Setup

  Mount in your Phoenix router:

      forward "/api/analytics", Lyt.API.Router

  ## Endpoints

    * `POST /event` - Track a single event
    * `POST /events` - Track multiple events (batch)

  ## Request Format

  ### Single Event (`POST /event`)

      {
        "name": "Button Click",
        "path": "/dashboard",
        "metadata": {"button_id": "signup"}
      }

  ### Batch Events (`POST /events`)

      {
        "events": [
          {"name": "Page View", "path": "/home"},
          {"name": "Scroll Depth", "metadata": {"depth": 50}}
        ]
      }

  ## Optional Fields

  These can be included with any event to enrich session data:

    * `screen_width` - Screen width in pixels (captured on session creation)
    * `screen_height` - Screen height in pixels
    * `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` - UTM parameters

  ## Configuration

      config :lyt, Lyt.API.Router,
        max_batch_size: 100,        # Maximum events per batch request
        max_metadata_size: 10_240,  # Maximum metadata size in bytes (10KB)
        max_name_length: 255,       # Maximum event name length
        before_save: &MyModule.filter/2  # Optional callback

  ## CORS

  This router does not handle CORS. Configure CORS in your Phoenix pipeline
  or use a library like `cors_plug` if needed for cross-origin requests.

  ## Before Save Callback

  You can configure a callback to filter or modify events before saving:

      config :lyt, Lyt.API.Router,
        before_save: fn changeset, conn ->
          if bot_request?(conn) do
            :halt
          else
            {:ok, changeset}
          end
        end

  The callback receives `(changeset, conn)` and should return:
    * `{:ok, changeset}` - Proceed with saving (optionally modified)
    * `:halt` - Skip saving this event
  """

  use Plug.Router

  alias Lyt.API.{Session, Validator, Error}

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  post "/event" do
    with {:ok, validated} <- Validator.validate_event(conn.body_params),
         {:ok, session} <- Session.get_or_create_session(conn, conn.body_params),
         {:ok, changeset} <- build_event_changeset(validated, session.id, conn),
         {:ok, final_changeset} <- run_before_save(changeset, conn) do
      queue_event(final_changeset)
      json_response(conn, 200, %{ok: true})
    else
      {:error, {:validation, _} = err} -> Error.respond(conn, err)
      {:error, :halted} -> json_response(conn, 200, %{ok: true})
      {:error, _} -> Error.respond(conn, :internal_error)
    end
  end

  post "/events" do
    with {:ok, events} <- Validator.validate_batch(conn.body_params),
         {:ok, session} <- Session.get_or_create_session(conn, conn.body_params) do
      queued_count = process_batch_events(events, session.id, conn)
      json_response(conn, 200, %{ok: true, queued: queued_count})
    else
      {:error, {:validation, _} = err} -> Error.respond(conn, err)
      {:error, _} -> Error.respond(conn, :internal_error)
    end
  end

  match _ do
    Error.respond(conn, :not_found)
  end

  defp process_batch_events(events, session_id, conn) do
    Enum.reduce(events, 0, fn event_params, count ->
      with {:ok, changeset} <- build_event_changeset(event_params, session_id, conn),
           {:ok, final_changeset} <- run_before_save(changeset, conn) do
        queue_event(final_changeset)
        count + 1
      else
        _ -> count
      end
    end)
  end

  defp build_event_changeset(params, session_id, conn) do
    attrs = %{
      session_id: session_id,
      name: params["name"],
      path: params["path"] || "/",
      query: params["query"],
      hostname: params["hostname"] || conn.host,
      metadata: params["metadata"]
    }

    {:ok, Lyt.Event.changeset(%Lyt.Event{}, attrs)}
  end

  defp queue_event(changeset) do
    if sync_mode?() do
      Lyt.Repo.insert(changeset)
    else
      Lyt.EventQueue.queue_event_changeset(changeset)
    end
  end

  defp run_before_save(changeset, conn) do
    case config()[:before_save] do
      nil ->
        {:ok, changeset}

      fun when is_function(fun, 2) ->
        case fun.(changeset, conn) do
          {:ok, cs} -> {:ok, cs}
          :halt -> {:error, :halted}
          _ -> {:error, :halted}
        end

      _ ->
        {:ok, changeset}
    end
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp config do
    Application.get_env(:lyt, __MODULE__, [])
  end

  defp sync_mode? do
    Application.get_env(:lyt, :sync_mode, false)
  end
end
