# Lyt

[![Hex.pm](https://img.shields.io/hexpm/v/lyt.svg)](https://hex.pm/packages/lyt)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/lyt)

Highly customizable analytics for Phoenix LiveView applications.

Lyt provides automatic tracking of page views and custom events in Phoenix
LiveView applications. It captures session data including browser information, UTM
parameters, and custom metadata.

## Features

- **Automatic LiveView Tracking** - Tracks mounts and navigation without manual instrumentation
- **Custom Event Tracking** - Use the `@analytics` decorator to track specific events
- **Session Management** - Automatic session creation with device/browser detection
- **UTM Parameter Capture** - Automatically captures marketing attribution data
- **Async Event Queuing** - High-performance batch inserts via GenServer
- **Multi-Database Support** - Works with PostgreSQL, MySQL, SQLite3, and DuckDB
- **Flexible Configuration** - Include/exclude events, custom callbacks, and more

## Installation

Add `lyt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lyt, "~> 0.1.0"},
    # Include your database adapter (one of the following):
    {:postgrex, ">= 0.0.0"},     # for PostgreSQL
    {:myxql, ">= 0.0.0"},        # for MySQL
    {:ecto_sqlite3, ">= 0.0.0"}, # for SQLite3
    {:ecto_duckdb, ">= 0.0.0"}   # for DuckDB
  ]
end
```

## Setup

### 1. Configure the Repository

Tell Lyt which Ecto repository to use:

```elixir
# config/config.exs
config :lyt, :repo, MyApp.Repo
```

### 2. Run Migrations

Create a migration to set up the analytics tables:

```bash
mix ecto.gen.migration create_analytics_tables
```

Then edit the generated migration file:

```elixir
defmodule MyApp.Repo.Migrations.CreateAnalyticsTables do
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

### 3. Add to Supervision Tree

Add the Lyt supervisor to your application:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    Lyt.Telemetry,  # Add this line
    MyAppWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 4. Add the Plug

Add `Lyt.Plug` to your router pipeline:

```elixir
# lib/my_app_web/router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug Lyt.Plug  # Add this line
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end
```

That's it! Lyt will now automatically track:

- Page views for regular (non-LiveView) requests
- LiveView mounts and navigation

## Tracking Custom Events

### Using the `@analytics` Decorator

To track specific LiveView events, use the `@analytics` decorator:

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  use Lyt

  @analytics true
  def handle_event("submit_form", params, socket) do
    # Your event handling code
    {:noreply, socket}
  end
end
```

### Custom Event Names and Metadata

You can customize the event name and add metadata:

```elixir
@analytics name: "Contact Form Submitted", metadata: %{"form_type" => "contact"}
def handle_event("submit", params, socket) do
  # ...
  {:noreply, socket}
end
```

Or use a function to generate metadata dynamically:

```elixir
@analytics name: "Item Purchased", metadata: &extract_purchase_metadata/1
def handle_event("purchase", params, socket) do
  # ...
  {:noreply, socket}
end

defp extract_purchase_metadata(params) do
  %{"item_id" => params["id"], "quantity" => params["qty"]}
end
```

### Module-Level Tracking Options

Configure tracking at the module level:

```elixir
# Track all events automatically
use Lyt, track_all: true

# Track all events except specific ones
use Lyt, track_all: true, exclude: ["ping", "heartbeat"]

# Only track specific events (without needing @analytics)
use Lyt, include: ["submit_form", "click_button"]
```

### Before-Save Callbacks

Filter or modify events before they're saved:

```elixir
use Lyt, before_save: &__MODULE__.filter_analytics/3

def filter_analytics(changeset, opts, socket) do
  # Skip tracking for admin users
  if socket.assigns.current_user.admin? do
    :halt
  else
    {:ok, changeset}
  end
end
```

You can also set `before_save` at the decorator level:

```elixir
@analytics before_save: &__MODULE__.add_user_info/3
def handle_event("action", params, socket) do
  # ...
end

defp add_user_info(changeset, _opts, socket) do
  metadata = Ecto.Changeset.get_field(changeset, :metadata) || %{}
  updated = Map.put(metadata, "user_id", socket.assigns.current_user.id)
  {:ok, Ecto.Changeset.put_change(changeset, :metadata, updated)}
end
```

## JavaScript API

Lyt provides a REST API for tracking events from JavaScript. This is useful for:

- Single-page applications that don't use LiveView
- Tracking client-side interactions (scroll depth, time on page, etc.)
- Mobile apps or external services

### Setup

Add the API router to your Phoenix router:

```elixir
# lib/my_app_web/router.ex
forward "/api/analytics", Lyt.API.Router
```

That's it! No additional configuration required.

### How It Works

Sessions are derived automatically from request data (user agent, IP address, hostname), so JavaScript can fire events immediately without waiting for a session to be created. The same browser/IP combination will always map to the same session.

### Tracking Events

#### Single Event

```javascript
fetch('/api/analytics/event', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    name: 'Button Click',
    path: '/dashboard',
    metadata: {button_id: 'signup', variant: 'blue'}
  })
});
```

#### Batch Events

Send multiple events in a single request (up to 100 by default):

```javascript
fetch('/api/analytics/events', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    events: [
      {name: 'Page View', path: '/home'},
      {name: 'Scroll Depth', metadata: {depth: 50}},
      {name: 'Time on Page', metadata: {seconds: 30}}
    ]
  })
});
```

### Request Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Event name (e.g., "Button Click", "Page View") |
| `path` | No | Page path (defaults to "/") |
| `hostname` | No | Hostname (defaults to request host) |
| `metadata` | No | Custom data object (max 10KB) |
| `screen_width` | No | Screen width in pixels (captured on session) |
| `screen_height` | No | Screen height in pixels (captured on session) |
| `utm_source` | No | UTM source parameter |
| `utm_medium` | No | UTM medium parameter |
| `utm_campaign` | No | UTM campaign parameter |
| `utm_term` | No | UTM term parameter |
| `utm_content` | No | UTM content parameter |

### Response Format

Success:
```json
{"ok": true}
```

Success (batch):
```json
{"ok": true, "queued": 3}
```

Validation error:
```json
{
  "ok": false,
  "error": "validation_error",
  "details": {"name": ["is required"]}
}
```

### Example: Track Page Views and Interactions

```javascript
// Track initial page view with screen dimensions
fetch('/api/analytics/event', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    name: 'Page View',
    path: window.location.pathname,
    screen_width: window.innerWidth,
    screen_height: window.innerHeight
  })
});

// Track button clicks
document.querySelectorAll('[data-track]').forEach(el => {
  el.addEventListener('click', () => {
    fetch('/api/analytics/event', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        name: el.dataset.track,
        path: window.location.pathname,
        metadata: {element_id: el.id}
      })
    });
  });
});
```

### API Configuration

```elixir
# config/config.exs
config :lyt, Lyt.API.Router,
  max_batch_size: 100,        # Maximum events per batch request
  max_metadata_size: 10_240,  # Maximum metadata size in bytes (10KB)
  max_name_length: 255,       # Maximum event name length
  before_save: &MyModule.filter/2  # Optional callback to filter events
```

### CORS

The API router does not handle CORS. If you need cross-origin requests, configure CORS in your Phoenix pipeline or use a library like `cors_plug`:

```elixir
# lib/my_app_web/router.ex
pipeline :api do
  plug :accepts, ["json"]
  plug CORSPlug, origin: ["https://myapp.com"]
end

scope "/api" do
  pipe_through :api
  forward "/analytics", Lyt.API.Router
end
```

## Configuration Options

All configuration is optional. Here are the available options:

```elixir
# config/config.exs

# Required: Your Ecto repository
config :lyt, :repo, MyApp.Repo

# Session cookie name (default: "lyt_session")
config :lyt, :session_cookie_name, "my_analytics_session"

# Session length in seconds (default: 300)
config :lyt, :session_length, 600

# Paths to exclude from tracking (default: [])
config :lyt, :excluded_paths, ["/health", "/metrics", "/api"]

# Enable synchronous mode for testing (default: false)
config :lyt, :sync_mode, false

# Event queue configuration
config :lyt, Lyt.EventQueue,
  flush_interval: 100,  # ms between batch inserts
  batch_size: 50        # max items per batch
```

### Test Configuration

For testing, enable synchronous mode to avoid async timing issues:

```elixir
# config/test.exs
config :lyt, :sync_mode, true
```

## Database Schema

Lyt creates the following tables:

### `lyt_sessions`

| Column                     | Type     | Description                 |
| -------------------------- | -------- | --------------------------- |
| `id`                       | string   | Primary key (64-char hex)   |
| `user_id`                  | string   | Optional user identifier    |
| `hostname`                 | string   | Request hostname            |
| `entry`                    | string   | First page visited          |
| `exit`                     | string   | Last page visited           |
| `referrer`                 | string   | HTTP referrer               |
| `started_at`               | datetime | Session start time          |
| `ended_at`                 | datetime | Session end time            |
| `screen_width`             | integer  | Screen width (if provided)  |
| `screen_height`            | integer  | Screen height (if provided) |
| `browser`                  | string   | Browser name                |
| `browser_version`          | string   | Browser version             |
| `operating_system`         | string   | OS name                     |
| `operating_system_version` | string   | OS version                  |
| `utm_source`               | string   | UTM source                  |
| `utm_medium`               | string   | UTM medium                  |
| `utm_campaign`             | string   | UTM campaign                |
| `utm_term`                 | string   | UTM term                    |
| `utm_content`              | string   | UTM content                 |
| `metadata`                 | map      | Custom metadata             |

### `lyt_events`

| Column       | Type    | Description                  |
| ------------ | ------- | ---------------------------- |
| `id`         | integer | Primary key (auto-increment) |
| `session_id` | string  | Foreign key to sessions      |
| `name`       | string  | Event name                   |
| `path`       | string  | Page path                    |
| `query`      | string  | Query string                 |
| `hostname`   | string  | Request hostname             |
| `metadata`   | map     | Custom event metadata        |

## Querying Analytics Data

Query your analytics data using Ecto:

```elixir
import Ecto.Query

# Get all sessions from the last 24 hours
from(s in Lyt.Session,
  where: s.inserted_at > ago(24, "hour"),
  order_by: [desc: s.inserted_at]
)
|> MyApp.Repo.all()

# Count events by name
from(e in Lyt.Event,
  group_by: e.name,
  select: {e.name, count(e.id)}
)
|> MyApp.Repo.all()

# Get page views with session info
from(e in Lyt.Event,
  join: s in Lyt.Session, on: e.session_id == s.id,
  where: e.name == "Page View",
  select: %{path: e.path, browser: s.browser, utm_source: s.utm_source}
)
|> MyApp.Repo.all()
```

## How It Works

### Session Tracking

1. When a request comes in, `Lyt.Plug` checks for an existing session cookie
2. If no session exists, a new one is created with:
   - A cryptographically secure 64-character ID
   - Parsed user-agent information (browser, OS)
   - UTM parameters from the query string
3. The session ID is stored in a cookie and passed to LiveView via the session

### Event Tracking

1. For regular requests, `Lyt.Plug` records a "Page View" event
2. For LiveView:
   - Mount events create a "Live View" event
   - Navigation (handle_params) creates events when the path changes
   - Custom events are tracked via the `@analytics` decorator
3. Events are queued asynchronously and batch-inserted for performance

### Performance

- Events are queued in a GenServer and batch-inserted periodically
- Default: 50 items per batch, every 100ms
- Sessions are always inserted before their events (foreign key safety)
- Use `sync_mode: true` in tests for deterministic behavior

## License

MIT License. See [LICENSE](LICENSE) for details.
