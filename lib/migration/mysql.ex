defmodule Lyt.Migration.MySQL do
  @moduledoc false

  @behaviour Lyt.Migration

  use Ecto.Migration
  alias Lyt.Migration.Migrator

  @initial_version 1
  @current_version 2

  @impl Lyt.Migration
  def up(opts) do
    opts = with_defaults(opts, @current_version)
    Migrator.migrate_up(__MODULE__, opts, @initial_version)
  end

  @impl Lyt.Migration
  def down(opts) do
    opts = with_defaults(opts, @initial_version)
    Migrator.migrate_down(__MODULE__, opts, @initial_version)
  end

  @impl Lyt.Migration
  def current_version(opts) do
    opts = with_defaults(opts, @initial_version)
    Migrator.current_version(opts)
  end

  defp with_defaults(opts, version) do
    Enum.into(opts, %{version: version})
  end
end
