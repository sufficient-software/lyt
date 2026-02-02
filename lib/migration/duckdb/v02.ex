defmodule Lyt.Migration.DuckDB.V02 do
  @moduledoc false

  use Ecto.Migration

  def up(_opts) do
    alter table(:lyt_events) do
      add(:timestamp, :utc_datetime)
    end

    # Populate existing rows with inserted_at value
    execute("UPDATE lyt_events SET timestamp = inserted_at")

    # Replace the inserted_at index with timestamp index
    drop(index(:lyt_events, [:inserted_at]))
    create(index(:lyt_events, [:timestamp]))

    alter table(:lyt_events) do
      remove(:inserted_at)
      remove(:updated_at)
    end
  end

  def down(_opts) do
    alter table(:lyt_events) do
      add(:inserted_at, :utc_datetime)
      add(:updated_at, :utc_datetime)
    end

    execute("UPDATE lyt_events SET inserted_at = timestamp, updated_at = timestamp")

    drop(index(:lyt_events, [:timestamp]))
    create(index(:lyt_events, [:inserted_at]))

    alter table(:lyt_events) do
      remove(:timestamp)
    end
  end
end
