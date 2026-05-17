defmodule Watchman.MixProject do
  use Mix.Project

  def project do
    [
      app: :watchman,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Watchman.Application, []}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate"]
    ]
  end

  defp deps do
    [
      {:ecto_sqlite3, "~> 0.17"},
      {:ecto_sql, "~> 3.12"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"}
    ]
  end
end
