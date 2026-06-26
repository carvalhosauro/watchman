# RANGE — position in the 52-week band

**Formula:** `(close − low) / (high − low) × 100`, over the full available
series (≥ 200 trading days from the ~1-year window).

**Unit:** % from 0 to 100.

## How to read

- **Near 0%** — the close sits near the period's low.
- **Near 100%** — the close sits near the period's high.
- **~50%** — mid-band.

It is the price's relative position inside the year's low–high range. The
`wm scan` table sorts by RANGE ascending (lowest position first) — that is only
a sort key, not a recommendation.

## Limitations

- Needs ≥ 200 trading days; with fewer, the field is omitted.
- Low and high are closes, not intraday extremes.
- A narrow band (high ≈ low) makes the position unstable.

## What it does not mean

A low RANGE does **not** mean "cheap" and a high RANGE does **not** mean
"expensive". It is price geometry, not valuation. It is not a buy or sell signal.
