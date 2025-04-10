defmodule PhxAnalytics.Repo.Migrations.CreateAnalyticsTables do
  use Ecto.Migration

  defdelegate up(), to: PhxAnalytics.Migration
  defdelegate down(), to: PhxAnalytics.Migration
end
