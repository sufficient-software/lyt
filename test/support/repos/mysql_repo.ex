defmodule Lyt.Test.MySQLRepo do
  use Ecto.Repo,
    otp_app: :lyt,
    adapter: Ecto.Adapters.MyXQL
end
