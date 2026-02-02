defmodule Lyt.Migration.Postgres.V02 do
  @moduledoc false

  use Ecto.Migration

  def up(opts) do
    prefix = opts[:prefix]

    alter table(:lyt_events, prefix: prefix) do
      add(:timestamp, :utc_datetime)
    end

    # Populate existing rows with inserted_at value
    execute("UPDATE #{prefix}.lyt_events SET timestamp = inserted_at")

    alter table(:lyt_events, prefix: prefix) do
      modify(:timestamp, :utc_datetime, null: false)
    end

    # Replace the inserted_at index with timestamp index
    drop(index(:lyt_events, [:inserted_at], prefix: prefix))
    create(index(:lyt_events, [:timestamp], prefix: prefix))

    alter table(:lyt_events, prefix: prefix) do
      remove(:inserted_at)
      remove(:updated_at)
    end
  end

  def down(opts) do
    prefix = opts[:prefix]

    alter table(:lyt_events, prefix: prefix) do
      add(:inserted_at, :utc_datetime)
      add(:updated_at, :utc_datetime)
    end

    execute("UPDATE #{prefix}.lyt_events SET inserted_at = timestamp, updated_at = timestamp")

    drop(index(:lyt_events, [:timestamp], prefix: prefix))
    create(index(:lyt_events, [:inserted_at], prefix: prefix))

    alter table(:lyt_events, prefix: prefix) do
      remove(:timestamp)
    end
  end
end
