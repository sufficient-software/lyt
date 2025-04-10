repo =
  case System.get_env("DATABASE", "sqlite3") do
    "sqlite" -> PhxAnalytics.Test.Sqlite3Repo
    "sqlite3" -> PhxAnalytics.Test.Sqlite3Repo
    _ -> raise "Unknown database"
  end

Application.put_env(:phx_analytics, :repo, repo)
repo.__adapter__().storage_up(repo.config())
repo.start_link()
Ecto.Migrator.run(repo, :up, all: true, log_migrations_sql: false, log: false)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
