# RSI — Relative Strength Index (14)

**Calculation:** Wilder RSI with a 14-period over closes — the same algorithm as
the `wm run` anomaly engine.

**Unit:** 0 to 100.

## How to read

- **> 70** — conventionally called "overbought".
- **< 30** — conventionally called "oversold".
- **~50** — neutral momentum.

## Limitations

- Needs ≥ 15 closes.
- In strong trends the RSI can sit at an extreme for a long time.

## What it does not mean

A low RSI does **not** mean "buy" and a high RSI does **not** mean "sell".
Extremes describe recent momentum; they do not turn price on their own.
