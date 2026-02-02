defmodule Lyt.Event do
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
    * `:timestamp` - When the event occurred (defaults to now, can be provided by client)
    * `:session_id` - Foreign key reference to the parent session

  ## Built-in Event Types

  Lyt automatically creates these events:

    * `"Page View"` - Created by `Lyt.Plug` for non-LiveView requests
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

  schema "lyt_events" do
    field(:name, :string)
    field(:path, :string)
    field(:metadata, :map)
    field(:hostname, :string)
    field(:query, :string)
    field(:timestamp, :utc_datetime)
    belongs_to(:session, Lyt.Session, type: :string)
  end

  @doc """
  Creates a changeset for an event.

  The `:name` and `:session_id` fields are required. All other fields are optional.

  The `:timestamp` field defaults to the current UTC time if not provided, allowing
  clients to preserve original event timing for batched or queued inserts.
  """
  def changeset(event, attrs) do
    attrs = default_timestamp(attrs)

    event
    |> cast(attrs, [:session_id, :name, :hostname, :path, :query, :metadata, :timestamp])
    |> validate_required([:name, :session_id, :timestamp])
    |> foreign_key_constraint(:session_id)
  end

  defp default_timestamp(attrs) do
    cond do
      Map.get(attrs, :timestamp) -> attrs
      Map.get(attrs, "timestamp") -> attrs
      true -> Map.put(attrs, :timestamp, DateTime.utc_now())
    end
  end
end
