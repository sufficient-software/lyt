defmodule PhxAnalytics.Test.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      import PhxAnalytics.Test.Case
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo(), shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  defp repo do
    Application.get_env(:phx_analytics, :repo)
  end

  def with_binary_module(binary, fun) do
    mod = define_module_by_binary(binary)

    try do
      fun.(mod)
    after
      :code.purge(mod)
      :code.delete(mod)
    end
  end

  # Helper function to define a module that can be used for testing
  def define_module_by_binary(binary) do
    Code.eval_string(binary)
    |> elem(0)
    |> elem(1)
  end
end
