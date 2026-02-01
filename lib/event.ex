defmodule PhxAnalytics.Event do
  @moduledoc """
  Ecto schema representing an analytics event.

  Events track user interactions within a session. This includes page views,
  LiveView mounts, navigation events, and custom user-defined events.

  ## Fields

    * `:id` - Auto-generated integer primary key
    * `:name` - Event name (e.g., "Page View", "Live View", or custom names)
    * `:path` - The page path where the event occurred
    * `:query` - Query string parameters
    * `:hostname` - The hostname of the request
    * `:metadata` - Custom metadata map for storing additional event data
    * `:session_id` - Foreign key reference to the parent session

  ## Built-in Event Types

  PhxAnalytics automatically creates these events:

    * `"Page View"` - Created by `PhxAnalytics.Plug` for non-LiveView requests
    * `"Live View"` - Created on LiveView mount and navigation

  ## Custom Events

  Track custom events using the `@analytics` decorator:

      @analytics name: "Form Submitted", metadata: %{"form_type" => "contact"}
      def handle_event("submit", params, socket) do
        # ...
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "phx_analytics_events" do
    field(:name, :string)
    field(:path, :string)
    field(:metadata, :map)
    field(:hostname, :string)
    field(:query, :string)
    belongs_to(:session, PhxAnalytics.Session, type: :string)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an event.

  The `:name` field is required. All other fields are optional.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:session_id, :name, :hostname, :path, :query, :metadata])
    |> validate_required([:name])
  end
end
