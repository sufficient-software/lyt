defmodule Lyt.Migration do
  @moduledoc """
  Database migration management for Lyt.

  This module handles creating and managing the analytics database tables.
  It automatically detects your database adapter and runs the appropriate
  migrations.

  ## Usage

  Create a migration file in your application:

      defmodule MyApp.Repo.Migrations.CreateAnalyticsTables do
        use Ecto.Migration

        def up do
          Lyt.Migration.up()
        end

        def down do
          Lyt.Migration.down()
        end
      end

  Then run the migration:

      mix ecto.migrate

  ## Tables Created

  The migration creates three tables:

    * `lyt_meta` - Stores migration version information
    * `lyt_sessions` - Stores session records
    * `lyt_events` - Stores event records (with FK to sessions)

  ## Multi-Database Support

  Migrations are automatically adapted for your database:

    * PostgreSQL (`Ecto.Adapters.Postgres`)
    * MySQL (`Ecto.Adapters.MyXQL`)
    * SQLite3 (`Ecto.Adapters.SQLite3`)
    * DuckDB (`Ecto.Adapters.DuckDB`)

  ## Versioning

  Lyt uses internal versioning to track applied migrations.
  Use `migrated_version/1` to check the current migration version.
  """

  @callback up(Keyword.t()) :: :ok
  @callback down(Keyword.t()) :: :ok
  @callback current_version(Keyword.t()) :: non_neg_integer()

  @doc """
  Run all pending migrations.

  ## Options

    * `:prefix` - Schema prefix for PostgreSQL (optional)
    * `:version` - Target version to migrate to (optional)

  ## Example

      Lyt.Migration.up()
      Lyt.Migration.up(prefix: "analytics")

  """
  def up(opts \\ []) do
    migrator().up(opts)
  end

  @doc """
  Rollback migrations.

  ## Options

    * `:prefix` - Schema prefix for PostgreSQL (optional)
    * `:version` - Target version to rollback to (optional)

  ## Example

      Lyt.Migration.down()

  """
  def down(opts \\ []) do
    migrator().down(opts)
  end

  @doc """
  Get the currently applied migration version.

  Returns `0` if no migrations have been run.

  ## Example

      Lyt.Migration.migrated_version()
      #=> 1

  """
  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    Lyt.Repo.with_adapter(fn
      :postgres -> Lyt.Migration.Postgres
      :mysql -> Lyt.Migration.MySQL
      :sqlite3 -> Lyt.Migration.SQLite3
      :duckdb -> Lyt.Migration.DuckDB
      adapter -> raise "Unknown adapter #{adapter}"
    end)
  end
end
