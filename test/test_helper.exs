# Configure the test repo
repo =
  case System.get_env("DATABASE", "sqlite3") do
    "sqlite" -> PhxAnalytics.Test.Sqlite3Repo
    "sqlite3" -> PhxAnalytics.Test.Sqlite3Repo
    _ -> raise "Unknown database"
  end

Application.put_env(:phx_analytics, :repo, repo)

# Configure the test endpoint for Phoenix/LiveView integration tests
Application.put_env(:phx_analytics, PhxAnalytics.Test.Endpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_signing_salt"],
  render_errors: [formats: [html: PhxAnalytics.Test.ErrorHTML]],
  pubsub_server: PhxAnalytics.Test.PubSub,
  server: false
)

# Start the repo
repo.__adapter__().storage_up(repo.config())
repo.start_link()
Ecto.Migrator.run(repo, :up, all: true, log_migrations_sql: false, log: false)

# Start PubSub for LiveView
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: PhxAnalytics.Test.PubSub)

# Start the endpoint
{:ok, _} = PhxAnalytics.Test.Endpoint.start_link()

# Attach telemetry handlers
PhxAnalytics.attach()

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
