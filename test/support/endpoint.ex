defmodule Lyt.Test.Endpoint do
  use Phoenix.Endpoint, otp_app: :lyt

  @session_options [
    store: :cookie,
    key: "_lyt_test_key",
    signing_salt: "test_signing_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.Session, @session_options)
  plug(Lyt.Test.Router)
end
