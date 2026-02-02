defmodule Lyt.Migration.SQLite3.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(_opts) do
    create table(:lyt_meta, primary_key: [name: :key, type: :string]) do
      add(:value, :string, null: false)
    end

    create table(:lyt_sessions, primary_key: false) do
      add(:id, :string, size: 32, primary_key: true)
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

    create table(:lyt_events) do
      add(:name, :string)
      add(:hostname, :string)
      add(:path, :text)
      add(:query, :text)
      add(:metadata, :map)

      add(:session_id, references(:lyt_sessions, type: :string, on_delete: :nothing), size: 32)

      timestamps(type: :utc_datetime)
    end

    create(index(:lyt_events, [:session_id]))
  end

  def down(_opts) do
    drop(table(:lyt_events))
    drop(table(:lyt_sessions))
    drop(table(:lyt_meta))
  end
end
