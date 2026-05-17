defmodule Watchman.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Watchman.Config.load()

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

  defp migrations_path do
    Application.app_dir(:watchman, "priv/repo/migrations")
  end
end
