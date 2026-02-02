defmodule Lyt.Test.PostgresRepo do
  use Ecto.Repo,
    otp_app: :lyt,
    adapter: Ecto.Adapters.Postgres
end
