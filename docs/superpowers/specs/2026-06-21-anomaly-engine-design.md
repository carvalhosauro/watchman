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
config.Load() ─> Thresholds  (from ~/.config/watchman/config.toml, or defaults)
cmd/run.go ──> glance.Run(tickers, cfg)       (impure: fetch per ticker)
                   │
                   ├─ prices.History(t) ─────────> []Bar{Date,Close,Volume}   (Yahoo, 1y)
                   └─ signals.Evaluate(bars,cfg) ─> []Signal{Name,Value,Severity,Reason}  (incl. Calm)
                          │
                          └─ verdict.Decide(signals) ─> Decision{Severity,Count,Reason}
                   │
glance.BuildRow (pure) ─> Row{Ticker,Severity,Count,Reason,sortKey}
glance.Format (pure) ───> sorted worst-first
```

### Packages

- **`internal/prices`** — change `History(ticker) ([]Bar, error)`; `type Bar struct { Date string; Close, Volume float64 }`. Fetch `range=1y&interval=1d`; parse `close` **and** `volume` arrays (drop bars where close is null). `BaseURL` / `WATCHMAN_PRICES_URL` seam unchanged.
- **`internal/signals`** *(new — replaces `internal/anomaly`, which is deleted)* — one pure func per signal: `(bars []prices.Bar, cfg Thresholds) (Signal, bool)` returning the signal (severity may be **Calm**) + whether it had enough data. `Evaluate(bars, cfg) []Signal` runs them all and returns **every computable signal, including Calm ones** (presentation decides what to show). `type Severity int` (`Calm`, `Watch`, `Look`); `type Signal struct { Name string; Value float64; Severity Severity; Reason string }`.
- **`internal/config`** *(new)* — `Load() (signals.Thresholds, error)` reads the config file (see Configuration) and fills any missing key from `signals.Defaults()`. The `Thresholds` type lives in `signals` (the consumer), so `config` imports `signals`, not the reverse — no cycle.
- **`internal/verdict`** — rewritten: `Decide(signals []signals.Signal) Decision`; `type Decision struct { Severity Severity; Count int; Reason string }`. Severity = max across signals (Calm if none ≥ Watch); Count = number of signals at ≥ Watch; Reason = joined reasons of the **fired** signals. No `hasNews`.
- **`internal/glance`** — `BuildRow` consumes signals+verdict; `Run` drops the news fetch; `Format` sorts rows by (Severity desc, Count desc, top-signal magnitude desc) and renders. `Row` carries a sort key.
- **delete `internal/news`** and its wiring in `glance.Run` / `cmd/run.go`.
- **delete `internal/anomaly`** (absorbed into `signals`).

## Signals (v1) — definitions, thresholds, value

Thresholds are user-tunable (see Configuration); `signals.Defaults()` holds the built-in
values shown below. Each signal needs a minimum history; if absent it simply doesn't fire
(engine degrades, never errors).

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

### Configuration (tunable thresholds)

Every threshold in the table is **user-configurable** via a config file at
`~/.config/watchman/config.toml` (env override `WATCHMAN_CONFIG`, same pattern as
`WATCHMAN_WALLET`). Missing file or missing key → the built-in default for that key.
`internal/config` loads it into a `Thresholds` struct passed to `signals.Evaluate`.

```toml
[zscore]
watch = 2.0
look  = 3.0
[rsi]
watch_high = 70   # look_high = 80, watch_low = 30, look_low = 20
[drawdown]
watch = -10   # percent
look  = -20
[prox52w]
band = 3.0    # percent within high/low = watch
[volume]
watch = 2.0   # ×avg
look  = 3.0
```

Format = **TOML** (human-readable, supports comments — investors will hand-tune these).
Costs one small mature dep (`BurntSushi/toml`). *Open knob for review:* TOML vs
stdlib-JSON (zero dep, no comments).

### Verdict & ranking

- Per-ticker severity = the **max** severity among its signals; `Calm` if none ≥ Watch.
- **Count** = how many signals fired (≥ Watch) — the tiebreaker; "3 lenses agree" ranks
  above "1 lens" within the same severity. No weighting.
- `wm run` shows **all** held tickers, sorted **worst-first** (Severity, then Count, then
  magnitude). Calm rows render last.

### CLI surface

- `wm run` — the ranked glance over the wallet (summary: only fired signals per row).
- `wm run [TICKER...]` — limit to the given tickers (any valid ticker, need not be in the
  wallet — handy for an ad-hoc check); empty args → the wallet.
- `wm run --look` — hide Calm rows (show only watch/LOOK).
- `wm run --detail` — **detailed mode**: print **every** signal for each ticker with its
  value and severity, calm or not (e.g. `z 0.4σ · RSI 55 · −3% peak · 12% to 52w high ·
  vol 1.1×`). Works for the whole list or a single ticker (`wm run PETR4 --detail`).
  This is why `signals.Evaluate` returns Calm signals too — `--detail` shows them all;
  the default view shows only the fired ones.

### Output shape

```
watchman — 2026-06-21
  ⚠ LOOK    PETR4    −6.1% (2.8σ) · RSI 82 · −22% vs peak        [3 signals]
    watch   VALE3    near 52w high (1.4%)                         [1 signal]
    calm    MXRF11   quiet
    —       XPTO3    No data
    —       ZZZZ3    API error
```
(Exact glyphs/columns finalized in implementation; severity label + ticker + fired
signals with values + count; failure rows show the failure class — see below.)

## Data flow & errors

`glance.Run` fetches each ticker independently and the run never aborts on one bad
ticker. Failures are **classified** (not lumped into a generic message):

- `errors.Is(err, prices.ErrNoData)` — HTTP 200 but no usable series (unknown ticker,
  empty/error payload) → row reason **"No data"**.
- any other error (request failed, non-200, body read error) → row reason **"API error"**.

Both render as a distinct, non-ranked row (severity shown as `—`), sorted after the
real verdicts. Insufficient history for a *specific* signal → that signal silently
doesn't fire (the ticker is still scored on whatever signals it has). `prices` returns
the typed errors so `glance.BuildRow` can branch on them.

## Testing

- **Per signal**: table tests — a clear watch case, a clear LOOK case, a calm case, and
  the degenerate edges (too few bars, σ=0, zero/again-flat volume, exact threshold).
- **Engine**: `signals.Evaluate` + `verdict.Decide` over crafted series → expected
  severity + count + ordering.
- **Config**: `internal/config` loads a temp file → expected `Thresholds`; missing file
  and missing keys → defaults; `WATCHMAN_CONFIG` override honored.
- **Errors**: `BuildRow` with `ErrNoData` → "No data"; with a generic error → "API error".
- **Detail mode**: `--detail` renders every signal (incl. Calm) for a ticker; default view
  renders only fired signals; `wm run TICKER` limits the set.
- **Flow**: `wm run` via `httptest` serving a 1-year close+volume JSON fixture; assert
  ranking, the rendered reasons, and the failure-class rows. Hermetic (no real network),
  per the existing `WATCHMAN_PRICES_URL` seam + testscript `.txtar`.
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
