# Track 2 — Technical Analysis (v0.4.0)

Concrete prep for the second realignment track. See
[`REALIGNMENT.md`](REALIGNMENT.md) for the broader rationale.

## Status — shipped v0.4.0

Track 2 shipped as of v0.4.0. Commits `b31cb54` (Indicators struct)
through `daaee56` (version bump) on branch `dev`.
All public functions in `Watchman.Analysis.Technical` covered;
`Watchman.Analysis.Technical` and `Watchman.Analysis.Indicators`
at 100% coverage.

The task list at the bottom of this document is preserved as the
historical record of how the track was decomposed.

## Goal

Own deterministic technical indicators computed directly from stored
`price_snapshots`. Pure functions. 100% unit-testable. Zero new external
APIs. Zero new runtime dependencies.

The indicators feed Track 4's `Watchman.Analysis.Classifier` — Track 2
itself produces no user-visible output and does NOT modify
`Watchman.Pipeline`. Wiring happens in Track 4.

## Module surface

A single module exposes pure functions:

```elixir
defmodule Watchman.Analysis.Technical do
  @moduledoc """
  Pure technical indicators computed on a list of price_snapshots
  ordered oldest → newest. Every function returns a tagged tuple and
  never raises on insufficient data.

  Minimum snapshot history required to compute the full `%Indicators{}`
  struct: 50 snapshots (for sma50). RSI requires 15 (period + 1) and
  zscore21 requires 21.
  """

  @spec sma([snapshot], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  @spec ema([snapshot], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  @spec rsi([snapshot], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  @spec zscore([snapshot], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  @spec streak([snapshot]) ::
          {:ok, %{direction: :up | :down, days: non_neg_integer()}}
  @spec drawdown([snapshot], pos_integer()) ::
          {:ok, float()} | {:error, :insufficient_data}
  @spec indicators([snapshot]) ::
          {:ok, %Watchman.Analysis.Indicators{}}
          | {:error, :insufficient_data}

  # rsi defaults to period 14, zscore to 21
  def rsi(snapshots, period \\ 14)
  def zscore(snapshots, period \\ 21)
end
```

`snapshot` is a `%Watchman.Models.PriceSnapshot{}` (only `price` is read;
the function does not depend on `fetched_at` ordering being chronological
— callers are responsible for passing the list ordered oldest → newest).

## `%Indicators{}` struct

```elixir
defmodule Watchman.Analysis.Indicators do
  @enforce_keys [
    :sma7, :sma21, :sma50,
    :ema21,
    :rsi14,
    :zscore21,
    :streak,
    :drawdown_from_peak
  ]

  defstruct [
    :sma7, :sma21, :sma50,
    :ema21,
    :rsi14,
    :zscore21,
    :streak,
    :drawdown_from_peak
  ]

  @type t :: %__MODULE__{
          sma7: float(),
          sma21: float(),
          sma50: float(),
          ema21: float(),
          rsi14: float(),
          zscore21: float(),
          streak: %{direction: :up | :down, days: non_neg_integer()},
          drawdown_from_peak: float()
        }
end
```

`Technical.indicators/1` returns `{:ok, %Indicators{}}` only when every
field can be computed (i.e., the snapshot list has at least 50 entries).
Otherwise `{:error, :insufficient_data}`. There is no partial result.

## Formulas + reference values

Each public function has at least one test case with a hardcoded
reference value computed in a spreadsheet (LibreOffice / Google Sheets
acceptable). The fixture and the spreadsheet-computed value live
inline in the test file with a comment pointing at the formula used.

### SMA (Simple Moving Average)

```
sma(prices, period) = sum(last period prices) / period
```

Reference: for `[1.0, 2.0, 3.0, 4.0, 5.0]`, `sma/2 ... 3 = (3+4+5)/3 = 4.0`.

### EMA (Exponential Moving Average)

```
multiplier = 2 / (period + 1)
ema_0      = sma of first `period` values
ema_n      = (price_n - ema_(n-1)) * multiplier + ema_(n-1)
```

Use the SMA-seeded variant (the most common spreadsheet form). Reference
values must be validated against a sheet computing the recurrence
explicitly.

### RSI (Relative Strength Index)

```
gain_n / loss_n = mean of positive / negative price changes over `period`
                  using Wilder's smoothing (NOT simple average)
rs              = avg_gain / avg_loss
rsi             = 100 - 100 / (1 + rs)
```

Wilder's smoothing is the standard. RSI requires `period + 1` snapshots
(to compute `period` price changes).

Reference: pin against a known dataset from a charting library or
textbook. The first 14 deltas seed the smoothed averages.

### Z-score

```
zscore(prices, period) = (last_price - sma(prices, period))
                         / stddev(last `period` prices, :sample)
```

Use sample standard deviation (`n - 1` denominator), the spreadsheet
default. Document choice in module doc.

### Streak

Counts consecutive same-direction daily changes ending at the most
recent snapshot. `:up` if `price_n > price_(n-1)`, `:down` if `<`. Equal
prices break the streak (return `{:ok, %{direction: :up, days: 0}}` or
`{:ok, %{direction: :down, days: 0}}` — see `Open Question` below).

Reference: `[1.0, 2.0, 3.0, 4.0]` → `%{direction: :up, days: 3}`.

### Drawdown from peak

```
peak       = max of last `period` prices
drawdown   = (last_price - peak) / peak * 100.0
```

Always returns a non-positive float (0.0 when at peak). Reference:
peak 10.0, current 8.0 → drawdown -20.0.

## Open questions (resolve before coding starts)

1. **Streak on flat prices.** Equal prices break the streak. Should the
   returned direction match the previous direction, or default to
   `:up`? Decision: default to `:up` with `days: 0`. Document and test.

2. **EMA seeding.** SMA-seeded is the common spreadsheet form. Some
   libraries seed with the first price. Decision: SMA-seeded.
   Document in `@moduledoc`.

3. **Insufficient data threshold.** `rsi/2` needs `period + 1`
   snapshots (14 deltas requires 15 prices). Document precisely per
   function. `indicators/1` requires 50.

## Constraints (apply throughout)

- **Pure.** No DB calls, no HTTP, no process communication, no `Process.put`.
- **Tagged tuples on error.** Never raise on insufficient data.
- **`@spec` on every public function.**
- **`@moduledoc` on the module** documenting the minimum-snapshots
  requirement per function.
- **No new runtime dependencies.** All math from `:math` and Elixir
  stdlib.
- **`mix credo --strict` clean on all new files.**
- **No `IO.inspect`.**
- **Not wired into `Pipeline`** — Track 4 is responsible for that.
- **Coverage 100%** on `Watchman.Analysis.Technical` and
  `Watchman.Analysis.Indicators`.

## Test plan

| Layer | Cases |
|-------|-------|
| `sma/2` | reference value; insufficient data; period = 1; period = list length |
| `ema/2` | spreadsheet-validated reference (5+ point series); insufficient; period = list length |
| `rsi/2` | spreadsheet-validated reference using Wilder smoothing on a ≥20-point dataset; insufficient; all-gain (rsi → 100); all-loss (rsi → 0); flat (avg_loss = 0 edge case must not divide by zero — return 100.0 by convention) |
| `zscore/2` | reference value; insufficient; period = 1 (stddev undefined — return `{:error, :insufficient_data}`); flat input (stddev = 0 → return `{:error, :insufficient_data}` to avoid div-by-zero) |
| `streak/1` | up streak; down streak; broken by flat; broken by direction change; single-element list (`days: 0`); empty list (return `{:ok, %{direction: :up, days: 0}}` or error — pick and document) |
| `drawdown/2` | at peak (0.0); 50% drawdown; insufficient |
| `indicators/1` | full happy path on 60-point series; insufficient (49 points) |

All tests live in `test/watchman/analysis/technical_test.exs`. Plain
`ExUnit.Case, async: true`. No DB.

## Ordered task list

1. **`Watchman.Analysis.Indicators` struct** in
   `lib/watchman/analysis/indicators.ex`. `@enforce_keys`, `defstruct`,
   `@type t`. No functions. Test that all fields are required.

2. **`Watchman.Analysis.Technical.sma/2`** in
   `lib/watchman/analysis/technical.ex`. Module skeleton +
   `@moduledoc`. Reference test.

3. **`Technical.ema/2`** with SMA-seeded variant. Spreadsheet reference.

4. **`Technical.rsi/2`** with Wilder smoothing. Spreadsheet reference.
   Edge cases (all-gain, all-loss, flat).

5. **`Technical.zscore/2`**. Sample stddev. Flat-input error path.

6. **`Technical.streak/1`** with direction + days. Flat-input
   convention documented.

7. **`Technical.drawdown/2`**. Always non-positive return.

8. **`Technical.indicators/1`** aggregator returning `%Indicators{}`.
   All-or-nothing semantics. Happy path + insufficient-data test.

9. **`mix.exs` version bump** to `0.4.0` once 1-8 land clean.

10. **Docs:** mark v0.4.0 done in ROADMAP, update ARCHITECTURE module
    map (`Analysis.Technical` and `Analysis.Indicators` → shipped),
    add Status block to this document.

Each step is independently committable. Conventional Commits prefix:
`feat(technical):` for code, `docs:` for the last step.

## Out of scope (lands in later tracks)

- Pipeline integration — Track 4.
- News fetching — Track 3.
- Classifier rule engine consuming `%Indicators{}` — Track 4.
- Loading snapshots from DB — caller's responsibility.

## References

- [REALIGNMENT.md](REALIGNMENT.md) — Track 2 section.
- [ROADMAP.md](../ROADMAP.md) — v0.4.0 milestone.
- [ARCHITECTURE.md](../ARCHITECTURE.md) — module map.
- [track-1-accuracy.md](track-1-accuracy.md) — prior-track format reference.
