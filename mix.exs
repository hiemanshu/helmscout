defmodule Helmscout.MixProject do
  use Mix.Project

  def project do
    [
      app: :helmscout,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [
      preferred_envs: [
        "helmscout.update": :dev,
        "helmscout.discover": :dev,
        "helmscout.fetch": :dev,
        "helmscout.index": :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Helmscout.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.2"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.7"},
      {:finch, "~> 0.24"},
      {:yaml_elixir, "~> 2.12"},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.25"},
      {:nimble_options, "~> 1.1"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
