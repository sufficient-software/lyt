defmodule PhxAnalytics.Event do
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

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:session_id, :name, :hostname, :path, :query, :metadata])
    |> validate_required([:name])
  end
end
