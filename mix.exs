defmodule PhxAnalytics.MixProject do
  use Mix.Project

  def project do
    [
      app: :phx_analytics,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.3.0"},
      {:ua_inspector, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
      {:plug, "~> 1.17"},
      {:ecto_sqlite3, ">= 0.0.0", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      {:myxql, ">= 0.0.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # Test dependencies for Phoenix/LiveView integration tests
      {:phoenix, "~> 1.7", only: :test},
      {:phoenix_live_view, "~> 1.0", only: :test},
      {:floki, "~> 0.36", only: :test},
      {:lazy_html, "~> 0.1", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "Phoenix Analytics",
      extras: ["README.md"]
    ]
  end
end
