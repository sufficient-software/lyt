defmodule PhxAnalytics.Test.PostgresRepo do
  use Ecto.Repo,
    otp_app: :phx_analytics,
    adapter: Ecto.Adapters.Postgres
end
