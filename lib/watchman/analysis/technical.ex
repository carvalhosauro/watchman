defmodule Watchman.Analysis.Technical do
  @moduledoc """
  Pure technical-indicator computations over a list of `%Watchman.Models.PriceSnapshot{}`.

  ## Input convention

  All functions accept a list of `%Watchman.Models.PriceSnapshot{}` structs ordered
  **oldest → newest** (the last element is the most recent snapshot). None of the
  functions mutate state, perform I/O, or access the database.

  ## Error convention

  Every public function returns a tagged tuple:

    * `{:ok, value}` — computation succeeded.
    * `{:error, :insufficient_data}` — the snapshot list is too short for the requested
      window. Functions never raise on bad input.

  ## Minimum snapshot counts

    * `sma/2` — requires at least `period` snapshots.
    * `ema/2` — requires at least `period` snapshots (SMA-seeded).

  ## EMA seeding

  EMA is seeded with the SMA of the first `period` prices (SMA-seeded variant);
  subsequent values use the standard multiplier `k = 2 / (period + 1)`.

  ## Z-score variance

  Z-score uses **sample variance** (denominator `n - 1`) for consistency with
  statistical convention on finite windows.
  """

  alias Watchman.Models.PriceSnapshot

  @spec sma([PriceSnapshot.t()], pos_integer()) :: {:ok, float()} | {:error, :insufficient_data}
  def sma(snapshots, period) when is_list(snapshots) and is_integer(period) and period > 0 do
    if length(snapshots) < period do
      {:error, :insufficient_data}
    else
      prices =
        snapshots
        |> Enum.take(-period)
        |> Enum.map(& &1.price)

      {:ok, Enum.sum(prices) / period}
    end
  end

  @spec ema([PriceSnapshot.t()], pos_integer()) :: {:ok, float()} | {:error, :insufficient_data}
  def ema(snapshots, period) when is_list(snapshots) and is_integer(period) and period > 0 do
    if length(snapshots) < period do
      {:error, :insufficient_data}
    else
      prices = Enum.map(snapshots, & &1.price)
      multiplier = 2.0 / (period + 1)
      seed_prices = Enum.take(prices, period)
      seed = Enum.sum(seed_prices) / period

      result =
        prices
        |> Enum.drop(period)
        |> Enum.reduce(seed, fn p, ema_prev -> (p - ema_prev) * multiplier + ema_prev end)

      {:ok, result}
    end
  end
end
