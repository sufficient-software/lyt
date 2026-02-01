defmodule PhxAnalytics.Test.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Plug.Conn

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, false)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :with_analytics do
    plug(PhxAnalytics.Plug)
  end

  scope "/", PhxAnalytics.Test do
    pipe_through([:browser, :with_analytics])

    live("/live-test", TestLive)
    live("/live-test/:id", TestLive)
    live("/live-test-include", TestLiveInclude)
    live("/live-test-track-all", TestLiveTrackAll)
    get("/plug-test", PageController, :index)
  end

  # Routes without analytics for comparison
  scope "/no-analytics", PhxAnalytics.Test do
    pipe_through([:browser])

    live("/live-test", TestLive)
  end
end
