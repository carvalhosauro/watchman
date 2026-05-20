# Architecture

## Overview

Watchman is an Elixir CLI that analyzes Brazilian financial assets daily.
It fetches market data and news, computes deterministic technical indicators
and a classified signal, optionally enriches the result with an AI narrative,
and stores everything in SQLite.

From v0.3.0 onwards (the [strategic realignment](docs/REALIGNMENT.md)),
the analytical layer lives in this codebase. The AI provider is an
enrichment step, not the engine.

## Design Patterns

### Strategy + Factory (Providers)

Market data, news, AI analysis, and alert delivery all use the Strategy
pattern with a Factory resolver:

```
Provider (behaviour) ← Brapi, Yfinance                        (Market)
Provider (behaviour) ← CVM, Infomoney                          (News)        [v0.5.0]
Provider (behaviour) ← Claude, Gemini, DeepSeek                (AI, optional)
Provider (behaviour) ← Telegram, Discord                       (Alerts)
Factory              → reads config, returns module(s)
```

Adding a new provider = implement the behaviour + add to `@*_map` in `Config`.
Zero pipeline changes.

### Pure analytical core

`Watchman.Analysis.Technical` and `Watchman.Analysis.Classifier` are pure
function modules. No DB calls. No HTTP. No process communication. Tagged-tuple
errors on bad input — they never raise. Everything is unit-testable with
hardcoded fixtures.

### Run-and-exit model

No GenServer daemon. CLI starts app, does work, exits. Cron/systemd-friendly.

## Config Priority

```
Environment variable → System keyring → TOML file → Default value
```

- Keyring: `secret-tool` (Linux), `security` (macOS)
- TOML: `~/.config/watchman/config.toml` (chmod 600)
- DB: `~/.local/share/watchman/watchman.db`
- Logs: `~/.local/share/watchman/logs/watchman.log`

## Data Model

```
assets ──< price_snapshots
       ──< news_items                       (source, category — v0.5.0)
       ──< analyses ──> price_snapshots (snapshot_id)
       ──< analysis_outcomes ──> analyses   (v0.3.0)

retrospectives (standalone, generated from stored data)
```

6 tables in SQLite (5 today + `analysis_outcomes` in v0.3.0). Auto-migrated on
first run.

`analysis_outcomes` closes the feedback loop: each analysis is evaluated against
the price observed `N` business days later (default 5) and tagged hit/miss.

## Pipeline Flow

```
wm run
 ├─ Close pending analysis outcomes past their lookahead window   (Track 1)
 ├─ Brapi free-tier usage warning
 ├─ Load active assets from DB
 ├─ Task.async_stream (parallel, max_concurrency from config)
 │   └─ Per asset:
 │       ├─ Market.Factory.provider().fetch(ticker)
 │       │   └─ fallback to secondary provider on failure
 │       ├─ News.Factory.provider().fetch(ticker)                  (Track 3)
 │       │   └─ tolerated to fail — empty list, pipeline continues
 │       ├─ Load last N price_snapshots from DB                    (Track 2)
 │       ├─ Persist new PriceSnapshot
 │       ├─ Technical.indicators(snapshots) → %Indicators{}        (Track 2)
 │       ├─ Classifier.classify(indicators, news) → %Signal{}      (Track 4)
 │       ├─ If AI configured:
 │       │     AI.Factory.provider().analyze(asset, snapshot,
 │       │                                   indicators, signal, news)
 │       │   else:
 │       │     format signal directly
 │       ├─ Persist Analysis + NewsItems
 │       ├─ Maybe dispatch alerts (Telegram / Discord)
 │       └─ Log result
 └─ Print summary
```

Idempotent: skips assets already analyzed today.

The AI prompt (when enabled) receives `%Signal{}` as context — it explains and
enriches the deterministic classification rather than re-deriving it.

## Module Map

| Module | Responsibility | Status |
|--------|---------------|--------|
| `CLI` | Command dispatch, argument parsing | shipped |
| `Config` | TOML + env + keyring config reader | shipped |
| `Credentials` | System keyring interface (Linux/macOS) | shipped |
| `Pipeline` | Parallel analysis orchestrator | rewrite in Track 4 |
| `Retro` | Retrospective generation from stored data | shipped |
| `Parser` | AI response → structured analysis + news | shipped |
| `Scheduler` | systemd/cron setup and teardown | shipped |
| `Setup` | Interactive configuration wizard | shipped |
| `Market.Provider` | Behaviour for price fetching | shipped |
| `Alerts.Provider` | Behaviour for alert delivery | shipped |
| `Accuracy` | Outcome closer + hit-rate queries | **Track 1 — v0.3.0** |
| `Analysis.Technical` | Pure indicator functions (SMA, EMA, RSI, …) | Track 2 — v0.4.0 |
| `Analysis.Indicators` | Indicator result struct | Track 2 — v0.4.0 |
| `News.Provider` | Behaviour for news fetching | Track 3 — v0.5.0 |
| `News.CVM` / `News.Infomoney` | News adapters | Track 3 — v0.5.0 |
| `Analysis.Classifier` | Rule engine → `%Signal{}` | Track 4 — v0.6.0 |
| `AI.Provider` | Behaviour for AI enrichment (now optional) | shipped, signature change in Track 4 |

## Branching

```
main (production) ← PR ← dev (staging) ← PR ← feat/*, fix/*, refac/*
```

- Feature branches from `dev`
- PRs to `dev`: CI runs (format, compile, test)
- PRs to `main`: CI + release gate
- Conventional Commits

## Testing

- **Mox** for provider mocking (behaviours already exist)
- **Ecto.Adapters.SQL.Sandbox** for DB isolation
- **ExUnit.CaptureIO** for CLI output assertions
- **Credo** `--strict` enforced on all new files
- **Dialyxir** for static type analysis

Coverage targets:
- Pure analytical modules (`Analysis.Technical`, `Analysis.Classifier`): **100%**
- Core modules (Pipeline, Retro, CLI, Parser, Accuracy): 75%+
- Models, Factories, Provider behaviours: 100%
- News/Market/AI HTTP adapters: mocked happy path + timeout + malformed response
- Scheduler, Setup: excluded (I/O-bound)

## CI Pipeline

```
quality: format --check-formatted → compile --warnings-as-errors → credo --strict
test:    mix test --cover
release-gate: stricter checks on PRs to main
```

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Own the analytical layer (v0.3.0+) | AI provider previously did all intellectually valuable work — see [REALIGNMENT.md](docs/REALIGNMENT.md) |
| Deterministic classifier as primary signal | Auditable, testable, runs without paid APIs, gives AI a fixed point of reference |
| AI as optional enrichment | Users without API keys still get a useful signal; AI cost becomes opt-in |
| Store outcomes, don't recompute | Lookahead-based hit rate must be persisted to avoid recomputing on every query |
| CVM as primary news source | Official, free, regulatory-grade — material facts are the highest-signal news category |
| `bin/wm` wrapper, not escript | exqlite NIF can't load from escript zip |
| SQLite, not Postgres | Personal tool, zero setup, single file |
| `Task.async_stream` | Parallel with backpressure, timeout, isolation |
| Portuguese user-facing strings | Brazilian market, PT-BR context improves analysis and UX |
| No GenServer | Run-and-exit suits cron, avoids complexity |
| `retry: :transient` | Handles connection pool exhaustion under parallel load |
| Ignore HTTP wrappers in coverage | Thin wrappers, tested via integration |
