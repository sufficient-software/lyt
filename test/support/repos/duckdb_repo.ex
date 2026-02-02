defmodule Lyt.Test.DuckDBRepo do
  use Ecto.Repo,
    otp_app: :lyt,
    adapter: Ecto.Adapters.DuckDB
end
