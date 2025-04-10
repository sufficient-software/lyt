defmodule PhxAnalytics.Test.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      import PhxAnalytics.Test.Case
    end
  end

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(repo())
  end

  defp repo do
    Application.get_env(:phx_analytics, :repo)
  end
end
