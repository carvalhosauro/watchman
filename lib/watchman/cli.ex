defmodule Watchman.CLI do
  @moduledoc "CLI entry point and command dispatch."

  alias Watchman.Models.{Analysis, Asset, PriceSnapshot}
  alias Watchman.Repo
  import Ecto.Query

  def main(args) do
    Application.ensure_all_started(:watchman)
    dispatch(args)
  end

  defp dispatch(["assets" | tickers]), do: cmd_assets(tickers)
  defp dispatch(["list"]), do: cmd_list()
  defp dispatch(["remove" | tickers]), do: cmd_remove(tickers)
  defp dispatch(["run" | opts]), do: cmd_run(opts)
  defp dispatch(["show" | opts]), do: cmd_show(opts)
  defp dispatch(["retro" | opts]), do: cmd_retro(opts)
  defp dispatch(["setup"]), do: Watchman.Setup.run()
  defp dispatch(["schedule"]), do: Watchman.Scheduler.setup()
  defp dispatch(["schedule", "status"]), do: Watchman.Scheduler.status()
  defp dispatch(["unschedule"]), do: Watchman.Scheduler.teardown()
  defp dispatch(["logs" | opts]), do: cmd_logs(opts)
  defp dispatch(["update"]), do: cmd_update()
  defp dispatch(["completions", shell]), do: cmd_completions(shell)
  # Debug helpers — completions now use file cache, but these remain for manual testing
  defp dispatch(["_complete_tickers"]), do: complete_tickers()
  defp dispatch(["_complete_retro_ids"]), do: complete_retro_ids()
  defp dispatch(_), do: print_usage()

  defp cmd_assets([]) do
    IO.puts("Usage: wm assets TICKER1 TICKER2 ...")
  end

  defp cmd_assets(tickers) do
    for raw <- tickers do
      {ticker, type} = parse_ticker_type(raw)

      case Repo.get_by(Asset, ticker: ticker) do
        nil ->
          {:ok, _} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: ticker, type: type}))
          IO.puts("+ #{ticker} (#{type})")

        %{active: false} = asset ->
          Repo.update!(Asset.changeset(asset, %{active: true, type: type}))
          IO.puts("+ #{ticker} (reactivated, #{type})")

        %{type: nil} = asset ->
          Repo.update!(Asset.changeset(asset, %{type: type}))
          IO.puts("~ #{ticker} (type set: #{type})")

        _existing ->
          IO.puts("~ #{ticker} (already tracked)")
      end
    end

    Watchman.Cache.update_tickers()
  end

  defp parse_ticker_type(raw) do
    raw = String.upcase(raw)

    case String.split(raw, ":") do
      [ticker, type] when type in ["ACAO", "FII"] ->
        {ticker, String.downcase(type)}

      [ticker] ->
        {ticker, detect_type(ticker)}

      _ ->
        {raw, detect_type(raw)}
    end
  end

  @known_etfs ~w(BOVA11 IVVB11 SMAL11 DIVO11 FIND11 HASH11 XFIX11 GOLD11 MATB11 IMAB11 FIXA11)

  defp detect_type(ticker) do
    upper = String.upcase(ticker)

    cond do
      upper in @known_etfs -> "acao"
      String.ends_with?(upper, "11") -> "fii"
      true -> "acao"
    end
  end

  defp cmd_list do
    assets = Repo.all(from a in Asset, where: a.active == true, order_by: a.ticker)
    Watchman.Cache.update_tickers()

    if assets == [] do
      IO.puts("No assets tracked. Use: wm assets TICKER1 TICKER2")
    else
      print_assets(assets)
    end
  end

  defp print_assets(assets) do
    IO.puts("Tracked assets:")

    for asset <- assets do
      type_label = if asset.type, do: " (#{asset.type})", else: ""
      IO.puts("  #{asset.ticker}#{type_label}")
    end
  end

  defp cmd_remove([]) do
    IO.puts("Usage: wm remove TICKER1 TICKER2 ...")
  end

  defp cmd_remove(tickers) do
    for ticker <- tickers do
      ticker = String.upcase(ticker)

      case Repo.get_by(Asset, ticker: ticker) do
        nil ->
          IO.puts("? #{ticker} (not found)")

        asset ->
          Repo.update!(Asset.changeset(asset, %{active: false}))
          IO.puts("- #{ticker}")
      end
    end

    Watchman.Cache.update_tickers()
  end

  defp cmd_run(_opts) do
    IO.puts("Running analysis...")
    Watchman.Pipeline.run()
  end

  defp cmd_show(opts) do
    {parsed, args, _} =
      OptionParser.parse(opts,
        switches: [last: :integer],
        aliases: [l: :last]
      )

    ticker = List.first(args)
    limit = parsed[:last]
    results = Repo.all(build_show_query(ticker, limit))

    if results == [] do
      print_show_empty(ticker)
    else
      for r <- results do
        IO.puts("""
        #{r.ticker}  #{format_datetime(r.analyzed_at)}
          Price: R$ #{r.price}  Var: #{format_var(r.variation_day)}
          Recommendation: #{r.recommendation}
          Cause: #{r.cause || "—"}
          Specific problem: #{r.is_specific_problem}
          Macro: #{r.macro_context || "—"}
          Justification: #{r.justification || "—"}
          Tokens: #{r.tokens_used || 0}  Cost: $#{Float.round((r.cost_usd || 0.0) * 1.0, 4)}
        """)
      end
    end
  end

  defp build_show_query(ticker, limit) do
    base =
      from a in Analysis,
        join: asset in Asset,
        on: a.asset_id == asset.id,
        join: s in PriceSnapshot,
        on: a.snapshot_id == s.id,
        order_by: [desc: a.analyzed_at],
        select: %{
          ticker: asset.ticker,
          price: s.price,
          variation_day: s.variation_day,
          recommendation: a.recommendation,
          cause: a.cause,
          justification: a.justification,
          is_specific_problem: a.is_specific_problem,
          macro_context: a.macro_context,
          tokens_used: a.tokens_used,
          cost_usd: a.cost_usd,
          analyzed_at: a.analyzed_at
        }

    base
    |> filter_show_by(ticker)
    |> maybe_limit(limit)
  end

  defp filter_show_by(query, nil) do
    today = Date.utc_today()
    start_dt = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    from [a, asset, s] in query, where: a.analyzed_at >= ^start_dt
  end

  defp filter_show_by(query, ticker) do
    t = String.upcase(ticker)
    from [a, asset, s] in query, where: asset.ticker == ^t
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(q in query, limit: ^limit)

  defp print_show_empty(nil), do: IO.puts("No analyses found for today. Run: wm run")
  defp print_show_empty(ticker), do: IO.puts("No analyses found for #{String.upcase(ticker)}.")

  defp cmd_logs(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        switches: [follow: :boolean, lines: :integer],
        aliases: [f: :follow, n: :lines]
      )

    log_path =
      Path.join([
        System.get_env("HOME") || "~",
        ".local",
        "share",
        "watchman",
        "logs",
        "watchman.log"
      ])

    if File.exists?(log_path) do
      cond do
        parsed[:follow] ->
          IO.puts("Following #{log_path} (Ctrl+C to stop)\n")
          System.cmd("tail", ["-f", log_path], into: IO.stream())

        parsed[:lines] ->
          n = to_string(parsed[:lines])
          {output, _} = System.cmd("tail", ["-n", n, log_path])
          IO.write(output)

        true ->
          {output, _} = System.cmd("tail", ["-n", "50", log_path])
          IO.write(output)
      end
    else
      IO.puts("No log file found at #{log_path}")
      IO.puts("Logs are created after running: wm run")
    end
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_var(nil), do: "N/A"
  defp format_var(val), do: "#{val}%"

  defp cmd_retro(["list" | _]), do: retro_list()
  defp cmd_retro(["show", id | _]), do: retro_show(id)

  defp cmd_retro(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        switches: [weekly: :boolean, monthly: :boolean],
        aliases: [w: :weekly, m: :monthly]
      )

    period =
      cond do
        parsed[:weekly] ->
          :weekly

        parsed[:monthly] ->
          :monthly

        true ->
          IO.puts("""
          Usage:
            wm retro -w              Generate weekly retrospective
            wm retro -m              Generate monthly retrospective
            wm retro list            List all retrospectives
            wm retro show ID         Show a specific retrospective
          """)

          :none
      end

    if period != :none do
      Watchman.Retro.generate(period)
      Watchman.Cache.update_retro_ids()
    end
  end

  defp retro_list do
    alias Watchman.Models.Retrospective

    retros =
      Repo.all(
        from r in Retrospective,
          order_by: [desc: r.generated_at],
          select: %{
            id: r.id,
            period_type: r.period_type,
            start_date: r.start_date,
            end_date: r.end_date,
            generated_at: r.generated_at
          }
      )

    if retros == [] do
      IO.puts("No retrospectives yet. Generate one: wm retro -w")
    else
      IO.puts("Retrospectives:\n")
      IO.puts("  ID   Period    Range                    Generated")
      IO.puts("  ---- -------- ------------------------ -------------------")

      for r <- retros do
        id = String.pad_leading(to_string(r.id), 4)
        period = String.pad_trailing(r.period_type, 8)
        range = "#{r.start_date} → #{r.end_date}"
        range_pad = String.pad_trailing(range, 24)
        generated = format_datetime(r.generated_at)
        IO.puts("  #{id} #{period} #{range_pad} #{generated}")
      end
    end
  end

  defp retro_show(id_str) do
    alias Watchman.Models.Retrospective

    case Integer.parse(id_str) do
      {id, _} ->
        case Repo.get(Retrospective, id) do
          nil ->
            IO.puts("Retrospective ##{id} not found.")

          retro ->
            IO.puts("""
            Retrospective ##{retro.id}
            Period: #{retro.period_type} (#{retro.start_date} → #{retro.end_date})
            Generated: #{format_datetime(retro.generated_at)}
            ─────────────────────────────────────────

            #{retro.content}
            """)
        end

      :error ->
        IO.puts("Invalid ID. Usage: wm retro show 1")
    end
  end

  defp cmd_completions(shell) when shell in ["bash", "zsh"] do
    ext = if shell == "bash", do: "wm.bash", else: "wm.zsh"

    paths = [
      # Dev/project root
      Path.join([File.cwd!(), "completions", ext]),
      # Installed via install.sh
      Path.join([
        System.get_env("HOME") || "~",
        ".local",
        "share",
        "watchman",
        "completions",
        ext
      ]),
      # Relative to app dir
      Path.join([Application.app_dir(:watchman), "..", "..", "completions", ext]) |> Path.expand()
    ]

    case Enum.find(paths, &File.exists?/1) do
      nil -> IO.puts("Completion file not found. Searched:\n#{Enum.join(paths, "\n")}")
      path -> IO.write(File.read!(path))
    end
  end

  defp cmd_completions(_) do
    IO.puts("Usage: wm completions bash | zsh")
  end

  defp complete_tickers do
    Repo.all(from a in Asset, where: a.active == true, select: a.ticker, order_by: a.ticker)
    |> Enum.each(&IO.puts/1)
  end

  defp complete_retro_ids do
    alias Watchman.Models.Retrospective

    Repo.all(from r in Retrospective, select: r.id, order_by: [desc: r.id])
    |> Enum.each(fn id -> IO.puts(to_string(id)) end)
  end

  defp print_usage do
    IO.puts("""
    watchman - financial asset monitor

    Usage:
      wm setup                    Interactive configuration wizard
      wm schedule                  Set up daily automated runs
      wm schedule status           Show schedule status
      wm unschedule                Remove scheduled runs
      wm logs                      Show last 50 log lines
      wm logs -f                   Follow log in real-time
      wm logs -n 100               Show last N log lines
      wm assets TICKER1 TICKER2   Register assets to track
      wm list                     List tracked assets
      wm remove TICKER1           Stop tracking an asset
      wm run                      Run analysis for all tracked assets
      wm show                     Show today's analyses
      wm show TICKER              Show analysis history for a ticker
      wm show -l 5                Show last 5 analyses
      wm retro -w                 Generate weekly retrospective
      wm retro -m                 Generate monthly retrospective
      wm retro list               List all retrospectives
      wm retro show ID            Show a specific retrospective
      wm update                   Pull latest version from GitHub
    """)
  end

  defp cmd_update do
    project_dir = System.get_env("WATCHMAN_INSTALL_DIR") || File.cwd!()

    IO.puts("Updating watchman...")

    case System.cmd("git", ["pull", "--ff-only"], cd: project_dir, stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts(output)
        IO.puts("Fetching dependencies...")

        case System.cmd("mix", ["deps.get"], cd: project_dir, stderr_to_stdout: true) do
          {_, 0} ->
            IO.puts("\n✓ Watchman updated successfully.")

          {err, _} ->
            IO.puts("Failed to fetch deps: #{err}")
        end

      {output, _} ->
        IO.puts("Update failed:\n#{output}")
    end
  end
end
