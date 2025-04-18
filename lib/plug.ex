defmodule PhxAnalytics.Plug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.register_before_send(fn conn ->
      stored_session_id = Map.get(conn.cookies, session_cookie_name())

      session =
        %{
          id: stored_session_id,
          user_id: conn.assigns[:exa_id],
          hostname: conn.host,
          referrer: req_header_or_nil(conn, "referrer"),
          started_at: DateTime.utc_now(),
          entry: conn.request_path
        }
        |> Map.merge(PhxAnalytics.parse_user_agent(req_header_or_nil(conn, "user-agent")))
        |> Map.merge(PhxAnalytics.parse_utm(conn.params))
        |> PhxAnalytics.create_session()

      %{
        session_id: session.id,
        name: Keyword.get(opts, :event_name, "Page View"),
        path: conn.request_path,
        hostname: conn.host,
        query: conn.query_string
      }
      |> PhxAnalytics.create_event()

      conn
      |> put_resp_cookie(session_cookie_name(), session.id,
        max_age: session_max_length(),
        same_site: "Lax"
      )
      |> put_session(session_cookie_name(), session.id)
    end)
  end

  defp session_cookie_name() do
    Application.get_env(:phx_analytics, :session_cookie_name, "phx_analytics_session")
  end

  def session_max_length(), do: 300

  defp req_header_or_nil(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      _ -> nil
    end
  end
end
