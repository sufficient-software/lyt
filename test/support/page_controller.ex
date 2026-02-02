defmodule Lyt.Test.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<html><body><h1>Test Page</h1></body></html>")
  end
end
