defmodule Watchman.MixProject do
  use Mix.Project

  def project do
    [
      app: :watchman,
      version: "0.4.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 60],
        ignore_modules: [
          # HTTP wrappers — tested via integration, not unit
          Watchman.AI.Claude,
          Watchman.AI.Gemini,
          Watchman.AI.Deepseek,
          Watchman.Market.Brapi,
          Watchman.Market.Yfinance,
          # Alert providers — HTTP wrappers
          Watchman.Alerts.Telegram,
          Watchman.Alerts.Discord,
          # Interactive I/O — requires stdin
          Watchman.Setup,
          # System commands — requires systemd/cron
          Watchman.Scheduler
        ]
      ],
      preferred_cli_env: [credo: :test, dialyzer: :test]
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
      setup: ["deps.get", "ecto.create", "ecto.migrate", "cmd ./bin/setup-hooks"],
      lint: ["credo --strict"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ],
      ci: ["deps.get", "quality"]
    ]
  end

  def cli do
    [preferred_envs: [quality: :test, ci: :test]]
  end

  defp deps do
    [
      {:ecto_sqlite3, "~> 0.17"},
      {:ecto_sql, "~> 3.12"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"},
      {:plug, "~> 1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
