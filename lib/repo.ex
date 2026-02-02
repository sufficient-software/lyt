defmodule Lyt.Repo do
  @moduledoc """
  Repository abstraction layer for Lyt.

  This module delegates Ecto operations to the application's configured repository.
  It also provides adapter detection for database-specific operations.

  ## Configuration

  Configure the repository in your application config:

      config :lyt, :repo, MyApp.Repo

  ## Supported Adapters

    * `Ecto.Adapters.Postgres` - PostgreSQL
    * `Ecto.Adapters.MyXQL` - MySQL
    * `Ecto.Adapters.SQLite3` - SQLite3
    * `Ecto.Adapters.DuckDB` - DuckDB

  ## Adapter Detection

  Use `with_adapter/1` to run adapter-specific code:

      Lyt.Repo.with_adapter(fn
        :postgres -> # PostgreSQL-specific code
        :mysql -> # MySQL-specific code
        :sqlite3 -> # SQLite3-specific code
        :duckdb -> # DuckDB-specific code
      end)
  """
  def insert!(struct_or_changeset, opts \\ []) do
    delegate(:insert!, [struct_or_changeset], opts)
  end

  def insert(struct_or_changeset, opts \\ []) do
    delegate(:insert, [struct_or_changeset], opts)
  end

  def all(queryable, opts \\ []) do
    delegate(:all, [queryable], opts)
  end

  def one(queryable, opts \\ []) do
    delegate(:one, [queryable], opts)
  end

  def get(queryable, id, opts \\ []) do
    delegate(:get, [queryable, id], opts)
  end

  defp delegate(action, arguments, opts) do
    repo = Keyword.get(opts, :repo, repo())
    # TODO: handle deafult arguments if needed
    apply(repo, action, arguments ++ [opts])
  end

  @doc """
  Execute a function with the detected database adapter.

  Calls the provided function with an atom representing the adapter:
  `:postgres`, `:mysql`, `:sqlite3`, or `:duckdb`.

  ## Examples

      Lyt.Repo.with_adapter(fn
        :postgres -> "PostgreSQL"
        :mysql -> "MySQL"
        :sqlite3 -> "SQLite3"
      end)

  """
  def with_adapter(fun), do: with_adapter(repo(), fun)

  def with_adapter(repo, fun) do
    adapter =
      case repo.__adapter__() do
        Ecto.Adapters.Postgres -> :postgres
        Ecto.Adapters.MyXQL -> :mysql
        Ecto.Adapters.SQLite3 -> :sqlite3
        Ecto.Adapters.DuckDB -> :duckdb
      end

    fun.(adapter)
  end

  defp repo() do
    Application.fetch_env!(:lyt, :repo)
  end
end
