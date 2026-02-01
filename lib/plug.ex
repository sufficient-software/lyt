defmodule PhxAnalytics.Plug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    session_id = Map.get(conn.cookies, session_cookie_name())
    {conn, session} = get_or_create_session(conn, session_id)

    conn
    |> put_session(session_cookie_name(), session.id)
    |> put_private(:phx_analytics_session, session)
    |> put_private(:phx_analytics_opts, opts)
    |> register_before_send(&maybe_record_page_view/1)
  end

  defp session_cookie_name() do
    Application.get_env(:phx_analytics, :session_cookie_name, "phx_analytics_session")
  end

  def session_max_length(), do: Application.get_env(:phx_analytics, :session_length, 300)

  defp req_header_or_nil(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp liveview_request?(conn) do
    # Check if response body contains LiveView data-phx attributes
    # This is present in all LiveView-rendered pages
    case conn.resp_body do
      nil ->
        false

      body ->
        body_string = IO.iodata_to_binary(body)
        String.contains?(body_string, "data-phx-main")
    end
  end

  defp maybe_record_page_view(conn) do
    # Skip if this is a LiveView request - telemetry handler will record it
    # LiveView pages have the data-phx-main attribute in the response
    unless liveview_request?(conn) do
      record_page_view(conn)
    end

    conn
  end

  defp get_or_create_session(conn, nil) do
    session = queue_session(conn)

    conn =
      put_resp_cookie(conn, session_cookie_name(), session.id,
        max_age: session_max_length(),
        same_site: "Lax"
      )

    {conn, session}
  end

  defp get_or_create_session(conn, session_id) do
    case PhxAnalytics.Repo.get(PhxAnalytics.Session, session_id) do
      nil ->
        get_or_create_session(conn, nil)

      session ->
        # Re-queue the session to update it (upsert behavior)
        queue_session_update(conn, session)
        {conn, session}
    end
  end

  defp queue_session(conn) do
    %{
      id: PhxAnalytics.generate_session_id(),
      user_id: conn.assigns[:exa_id],
      hostname: conn.host,
      referrer: req_header_or_nil(conn, "referrer"),
      started_at: DateTime.utc_now(),
      entry: conn.request_path
    }
    |> Map.merge(PhxAnalytics.parse_user_agent(req_header_or_nil(conn, "user-agent")))
    |> Map.merge(PhxAnalytics.parse_utm(conn.params))
    |> PhxAnalytics.queue_session()
  end

  defp queue_session_update(conn, existing_session) do
    # Queue an update for the existing session (will upsert)
    %{
      id: existing_session.id,
      user_id: conn.assigns[:exa_id] || existing_session.user_id,
      hostname: existing_session.hostname,
      referrer: existing_session.referrer,
      started_at: existing_session.started_at,
      entry: existing_session.entry
    }
    |> Map.merge(PhxAnalytics.parse_user_agent(req_header_or_nil(conn, "user-agent")))
    |> Map.merge(PhxAnalytics.parse_utm(conn.params))
    |> PhxAnalytics.queue_session()
  end

  defp record_page_view(conn) do
    case conn.private[:phx_analytics_session] do
      nil ->
        :ok

      session ->
        opts = conn.private[:phx_analytics_opts] || []
        event_name = Keyword.get(opts, :event_name, "Page View")

        %{
          session_id: session.id,
          name: event_name,
          hostname: conn.host,
          path: conn.request_path,
          query: conn.query_string
        }
        |> PhxAnalytics.queue_event()
    end
  end
end
