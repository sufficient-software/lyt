defmodule PhxAnalytics.Test.Sqlite3Repo do
  use Ecto.Repo,
    otp_app: :phx_analytics,
    adapter: Ecto.Adapters.SQLite3
end
