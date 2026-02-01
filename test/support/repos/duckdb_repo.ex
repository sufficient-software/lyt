defmodule PhxAnalytics.Test.DuckDBRepo do
  use Ecto.Repo,
    otp_app: :phx_analytics,
    adapter: Ecto.Adapters.DuckDB
end
