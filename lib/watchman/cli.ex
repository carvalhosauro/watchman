defmodule Watchman.CLI do
  alias Watchman.Models.{Asset, Analysis, PriceSnapshot}
  alias Watchman.Repo
  import Ecto.Query

  def main(args) do
    Application.ensure_all_started(:watchman)

    case args do
      ["assets" | tickers] -> cmd_assets(tickers)
      ["list"] -> cmd_list()
      ["remove" | tickers] -> cmd_remove(tickers)
      ["run" | opts] -> cmd_run(opts)
      ["show" | opts] -> cmd_show(opts)
      ["retro" | opts] -> cmd_retro(opts)
      _ -> print_usage()
    end
  end

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

  defp detect_type(ticker) do
    # FIIs typically end in 11 (e.g., MXRF11, HGLG11, XPLG11)
    if Regex.match?(~r/\d{2}$/, ticker) and String.ends_with?(ticker, "11") do
      "fii"
    else
      "acao"
    end
  end

  defp cmd_list do
    assets = Repo.all(from a in Asset, where: a.active == true, order_by: a.ticker)
    if assets == [] do
      IO.puts("No assets tracked. Use: wm assets TICKER1 TICKER2")
    else
      IO.puts("Tracked assets:")
      for asset <- assets do
        type_label = if asset.type, do: " (#{asset.type})", else: ""
        IO.puts("  #{asset.ticker}#{type_label}")
      end
    end
  end

  defp cmd_remove([]) do
    IO.puts("Usage: wm remove TICKER1 TICKER2 ...")
  end

  defp cmd_remove(tickers) do
    for ticker <- tickers do
      ticker = String.upcase(ticker)
      case Repo.get_by(Asset, ticker: ticker) do
        nil -> IO.puts("? #{ticker} (not found)")
        asset ->
          Repo.update!(Asset.changeset(asset, %{active: false}))
          IO.puts("- #{ticker}")
      end
    end
  end

  defp cmd_run(_opts) do
    # Will be wired to Pipeline.run/0 in step 5
    IO.puts("Running analysis...")
    Watchman.Pipeline.run()
  end

  defp cmd_show(opts) do
    {parsed, args, _} = OptionParser.parse(opts,
      switches: [last: :integer],
      aliases: [l: :last]
    )
    ticker = List.first(args)
    limit = parsed[:last]

    query =
      from a in Analysis,
        join: asset in Asset, on: a.asset_id == asset.id,
        join: s in PriceSnapshot, on: a.snapshot_id == s.id,
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

    query =
      if ticker do
        t = String.upcase(ticker)
        from [a, asset, s] in query, where: asset.ticker == ^t
      else
        today = Date.utc_today()
        start_dt = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
        from [a, asset, s] in query, where: a.analyzed_at >= ^start_dt
      end

    query = if limit, do: from(q in query, limit: ^limit), else: query

    results = Repo.all(query)

    if results == [] do
      if ticker do
        IO.puts("No analyses found for #{String.upcase(ticker)}.")
      else
        IO.puts("No analyses found for today. Run: wm run")
      end
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

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_var(nil), do: "N/A"
  defp format_var(val), do: "#{val}%"

  defp cmd_retro(opts) do
    # Will be wired to Retro module in step 6
    {parsed, _, _} = OptionParser.parse(opts,
      switches: [weekly: :boolean, monthly: :boolean],
      aliases: [w: :weekly, m: :monthly]
    )
    period = cond do
      parsed[:weekly] -> :weekly
      parsed[:monthly] -> :monthly
      true ->
        IO.puts("Usage: wm retro --weekly | --monthly")
        :none
    end
    if period != :none do
      Watchman.Retro.generate(period)
    end
  end

  defp print_usage do
    IO.puts("""
    watchman - financial asset monitor

    Usage:
      wm assets TICKER1 TICKER2   Register assets to track
      wm list                     List tracked assets
      wm remove TICKER1           Stop tracking an asset
      wm run                      Run analysis for all tracked assets
      wm show                     Show today's analyses
      wm show TICKER              Show analysis history for a ticker
      wm show --last 5            Show last 5 analyses
      wm retro --weekly           Generate weekly retrospective
      wm retro --monthly          Generate monthly retrospective
    """)
  end
end
