# Configure the test repo
repo =
  case System.get_env("DATABASE", "sqlite3") do
    "sqlite" -> Lyt.Test.Sqlite3Repo
    "sqlite3" -> Lyt.Test.Sqlite3Repo
    _ -> raise "Unknown database"
  end

Application.put_env(:lyt, :repo, repo)

# Configure the test endpoint for Phoenix/LiveView integration tests
Application.put_env(:lyt, Lyt.Test.Endpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_signing_salt"],
  render_errors: [formats: [html: Lyt.Test.ErrorHTML]],
  pubsub_server: Lyt.Test.PubSub,
  server: false
)

# Start the repo
repo.__adapter__().storage_up(repo.config())
repo.start_link()
Ecto.Migrator.run(repo, :up, all: true, log_migrations_sql: false, log: false)

# Start PubSub for LiveView
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: Lyt.Test.PubSub)

# Start the endpoint
{:ok, _} = Lyt.Test.Endpoint.start_link()

# Attach telemetry handlers
Lyt.attach()

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
