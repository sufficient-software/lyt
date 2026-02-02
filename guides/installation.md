# Installation Guide

This guide walks you through installing and configuring Lyt in a Phoenix application.

## Prerequisites

- Elixir 1.17 or later
- Phoenix 1.7 or later
- Phoenix LiveView 1.0 or later
- One of the supported databases: PostgreSQL, MySQL, SQLite3, or DuckDB

## Step 1: Add the Dependency

Add `lyt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lyt, "~> 0.1.0"}
  ]
end
```

Lyt works with your existing database adapter. Make sure you have one of these adapters in your dependencies:

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

Tell Lyt which Ecto repository to use. Add this to your `config/config.exs`:

```elixir
# config/config.exs
config :lyt, :repo, MyApp.Repo
```

Replace `MyApp.Repo` with your application's actual Repo module name.

## Step 3: Create the Migration

Generate a new migration file:

```bash
mix ecto.gen.migration create_lyt_tables
```

Open the generated file in `priv/repo/migrations/` and replace its contents with:

```elixir
defmodule MyApp.Repo.Migrations.CreateLytTables do
  use Ecto.Migration

  def up do
    Lyt.Migration.up()
  end

  def down do
    Lyt.Migration.down()
  end
end
```

Run the migration:

```bash
mix ecto.migrate
```

This creates three tables in your database:

- `lyt_meta` - Internal migration tracking
- `lyt_sessions` - User session data
- `lyt_events` - Page views and custom events

## Step 4: Add to Supervision Tree

Add `Lyt.Telemetry` to your application's supervision tree. Open `lib/my_app/application.ex` and add it to the children list:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyAppWeb.Telemetry,
      MyApp.Repo,
      Lyt.Telemetry,  # Add this line
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

> **Important:** Add `Lyt.Telemetry` after your `Repo` but before your `Endpoint`.

## Step 5: Add the Plug

Add `Lyt.Plug` to your browser pipeline in `lib/my_app_web/router.ex`:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug Lyt.Plug  # Add this line
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
MyApp.Repo.all(Lyt.Session) |> length()

# Check for events
MyApp.Repo.all(Lyt.Event) |> length()
```

You should see sessions and events being created as you browse your application.

## Optional: JavaScript API

If you need to track events from JavaScript (for SPAs, client-side interactions, or non-LiveView pages), add the API router:

```elixir
# lib/my_app_web/router.ex
forward "/api/analytics", Lyt.API.Router
```

Then track events from JavaScript:

```javascript
fetch('/api/analytics/event', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    name: 'Button Click',
    path: window.location.pathname,
    metadata: {button_id: 'signup'}
  })
});
```

Sessions are derived automatically from request data, so JavaScript can fire events immediately without waiting for session creation. See the README for full API documentation.

## Next Steps

Now that Lyt is installed, you can:

- Track custom events in your LiveView modules using the `@analytics` decorator
- Track client-side events using the JavaScript API
- Configure tracking options like excluded paths and session length
- Query your analytics data using Ecto to build dashboards

See the `Lyt` module documentation for detailed usage examples.

## Troubleshooting

### Events not being recorded

1. **Check the supervision tree** - Ensure `Lyt.Telemetry` is in your application's children list
2. **Check the plug order** - `Lyt.Plug` must come after `:fetch_session`
3. **Check the repo config** - Verify `config :lyt, :repo, MyApp.Repo` is set correctly

### Migration errors

If you get migration errors, check that:

1. Your database adapter is supported (PostgreSQL, MySQL, SQLite3, or DuckDB)
2. The repo is properly configured before running migrations

### LiveView events not tracked

LiveView tracking requires:

1. `Lyt.Telemetry` in your supervision tree (attaches telemetry handlers)
2. The session cookie to be passed to LiveView via the Plug

## Test Configuration

For testing, enable synchronous mode to avoid timing issues with the async event queue:

```elixir
# config/test.exs
config :lyt, :sync_mode, true
```

This ensures events are inserted immediately rather than being batched, making tests deterministic.
