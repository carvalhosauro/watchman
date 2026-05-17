defmodule Watchman.Cache do
  @moduledoc "File-based cache for shell completions."

  @cache_dir Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "cache"])

  def update_tickers do
    import Ecto.Query
    alias Watchman.{Models.Asset, Repo}

    tickers =
      Repo.all(from a in Asset, where: a.active == true, select: a.ticker, order_by: a.ticker)

    write("tickers", Enum.join(tickers, "\n"))
  end

  def update_retro_ids do
    import Ecto.Query
    alias Watchman.{Models.Retrospective, Repo}

    ids = Repo.all(from r in Retrospective, select: r.id, order_by: [desc: r.id])
    write("retro_ids", Enum.map_join(ids, "\n", &to_string/1))
  end

  defp write(filename, content) do
    dir = Path.expand(@cache_dir)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, filename), content <> "\n")
  rescue
    _ -> :ok
  end
end
