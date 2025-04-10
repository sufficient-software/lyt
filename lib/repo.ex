defmodule PhxAnalytics.Repo do
  def insert!(struct_or_changeset, opts \\ []) do
    delegate(:insert!, [struct_or_changeset], opts)
  end

  def all(queryable, opts \\ []) do
    delegate(:all, [queryable], opts)
  end

  defp delegate(action, arguments, opts) do
    repo = Keyword.get(opts, :repo, repo())
    # TODO: handle deafult arguments if needed
    apply(repo, action, arguments ++ [opts])
  end

  def with_adapter(fun), do: with_adapter(repo(), fun)

  def with_adapter(repo, fun) do
    adapter =
      case repo.__adapter__() do
        Ecto.Adapters.Postgres -> :postgres
        Ecto.Adapters.MyXQL -> :mysql
        Ecto.Adapters.SQLite3 -> :sqlite3
      end

    fun.(adapter)
  end

  defp repo() do
    Application.fetch_env!(:phx_analytics, :repo)
  end
end
