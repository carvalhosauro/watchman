# watchman anomaly engine — design spec

> Date: 2026-06-21 · Branch: `feat/anomaly-engine` · Status: approved for planning

## Context & pivot

watchman's v2.0.0 core was a deterministic ignore/LOOK glance from two signals: a
price z-score **or** a fresh CVM material fact. Research (see
[`docs/design/2026-06-21-news-source.md`](../../design/2026-06-21-news-source.md))
showed no global material-fact RSS feed exists — the only live sources are an
undocumented B3 JSON proxy or a weekly CVM CSV. **The sourcing effort doesn't justify
the value**, so news is dropped as a core signal.

The new differentiator is what watchman is already strongest at: **deterministic,
pure, auditable math**. The core becomes a **multi-signal price/volume anomaly
engine** — each held ticker gets a severity (calm / watch / LOOK) explained
line-by-line by the signals that fired. No news, no fundamentals, no DB, no AI,
no editorial weights. It points; it doesn't recommend.

## Goal

For each ticker the user holds, `wm run` answers "does this deserve my attention
today, and exactly why?" by running independent statistical signals over ~1 year of
daily prices+volume, taking the worst severity, and ranking holdings worst-first.

## Non-goals (out of scope)

News · fundamentals/valuation (Bazin/Graham/Lynch) · FII screening · a TUI · editorial
signal weighting · ML/prediction · buy/sell advice · new data sources beyond Yahoo.

## Architecture

Pure logic isolated from I/O; each unit independently testable.

```
cmd/run.go ──> glance.Run(tickers)            (impure: fetch per ticker)
                   │
                   ├─ prices.History(t) ─────> []Bar{Date,Close,Volume}   (Yahoo, 1y)
                   └─ signals.Evaluate(bars) ─> []Signal{Name,Value,Severity,Reason}
                          │
                          └─ verdict.Decide(signals) ─> Decision{Severity,Fired,Count}
                   │
glance.BuildRow (pure) ─> Row{Ticker,Severity,Count,Reason,sortKey}
glance.Format (pure) ───> sorted worst-first
```

### Packages

- **`internal/prices`** — change `History(ticker) ([]Bar, error)`; `type Bar struct { Date string; Close, Volume float64 }`. Fetch `range=1y&interval=1d`; parse `close` **and** `volume` arrays (drop bars where close is null). `BaseURL` / `WATCHMAN_PRICES_URL` seam unchanged.
- **`internal/signals`** *(new — replaces `internal/anomaly`, which is deleted)* — one pure func per signal: `(bars []prices.Bar) (Signal, bool)` returning the signal + whether it has enough data. `Evaluate(bars) []Signal` runs them all and returns those at ≥ Watch. `type Severity int` (`Calm`, `Watch`, `Look`); `type Signal struct { Name string; Value float64; Severity Severity; Reason string }`.
- **`internal/verdict`** — rewritten: `Decide(signals []signals.Signal) Decision`; `type Decision struct { Severity Severity; Count int; Reason string }`. Severity = max across signals (Calm if none fired); Count = number of fired signals; Reason = joined per-signal reasons. No `hasNews`.
- **`internal/glance`** — `BuildRow` consumes signals+verdict; `Run` drops the news fetch; `Format` sorts rows by (Severity desc, Count desc, top-signal magnitude desc) and renders. `Row` carries a sort key.
- **delete `internal/news`** and its wiring in `glance.Run` / `cmd/run.go`.
- **delete `internal/anomaly`** (absorbed into `signals`).

## Signals (v1) — definitions, thresholds, value

Thresholds are documented, tunable constants in `signals`. Each signal needs a minimum
history; if absent it simply doesn't fire (engine degrades, never errors).

| Signal | Definition | watch | LOOK | min data |
|---|---|---|---|---|
| **zscore** | z of latest daily return vs prior daily returns | \|z\| ≥ 2 | \|z\| ≥ 3 | 3 closes |
| **rsi** | Wilder RSI(14) of closes | >70 or <30 | >80 or <20 | 15 closes |
| **drawdown** | % below the trailing peak (window: full series) | ≤ −10% | ≤ −20% | 2 closes |
| **prox52w** | distance to 1y high/low (or break beyond) | within 3% | new high/low | ~200 closes |
| **volume** | latest volume ÷ trailing 20-day avg volume | ≥ 2× | ≥ 3× | 21 bars w/ volume |

Each lens catches a distinct failure mode: magnitude (zscore), momentum extreme (rsi),
cumulative loss (drawdown), yearly extreme (prox52w), participation/conviction (volume).
RSI uses Wilder smoothing; **cross-check rsi & drawdown against the spreadsheet-validated
reference `analysis/technical.ex` in tag `v0.6.0-elixir-reference` (±0.1)**.

### Verdict & ranking

- Per-ticker severity = the **max** severity among its signals; `Calm` if none ≥ Watch.
- **Count** = how many signals fired (≥ Watch) — the tiebreaker; "3 lenses agree" ranks
  above "1 lens" within the same severity. No weighting.
- `wm run` shows **all** held tickers, sorted **worst-first** (Severity, then Count, then
  magnitude). Calm rows render last. A `--look` flag (optional, v1) hides Calm rows.

### Output shape

```
watchman — 2026-06-21
  ⚠ LOOK    PETR4    −6.1% (2.8σ) · RSI 82 · −22% vs peak        [3 signals]
    watch   VALE3    near 52w high (1.4%)                         [1 signal]
    calm    MXRF11   quiet
```
(Exact glyphs/columns finalized in implementation; severity label + ticker + fired
signals with values + count.)

## Data flow & errors

`glance.Run` fetches each ticker independently; a fetch error → that row is `calm` with
reason "no price data" (today's behavior). Insufficient history for a signal → that
signal silently doesn't fire. The engine never errors the whole run on one bad ticker.

## Testing

- **Per signal**: table tests — a clear watch case, a clear LOOK case, a calm case, and
  the degenerate edges (too few bars, σ=0, zero/again-flat volume, exact threshold).
- **Engine**: `signals.Evaluate` + `verdict.Decide` over crafted series → expected
  severity + count + ordering.
- **Flow**: `wm run` via `httptest` serving a 1-year close+volume JSON fixture; assert
  ranking and the rendered reasons. Hermetic (no real network), per the existing
  `WATCHMAN_PRICES_URL` seam + testscript `.txtar`.
- Coverage floor stays **80**; live smoke (`-tags live`) updated for the richer row.

## Migration / breaking changes

- `prices.History` return type changes (`[]float64` → `[]Bar`) — internal only.
- `internal/anomaly` and `internal/news` deleted; `verdict.Decide` signature changes.
- CLI surface unchanged (`wm wallet …`, `wm run`); output is richer. Ship as **v2.1.0**.
- ROADMAP.md updated: v2.1 is the anomaly engine (news removed); the abandoned
  `fix/news-feed` branch is dropped.

## Tunable defaults (recorded, not bikeshedding)

drawdown peak window = full 1y series · volume avg window = 20 trading days · prox52w
band = 3% · all thresholds per the table above. These are constants, changeable later.
