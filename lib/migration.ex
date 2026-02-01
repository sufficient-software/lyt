defmodule PhxAnalytics.Migration do
  @moduledoc """
  Database migration management for PhxAnalytics.

  This module handles creating and managing the analytics database tables.
  It automatically detects your database adapter and runs the appropriate
  migrations.

  ## Usage

  Create a migration file in your application:

      defmodule MyApp.Repo.Migrations.CreateAnalyticsTables do
        use Ecto.Migration

        def up do
          PhxAnalytics.Migration.up()
        end

        def down do
          PhxAnalytics.Migration.down()
        end
      end

  Then run the migration:

      mix ecto.migrate

  ## Tables Created

  The migration creates three tables:

    * `phx_analytics_meta` - Stores migration version information
    * `phx_analytics_sessions` - Stores session records
    * `phx_analytics_events` - Stores event records (with FK to sessions)

  ## Multi-Database Support

  Migrations are automatically adapted for your database:

    * PostgreSQL (`Ecto.Adapters.Postgres`)
    * MySQL (`Ecto.Adapters.MyXQL`)
    * SQLite3 (`Ecto.Adapters.SQLite3`)
    * DuckDB (`Ecto.Adapters.DuckDB`)

  ## Versioning

  PhxAnalytics uses internal versioning to track applied migrations.
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

      PhxAnalytics.Migration.up()
      PhxAnalytics.Migration.up(prefix: "analytics")

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

      PhxAnalytics.Migration.down()

  """
  def down(opts \\ []) do
    migrator().down(opts)
  end

  @doc """
  Get the currently applied migration version.

  Returns `0` if no migrations have been run.

  ## Example

      PhxAnalytics.Migration.migrated_version()
      #=> 1

  """
  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    PhxAnalytics.Repo.with_adapter(fn
      :postgres -> PhxAnalytics.Migration.Postgres
      :mysql -> PhxAnalytics.Migration.MySQL
      :sqlite3 -> PhxAnalytics.Migration.SQLite3
      :duckdb -> PhxAnalytics.Migration.DuckDB
      adapter -> raise "Unknown adapter #{adapter}"
    end)
  end
end
