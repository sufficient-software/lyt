defmodule PhxAnalytics.Session do
  @moduledoc """
  Ecto schema representing an analytics session.

  A session groups related page views and events from a single user visit.
  Sessions capture device information, UTM parameters, and custom metadata.

  ## Fields

    * `:id` - Unique session identifier (64-character hex string)
    * `:user_id` - Optional user identifier for logged-in users
    * `:hostname` - The hostname of the request
    * `:entry` - The first page path visited in this session
    * `:exit` - The last page path visited (updated on session end)
    * `:referrer` - The HTTP referrer header value
    * `:started_at` - When the session began
    * `:ended_at` - When the session ended
    * `:screen_width` - Screen width in pixels (if provided)
    * `:screen_height` - Screen height in pixels (if provided)
    * `:browser` - Browser name (e.g., "Chrome", "Firefox")
    * `:browser_version` - Browser version string
    * `:operating_system` - OS name (e.g., "Mac", "Windows")
    * `:operating_system_version` - OS version string
    * `:utm_source` - UTM source parameter
    * `:utm_medium` - UTM medium parameter
    * `:utm_campaign` - UTM campaign parameter
    * `:utm_term` - UTM term parameter
    * `:utm_content` - UTM content parameter
    * `:metadata` - Custom metadata map

  ## Upsert Behavior

  When a session with an existing ID is inserted, only the `:metadata` field
  is updated (see `upsert_keys/0`). This allows sessions to be updated without
  overwriting the original entry data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @doc """
  Returns the list of fields that are updated on conflict during upsert operations.

  Currently only `:metadata` is updated when a session already exists.
  """
  def upsert_keys(), do: [:metadata]

  @primary_key {:id, :string, autogenerate: false}
  schema "phx_analytics_sessions" do
    field(:exit, :string)
    field(:started_at, :naive_datetime)
    field(:metadata, :map)
    field(:hostname, :string)
    field(:entry, :string)
    field(:user_id, :string)
    field(:ended_at, :naive_datetime)
    field(:referrer, :string)
    field(:screen_width, :integer)
    field(:screen_height, :integer)
    field(:browser, :string)
    field(:browser_version, :string)
    field(:operating_system, :string)
    field(:operating_system_version, :string)
    field(:utm_medium, :string)
    field(:utm_source, :string)
    field(:utm_campaign, :string)
    field(:utm_content, :string)
    field(:utm_term, :string)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a session.

  Automatically generates a session ID if one is not provided.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :id,
      :user_id,
      :hostname,
      :started_at,
      :ended_at,
      :entry,
      :exit,
      :referrer,
      :screen_width,
      :screen_height,
      :browser,
      :browser_version,
      :operating_system,
      :operating_system_version,
      :utm_medium,
      :utm_source,
      :utm_campaign,
      :utm_content,
      :utm_term,
      :metadata
    ])
    |> maybe_set_session_id()
    |> validate_required([:id])
  end

  defp maybe_set_session_id(changeset) do
    current_id = get_field(changeset, :id)

    if is_nil(current_id) || current_id == "" do
      put_change(changeset, :id, PhxAnalytics.generate_session_id())
    else
      changeset
    end
  end
end
