defmodule PhxAnalytics.Migration.DuckDB.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(_opts) do
    create table(:phx_analytics_meta, primary_key: [name: :key, type: :string]) do
      add(:value, :string, null: false)
    end

    create table(:phx_analytics_sessions, primary_key: false) do
      add(:id, :string, size: 64, primary_key: true)
      add(:user_id, :string)
      add(:hostname, :string)
      add(:started_at, :naive_datetime)
      add(:ended_at, :naive_datetime)
      add(:entry, :text)
      add(:exit, :text)
      add(:referrer, :text)
      add(:screen_width, :integer)
      add(:screen_height, :integer)
      add(:browser, :text)
      add(:browser_version, :string)
      add(:operating_system, :text)
      add(:operating_system_version, :text)
      add(:utm_medium, :string)
      add(:utm_source, :string)
      add(:utm_campaign, :string)
      add(:utm_content, :string)
      add(:utm_term, :string)
      add(:metadata, :map)

      timestamps(type: :utc_datetime)
    end

    create table(:phx_analytics_events) do
      add(:name, :string)
      add(:hostname, :string)
      add(:path, :text)
      add(:query, :text)
      add(:metadata, :map)

      add(:session_id, references(:phx_analytics_sessions, type: :string, on_delete: :nothing),
        size: 64
      )

      timestamps(type: :utc_datetime)
    end

    create(index(:phx_analytics_events, [:session_id]))
  end

  def down(_opts) do
    drop(table(:phx_analytics_events))
    drop(table(:phx_analytics_sessions))
    drop(table(:phx_analytics_meta))
  end
end
