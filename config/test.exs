import Config

config :phx_analytics, PhxAnalytics.Test.Sqlite3Repo,
  database: "priv/repo/sqlite3/test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/repo",
  log: false

config :phx_analytics, ecto_repos: [PhxAnalytics.Test.Sqlite3Repo]
config :phx_analytics, otp_app: :phx_analytics
