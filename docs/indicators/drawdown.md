# DRAWDOWN — decline from the peak

**Formula:** `(close − peak) / peak × 100`, where peak is the highest close in
the series.

**Unit:** % (always ≤ 0).

## How to read

- **0%** — the current close is the series peak.
- **−22%** — 22% below the highest close of the period.

`wm scan --detail` also shows the reference peak's date and value.

## Limitations

- Needs ≥ 2 trading days.
- Uses closes; ignores intraday highs.
- Measures distance from the top, not how long the decline lasted.

## What it does not mean

A large DRAWDOWN does **not** signal an imminent recovery nor that the asset
"has to" rebound. It is a descriptive measure of how far price fell from its
top, not a forecast.
