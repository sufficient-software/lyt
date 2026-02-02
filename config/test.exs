import Config

config :lyt, Lyt.Test.Sqlite3Repo,
  database: "priv/repo/sqlite3/test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/repo",
  log: false

config :lyt, ecto_repos: [Lyt.Test.Sqlite3Repo]
config :lyt, otp_app: :lyt

# Disable logging in tests (only show errors for critical issues)
config :logger, level: :none

# Disable Phoenix debug logs
config :phoenix, :logger, false

# Use synchronous mode for tests to avoid sandbox issues with the EventQueue GenServer
config :lyt, sync_mode: true
