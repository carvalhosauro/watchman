# watchman scan & opportunity indicators — design spec

> Date: 2026-06-25 · Status: approved for planning

## Context

watchman's v2.1 anomaly engine (`wm run`) answers **"did something unusual happen
today?"** — z-score, RSI extremes, drawdown, 52-week proximity, volume. It is a
point-in-time alert, not a recurring opportunity radar.

The user's job-to-be-done is different from portfolio tracking (Investidor10 covers
buy/sell history and fundamentals well). The gap is **technical opportunity
indicators**: knowing where price sits in its recent history, whether momentum has
exhausted, and how readings evolve over 2–3 weekly check-ins — without editorial
buy/sell advice.

Research in this design session established:

- **Fundamentals are out of scope** — Investidor10 Pro is the source of truth for
  Bazin, Graham, DY, P/L, etc.
- **The user does not need to know indicator jargon** — the CLI shows factual
  numbers; interpretation lives in docs and (optionally) a Cursor skill.
- **No SQLite, no daemon** — append-only NDJSON history + optional cron/systemd
  schedule matches watchman's local, auditable CLI philosophy.

## Goal

Add a **`wm scan`** command that prints a **neutral, factual table** of technical
readings per watched ticker, plus **`--json`** for machines/skills. Supplement with
**`docs/indicators/`** reference material and **`wm explain`** to surface it in the
terminal. Small wallet UX improvements so users can manage what they observe
without leaving the CLI.

`wm run` stays unchanged — anomaly alerts and opportunity scan are separate JTBDs.

## Non-goals (out of scope)

- Buy/sell advice, price targets, or editorial labels ("interessante", "compre").
- Fundamentals / valuation (Bazin, Graham, Lynch, DY, P/L, screening).
- SQLite, embedded DB, long-running daemon, push notifications.
- TUI, web UI, charts (ASCII sparklines deferred).
- MACD, SMA cross, streak signals — later phase, opt-in only if they earn their place.
- Cursor skill implementation in this phase (spec only; lives outside the Go binary).

## Design principles

1. **Data first, interpretation optional** — CLI rows are numbers and neutral
   context strings; no verdict beyond what the math says.
2. **Three layers** — CLI (facts) → docs (reference) → skill (natural-language digest).
3. **Same data, two surfaces** — human table and machine JSON from one code path.
4. **Reuse Yahoo 1y bars** — no new data sources; extend pure signal functions.
5. **Wallet = observation list** — not a portfolio; no quantities, cost basis, or P&L.

## Architecture

Pure indicator logic isolated from I/O; formatting and CLI wiring stay thin.

```
config.Load() ─> Thresholds + ScanConfig (defaults for scan-only knobs)
cmd/scan.go ──> scan.Run(tickers, cfg)          (impure: fetch per ticker)
                   │
                   ├─ prices.History(t) ────────> []Bar
                   └─ scan.Evaluate(bars, cfg) ─> ScanResult{Ticker, Readings[], Meta}
                          │
scan.FormatTable (pure) ──> aligned text table
scan.FormatJSON  (pure) ──> []ScanResult JSON
scan.FormatDetail(pure) ──> single-ticker expanded view

cmd/explain.go ──> embed or read docs/indicators/<name>.md

wallet.* ──> unchanged core; cmd/wallet.go gains multi-add, clear, default=list
```

### Packages

- **`internal/scan`** *(new)* — opportunity/readout indicators as pure functions over
  `[]prices.Bar`. Returns structured `Reading` values (name, value, unit, context)
  with no severity or editorial ranking. `Run(tickers)` fetches and assembles results.
- **`internal/scan/format.go`** *(new)* — `FormatTable`, `FormatJSON`, `FormatDetail`.
- **`internal/indicators/doc.go`** *(new, optional)* — embed `docs/indicators/*.md` via
  `//go:embed` for `wm explain`; or read from filesystem with embed fallback.
- **`cmd/scan.go`** *(new)* — `wm scan [TICKER...]`, flags `--detail`, `--json`.
- **`cmd/explain.go`** *(new)* — `wm explain [INDICATOR]`, `--list`.
- **`docs/indicators/`** *(new)* — human reference, one file per indicator + README.
- **`cmd/wallet.go`** — extend: multi-ticker `add`, `clear`, default subcommand = `list`.

Existing packages **`internal/signals`**, **`internal/glance`**, **`internal/verdict`**
remain for `wm run`; scan may share math helpers (e.g. RSI, drawdown) but must not
reuse anomaly severity thresholds or `verdict.Decide`.

## Scan indicators (v1)

Each reading is always emitted when enough bars exist; missing data omits that field
(detail view notes "insufficient history") rather than failing the row.

| Key | Label (table header) | Definition | Unit | Min bars |
|---|---|---|---|---|
| `range` | RANGE | Position of latest close in the 52-week (or full series) low–high band: `(close − low) / (high − low) × 100` | % (0–100) | 200 |
| `drawdown` | DRAWDOWN | `(close − peak) / peak × 100` over the full series | % (≤ 0) | 2 |
| `sma200` | vs SMA200 | `(close − SMA200) / SMA200 × 100` | % (+ above, − below) | 200 |
| `rsi` | RSI | Wilder RSI(14) on closes — same algorithm as `internal/signals/rsi.go` | 0–100 | 15 |
| `volume` | VOL | Latest volume ÷ 20-day average volume | × | 21 w/ volume |

**Ranking:** default table sort is by `range` ascending (lowest in yearly band first).
This is a **sort key**, not a recommendation. `--sort` flag deferred; document the
default in `docs/indicators/README.md`.

**Shared math:** extract or duplicate RSI/SMA helpers into `internal/scan` or a tiny
`internal/ta` package if duplication becomes painful; avoid importing anomaly
`Severity` types into scan.

### Example output — table (default)

```text
watchman scan — 2026-06-25  (4 tickers)

TICKER   RANGE   DRAWDOWN   vs SMA200   RSI
PETR4      18%     −22%       −12%        27
VALE3      35%     −10%        −8%        42
ITUB4      52%      −3%        +2%        55
MXRF11     71%      −1%        +5%        61
```

Failure rows (same pattern as glance):

```text
XPTO3      —        —           —         —    No data
```

### Example output — detail

```text
PETR4 @ R$ 38.42

  range      18%   (position in 52-week low–high band)
  drawdown  −22%   (from peak R$ 49.20 on 2026-03-14)
  sma200    −12%   (200-day average R$ 43.60)
  rsi        27    (14-day Wilder)
  volume    1.4×   (vs 20-day average)
```

Parenthetical lines are **factual context** copied from structured fields, not
interpretive advice.

### Example output — JSON (`--json`)

```json
{
  "as_of": "2026-06-25",
  "tickers": [
    {
      "ticker": "PETR4",
      "close": 38.42,
      "readings": {
        "range_pct": 18,
        "drawdown_pct": -22,
        "sma200_pct": -12,
        "rsi": 27,
        "volume_ratio": 1.4
      },
      "meta": {
        "peak_date": "2026-03-14",
        "peak_close": 49.20,
        "sma200": 43.60
      }
    }
  ]
}
```

- Stable field names for skill/script consumption.
- Omit null keys when data unavailable; include `"error": "No data"` for failure rows.
- JSON writes to stdout; table suppressed when `--json` is set (no mixed output).

## CLI surface

### `wm scan [TICKER...]`

- Empty args → wallet tickers (same as `wm run`).
- Empty wallet → message: `No tickers. Add with: wm wallet add PETR4`.
- Flags:
  - `--detail` — single-ticker or all tickers expanded (if one arg, detail that ticker;
    if no args, detail all — same as `wm scan --detail` with wallet).
  - `--json` — machine output; mutually exclusive with table (detail mode still applies
    to JSON shape: one object vs array).

### `wm explain [INDICATOR]`

- `wm explain range` — print `docs/indicators/range.md` to stdout.
- `wm explain --list` — print indicator keys (`range`, `drawdown`, `sma200`, `rsi`, `volume`).
- Unknown indicator → exit 1 with hint to run `--list`.

### Wallet extensions

| Command | Behavior |
|---|---|
| `wm wallet` | Default to `list` (no subcommand). |
| `wm wallet add T1 T2 …` | Add multiple tickers in one call; dedupe, uppercase. |
| `wm wallet clear` | Remove all tickers; require `--yes` flag to confirm. |

Existing `add` (single), `remove`, `list` unchanged.

## Documentation (`docs/indicators/`)

| File | Purpose |
|---|---|
| `README.md` | How to read `wm scan` output; link to each indicator; disclaimer (not advice). |
| `range.md` | Definition, formula, how to read low/mid/high values, limitations. |
| `drawdown.md` | Idem |
| `sma200.md` | Idem |
| `rsi.md` | Idem |
| `volume.md` | Idem |

Tone: factual reference (Wikipedia-style), Portuguese or bilingual TBD at
implementation — **recommend Portuguese** for the primary audience; English summary
optional in README.

Each doc ends with a **"O que não significa"** section to counter over-interpretation.

## Cursor skill (phase 4 — out of repo scope)

Separate artifact (e.g. `.cursor/skills/watchman/SKILL.md` or user-local skill):

1. Run `wm scan --json` or `wm scan TICKER --json`.
2. Load indicator docs for context.
3. Explain readings in Portuguese without buy/sell commands.

Not part of the Go module or CI; documented here for product continuity.

## Phased delivery

| Phase | Scope | Ship criteria |
|---|---|---|
| **1a** | `internal/scan`, `wm scan` table + `--detail` + `--json` | Tests ≥80% coverage; testscript `.txtar`; hermetic httptest |
| **1b** | `docs/indicators/*`, `wm explain` | Docs complete; explain prints embedded content |
| **1c** | Wallet multi-add, clear, default list | testscript wallet cases |
| **2** | History NDJSON append on scan/run; `wm history` | ROADMAP history item |
| **3** | `wm schedule` | ROADMAP schedule item |
| **4** | Cursor skill template | Optional; user-local |

This spec covers **phases 1a–1c** in full detail; phases 2–3 reference existing
ROADMAP intent.

## History (phase 2 — summary)

Append one NDJSON line per `wm scan` and `wm run` execution to
`~/.config/watchman/history.ndjson` (override `WATCHMAN_HISTORY`):

```json
{"ts":"2026-06-25T14:00:00Z","cmd":"scan","results":[…]}
```

`wm history [-n N] [TICKER]` — print last N snapshots, filter by ticker. Enables
"was PETR4 worse last week?" without a DB.

## Data flow & errors

Same failure taxonomy as glance:

- `prices.ErrNoData` → row with `error: "No data"`, excluded from sort or sorted last.
- Other fetch errors → `error: "API error"`.
- Per-indicator insufficient history → omit field; detail view notes it.

Scan never aborts the whole run because one ticker failed.

## Testing

- **Per indicator:** table tests — typical value, edge (flat series, σ=0 volume),
  insufficient bars.
- **Format:** table column alignment; JSON round-trip; `--json` with failures.
- **CLI:** testscript `scan.txtar` with mock prices fixture (reuse run mock patterns).
- **Explain:** `--list`, known indicator, unknown indicator.
- **Wallet:** multi-add, clear without `--yes` fails, clear with `--yes` empties file.
- Coverage floor stays **80%**.

## Migration / breaking changes

- No breaking changes to `wm run` or wallet file format.
- New commands only; ship as **minor** release (e.g. v2.2.0).
- Update `README.md` and `ROADMAP.md` when phase 1a ships.

## Tunable defaults (v1)

- SMA window: **200** trading days (constant; config knob deferred).
- RSI period: **14** (shared with anomaly engine).
- Volume average window: **20** days.
- Range band: full available series (≥200 bars); use all bars in the 1y fetch.
- Table sort: **`range` ascending**.

Config file extension for scan-specific thresholds is **deferred** — v1 uses fixed
constants documented in `docs/indicators/`.
