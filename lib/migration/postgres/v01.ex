defmodule Lyt.Migration.Postgres.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(opts) do
    prefix = opts[:prefix]

    create table(:lyt_meta, primary_key: false, prefix: prefix) do
      add(:key, :string, primary_key: true)
      add(:value, :string, null: false)
    end

    create table(:lyt_sessions, primary_key: false, prefix: prefix) do
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

    create table(:lyt_events, prefix: prefix) do
      add(:name, :string)
      add(:hostname, :string)
      add(:path, :text)
      add(:query, :text)
      add(:metadata, :map)

      add(:session_id, references(:lyt_sessions, type: :string, on_delete: :delete_all), size: 64)

      timestamps(type: :utc_datetime)
    end

    create(index(:lyt_events, [:session_id], prefix: prefix))
    create(index(:lyt_events, [:name], prefix: prefix))
    create(index(:lyt_events, [:inserted_at], prefix: prefix))
    create(index(:lyt_sessions, [:inserted_at], prefix: prefix))
  end

  def down(opts) do
    prefix = opts[:prefix]

    drop(table(:lyt_events, prefix: prefix))
    drop(table(:lyt_sessions, prefix: prefix))
    drop(table(:lyt_meta, prefix: prefix))
  end
end
