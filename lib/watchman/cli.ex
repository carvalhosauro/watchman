defmodule Watchman.CLI do
  alias Watchman.Models.Asset
  alias Watchman.Repo
  import Ecto.Query

  def main(args) do
    Application.ensure_all_started(:watchman)

    case args do
      ["assets" | tickers] -> cmd_assets(tickers)
      ["list"] -> cmd_list()
      ["remove" | tickers] -> cmd_remove(tickers)
      ["run" | opts] -> cmd_run(opts)
      ["retro" | opts] -> cmd_retro(opts)
      _ -> print_usage()
    end
  end

  defp cmd_assets([]) do
    IO.puts("Usage: wm assets TICKER1 TICKER2 ...")
  end

  defp cmd_assets(tickers) do
    for ticker <- tickers do
      ticker = String.upcase(ticker)
      case Repo.get_by(Asset, ticker: ticker) do
        nil ->
          {:ok, _} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: ticker}))
          IO.puts("+ #{ticker}")
        %{active: false} = asset ->
          Repo.update!(Asset.changeset(asset, %{active: true}))
          IO.puts("+ #{ticker} (reactivated)")
        _existing ->
          IO.puts("~ #{ticker} (already tracked)")
      end
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

  defp cmd_retro(opts) do
    # Will be wired to Retro module in step 6
    {parsed, _, _} = OptionParser.parse(opts, switches: [weekly: :boolean, monthly: :boolean])
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
      wm retro --weekly           Generate weekly retrospective
      wm retro --monthly          Generate monthly retrospective
    """)
  end
end
