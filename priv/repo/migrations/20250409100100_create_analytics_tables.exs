defmodule Lyt.Repo.Migrations.CreateAnalyticsTables do
  use Ecto.Migration

  defdelegate up(), to: Lyt.Migration
  defdelegate down(), to: Lyt.Migration
end
