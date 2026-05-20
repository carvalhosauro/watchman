defmodule Watchman.Analysis.Indicators do
  @moduledoc """
  All-or-nothing result of `Watchman.Analysis.Technical.indicators/1`.

  Holds the full snapshot of computed technical indicators for an asset
  at a single point in time. Track 4's classifier consumes this struct
  to derive a deterministic `%Signal{}`.

  All eight fields are required (`@enforce_keys`). The struct is never
  constructed partially — if any underlying indicator cannot be computed
  (insufficient snapshot history), `Technical.indicators/1` returns
  `{:error, :insufficient_data}` instead of a half-populated struct.
  """

  @enforce_keys [
    :sma7,
    :sma21,
    :sma50,
    :ema21,
    :rsi14,
    :zscore21,
    :streak,
    :drawdown_from_peak
  ]

  defstruct [
    :sma7,
    :sma21,
    :sma50,
    :ema21,
    :rsi14,
    :zscore21,
    :streak,
    :drawdown_from_peak
  ]

  @type streak :: %{direction: :up | :down, days: non_neg_integer()}

  @type t :: %__MODULE__{
          sma7: float(),
          sma21: float(),
          sma50: float(),
          ema21: float(),
          rsi14: float(),
          zscore21: float(),
          streak: streak(),
          drawdown_from_peak: float()
        }
end
