# `wm scan` indicators

`wm scan` prints a **neutral, factual** technical readout of the tickers you
follow — numbers, with no buy or sell verdict. This folder explains each column.

| Column | Indicator | Reference |
|---|---|---|
| RANGE | Position in the 52-week band | [range.md](range.md) |
| DRAWDOWN | Decline from the peak | [drawdown.md](drawdown.md) |
| vs SMA200 | Distance from the 200-day average | [sma200.md](sma200.md) |
| RSI | Relative strength (Wilder 14) | [rsi.md](rsi.md) |
| VOL | Volume vs the 20-day average | [volume.md](volume.md) |

The table sorts by **RANGE ascending** (lowest position in the band first). That
is only a sort key, **not** a recommendation.

In the terminal: `wm explain <indicator>` (e.g. `wm explain range`) or
`wm explain --list`.

## Disclaimer

`watchman` gives no buy/sell advice, price targets, or valuation. Technical
indicators are **descriptive, not predictive**. Fundamentals are out of scope.
