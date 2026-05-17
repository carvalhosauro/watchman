defmodule Watchman.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Watchman.Config.load()
    setup_file_logger()

    children = [
      Watchman.Repo
    ]

    opts = [strategy: :one_for_one, name: Watchman.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    ensure_db_ready()

    {:ok, pid}
  end

  defp ensure_db_ready do
    db_path = Watchman.Repo.config()[:database]
    db_path |> Path.dirname() |> File.mkdir_p!()

    Ecto.Migrator.run(
      Watchman.Repo,
      migrations_path(),
      :up,
      all: true,
      log: false
    )
  end

  defp setup_file_logger do
    log_dir = log_path() |> Path.dirname()
    File.mkdir_p!(log_dir)

    :logger.add_handler(:watchman_file, :logger_std_h, %{
      config: %{
        file: log_path() |> String.to_charlist(),
        max_no_bytes: 10_000_000,
        max_no_files: 7
      },
      formatter:
        {:logger_formatter,
         %{
           template: [:time, ~c" [", :level, ~c"] ", :msg, ~c"\n"]
         }},
      level: :info
    })
  end

  defp log_path do
    Path.join([
      System.get_env("HOME") || "~",
      ".local",
      "share",
      "watchman",
      "logs",
      "watchman.log"
    ])
  end

  defp migrations_path do
    Application.app_dir(:watchman, "priv/repo/migrations")
  end
end
