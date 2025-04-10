defmodule PhxAnalytics.Session do
  use Ecto.Schema
  import Ecto.Changeset

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
      put_change(changeset, :id, generate_session_id())
    else
      changeset
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
