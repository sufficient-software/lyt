# Installation Guide

This guide walks you through installing and configuring PhxAnalytics in a Phoenix application.

## Prerequisites

- Elixir 1.17 or later
- Phoenix 1.7 or later
- Phoenix LiveView 1.0 or later
- One of the supported databases: PostgreSQL, MySQL, SQLite3, or DuckDB

## Step 1: Add the Dependency

Add `phx_analytics` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phx_analytics, "~> 0.1.0"}
  ]
end
```

PhxAnalytics works with your existing database adapter. Make sure you have one of these adapters in your dependencies:

```elixir
# PostgreSQL (most common)
{:postgrex, ">= 0.0.0"}

# MySQL
{:myxql, ">= 0.0.0"}

# SQLite3
{:ecto_sqlite3, ">= 0.0.0"}

# DuckDB
{:ecto_duckdb, ">= 0.0.0"}
```

Then fetch the dependencies:

```bash
mix deps.get
```

## Step 2: Configure the Repository

Tell PhxAnalytics which Ecto repository to use. Add this to your `config/config.exs`:

```elixir
# config/config.exs
config :phx_analytics, :repo, MyApp.Repo
```

Replace `MyApp.Repo` with your application's actual Repo module name.

## Step 3: Create the Migration

Generate a new migration file:

```bash
mix ecto.gen.migration create_phx_analytics_tables
```

Open the generated file in `priv/repo/migrations/` and replace its contents with:

```elixir
defmodule MyApp.Repo.Migrations.CreatePhxAnalyticsTables do
  use Ecto.Migration

  def up do
    PhxAnalytics.Migration.up()
  end

  def down do
    PhxAnalytics.Migration.down()
  end
end
```

Run the migration:

```bash
mix ecto.migrate
```

This creates three tables in your database:

- `phx_analytics_meta` - Internal migration tracking
- `phx_analytics_sessions` - User session data
- `phx_analytics_events` - Page views and custom events

## Step 4: Add to Supervision Tree

Add `PhxAnalytics.Telemetry` to your application's supervision tree. Open `lib/my_app/application.ex` and add it to the children list:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyAppWeb.Telemetry,
      MyApp.Repo,
      PhxAnalytics.Telemetry,  # Add this line
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch},
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

> **Important:** Add `PhxAnalytics.Telemetry` after your `Repo` but before your `Endpoint`.

## Step 5: Add the Plug

Add `PhxAnalytics.Plug` to your browser pipeline in `lib/my_app_web/router.ex`:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug PhxAnalytics.Plug  # Add this line
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # ...
end
```

> **Note:** The plug must come after `:fetch_session` since it uses the session to store the analytics session ID.

## Step 6: Verify Installation

Start your Phoenix server:

```bash
mix phx.server
```

Visit a few pages in your browser, then check if analytics are being recorded:

```elixir
# In IEx (iex -S mix)
import Ecto.Query

# Check for sessions
MyApp.Repo.all(PhxAnalytics.Session) |> length()

# Check for events
MyApp.Repo.all(PhxAnalytics.Event) |> length()
```

You should see sessions and events being created as you browse your application.

## Next Steps

Now that PhxAnalytics is installed, you can:

- Track custom events in your LiveView modules using the `@analytics` decorator
- Configure tracking options like excluded paths and session length
- Query your analytics data using Ecto to build dashboards

See the `PhxAnalytics` module documentation for detailed usage examples.

## Troubleshooting

### Events not being recorded

1. **Check the supervision tree** - Ensure `PhxAnalytics.Telemetry` is in your application's children list
2. **Check the plug order** - `PhxAnalytics.Plug` must come after `:fetch_session`
3. **Check the repo config** - Verify `config :phx_analytics, :repo, MyApp.Repo` is set correctly

### Migration errors

If you get migration errors, check that:

1. Your database adapter is supported (PostgreSQL, MySQL, SQLite3, or DuckDB)
2. The repo is properly configured before running migrations

### LiveView events not tracked

LiveView tracking requires:

1. `PhxAnalytics.Telemetry` in your supervision tree (attaches telemetry handlers)
2. The session cookie to be passed to LiveView via the Plug

## Test Configuration

For testing, enable synchronous mode to avoid timing issues with the async event queue:

```elixir
# config/test.exs
config :phx_analytics, :sync_mode, true
```

This ensures events are inserted immediately rather than being batched, making tests deterministic.
