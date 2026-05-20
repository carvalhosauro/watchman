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
    * `rsi/2` — requires at least `period + 1` snapshots.
    * `zscore/2` — requires at least `period` snapshots and `period >= 2`.
    * `streak/1` — no minimum; empty/single → `%{direction: :up, days: 0}`, never errors.

  ## EMA seeding

  EMA is seeded with the SMA of the first `period` prices (SMA-seeded variant);
  subsequent values use the standard multiplier `k = 2 / (period + 1)`.

  ## RSI (Relative Strength Index)

  RSI uses Wilder smoothing (multiplier `1/period`). When `avg_loss == 0`,
  RSI returns `100.0` by convention to avoid division by zero. This applies
  to both the all-gain and the flat (zero-delta) cases.

  ## Streak conventions

  `streak/1` never returns `{:error, _}`. Equal consecutive prices break the
  streak. An empty or single-element list returns
  `{:ok, %{direction: :up, days: 0}}` by convention.

  ## Z-score variance

  Z-score uses **sample variance** (denominator `n - 1`) for consistency with
  statistical convention on finite windows. When the price series is flat
  (stddev == 0), `zscore/2` returns `{:error, :insufficient_data}` rather
  than divide-by-zero.
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

  @spec rsi([PriceSnapshot.t()], pos_integer()) :: {:ok, float()} | {:error, :insufficient_data}
  def rsi(snapshots, period \\ 14)

  def rsi(snapshots, period) when is_list(snapshots) and is_integer(period) and period > 0 do
    if length(snapshots) < period + 1 do
      {:error, :insufficient_data}
    else
      prices = Enum.map(snapshots, & &1.price)

      deltas =
        prices
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      {seed_deltas, rest_deltas} = Enum.split(deltas, period)

      avg_gain = Enum.sum(Enum.map(seed_deltas, fn d -> max(d, 0.0) end)) / period
      avg_loss = Enum.sum(Enum.map(seed_deltas, fn d -> max(-d, 0.0) end)) / period

      {final_gain, final_loss} =
        Enum.reduce(rest_deltas, {avg_gain, avg_loss}, fn d, {ag, al} ->
          {(ag * (period - 1) + max(d, 0.0)) / period,
           (al * (period - 1) + max(-d, 0.0)) / period}
        end)

      if final_loss == 0.0 do
        {:ok, 100.0}
      else
        rs = final_gain / final_loss
        {:ok, 100.0 - 100.0 / (1.0 + rs)}
      end
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

  @spec streak([PriceSnapshot.t()]) ::
          {:ok, %{direction: :up | :down, days: non_neg_integer()}}
  def streak(snapshots) when is_list(snapshots) do
    case Enum.reverse(Enum.map(snapshots, & &1.price)) do
      [] ->
        {:ok, %{direction: :up, days: 0}}

      [_] ->
        {:ok, %{direction: :up, days: 0}}

      [latest, prev | rest] ->
        cond do
          latest > prev -> do_streak(:up, prev, rest, 1)
          latest < prev -> do_streak(:down, prev, rest, 1)
          true -> {:ok, %{direction: :up, days: 0}}
        end
    end
  end

  @spec zscore([PriceSnapshot.t()], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  def zscore(snapshots, period \\ 21)

  def zscore(snapshots, period) when is_list(snapshots) and is_integer(period) and period > 0 do
    if period < 2 or length(snapshots) < period do
      {:error, :insufficient_data}
    else
      prices = snapshots |> Enum.take(-period) |> Enum.map(& &1.price)
      mean = Enum.sum(prices) / period
      sum_sq = Enum.sum(Enum.map(prices, fn p -> (p - mean) * (p - mean) end))
      stddev = :math.sqrt(sum_sq / (period - 1))

      if stddev == 0.0 do
        {:error, :insufficient_data}
      else
        {:ok, (List.last(prices) - mean) / stddev}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_streak(direction, _prev, [], count), do: {:ok, %{direction: direction, days: count}}

  defp do_streak(direction, prev, [next | rest], count) do
    continues =
      case direction do
        :up -> prev > next
        :down -> prev < next
      end

    if continues do
      do_streak(direction, next, rest, count + 1)
    else
      {:ok, %{direction: direction, days: count}}
    end
  end
end
