defmodule Lyt.Test.Sqlite3Repo do
  use Ecto.Repo,
    otp_app: :lyt,
    adapter: Ecto.Adapters.SQLite3
end
