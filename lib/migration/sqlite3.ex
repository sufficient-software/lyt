defmodule PhxAnalytics.Migration.SQLite3 do
  @moduledoc false

  @behaviour PhxAnalytics.Migration

  use Ecto.Migration
  alias PhxAnalytics.Migration.Migrator

  @initial_version 1
  @current_version 1

  @impl PhxAnalytics.Migration
  def up(opts) do
    opts = with_defaults(opts, @current_version)
    Migrator.migrate_up(__MODULE__, opts, @initial_version)
  end

  @impl PhxAnalytics.Migration
  def down(opts) do
    opts = with_defaults(opts, @initial_version)
    Migrator.migrate_down(__MODULE__, opts, @initial_version)
  end

  @impl PhxAnalytics.Migration
  def current_version(opts) do
    opts = with_defaults(opts, @initial_version)
    Migrator.current_version(opts)
  end

  defp with_defaults(opts, version) do
    Enum.into(opts, %{version: version})
  end
end
