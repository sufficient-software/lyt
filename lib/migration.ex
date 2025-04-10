defmodule PhxAnalytics.Migration do
  @callback up(Keyword.t()) :: :ok
  @callback down(Keyword.t()) :: :ok
  @callback current_version(Keyword.t()) :: non_neg_integer()

  def up(opts \\ []) do
    migrator().up(opts)
  end

  def down(opts \\ []) do
    migrator().down(opts)
  end

  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    PhxAnalytics.Repo.with_adapter(fn
      :postgres -> PhxAnalytics.Migration.Postgres
      :mysql -> PhxAnalytics.Migration.MySQL
      :sqlite3 -> PhxAnalytics.Migration.SQLite3
      adapter -> raise "Unknown adapter #{adapter}"
    end)
  end
end
