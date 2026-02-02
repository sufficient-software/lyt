defmodule Lyt.API.Session do
  @moduledoc """
  Session management for API requests.

  Sessions are derived deterministically from request data (user agent, IP, hostname)
  using `Lyt.derive_session_id/1`, allowing JavaScript clients to fire events
  immediately without waiting for session creation. The same client will always
  map to the same session ID.

  ## How It Works

  1. Session ID is derived from: `hash(salt + user_agent + remote_ip + hostname)`
  2. If no session exists with that ID, one is created automatically
  3. Same browser/IP/hostname always produces the same session ID

  This uses the same derivation logic as `Lyt.Plug`, ensuring that a user
  browsing via LiveView and sending events via the JavaScript API will
  have the same session ID.
  """

  import Plug.Conn

  @doc """
  Get or create a session for the given connection.

  Derives the session ID from request data using `Lyt.derive_session_id/1`,
  looks up the session in the database, and creates a new one if it doesn't exist.

  Returns `{:ok, session}` on success.
  """
  def get_or_create_session(conn, params \\ %{}) do
    session_id = Lyt.derive_session_id(conn)

    case Lyt.Repo.get(Lyt.Session, session_id) do
      nil ->
        session = create_session(conn, session_id, params)
        {:ok, session}

      session ->
        # Update session with any new data (screen dimensions, etc.)
        session = maybe_update_session(conn, session, params)
        {:ok, session}
    end
  end

  defp create_session(conn, session_id, params) do
    user_agent = get_req_header(conn, "user-agent") |> List.first()
    referrer = get_req_header(conn, "referer") |> List.first()

    attrs =
      %{
        id: session_id,
        hostname: conn.host,
        referrer: referrer,
        started_at: DateTime.utc_now(),
        entry: params["path"] || "/"
      }
      |> maybe_add_screen_dimensions(params)
      |> Map.merge(Lyt.parse_user_agent(user_agent))
      |> Map.merge(Lyt.parse_utm(params))

    Lyt.queue_session(attrs)
  end

  defp maybe_update_session(_conn, session, params) do
    # If screen dimensions provided and session doesn't have them, update
    if has_screen_dimensions?(params) && !has_screen_dimensions?(session) do
      attrs =
        %{
          id: session.id,
          hostname: session.hostname,
          referrer: session.referrer,
          started_at: session.started_at,
          entry: session.entry,
          screen_width: params["screen_width"],
          screen_height: params["screen_height"]
        }

      Lyt.queue_session(attrs)
    end

    session
  end

  defp has_screen_dimensions?(%{"screen_width" => w, "screen_height" => h})
       when is_integer(w) and is_integer(h),
       do: true

  defp has_screen_dimensions?(%Lyt.Session{screen_width: w, screen_height: h})
       when not is_nil(w) and not is_nil(h),
       do: true

  defp has_screen_dimensions?(_), do: false

  defp maybe_add_screen_dimensions(attrs, params) do
    attrs
    |> maybe_put(:screen_width, params["screen_width"])
    |> maybe_put(:screen_height, params["screen_height"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
