# Roadmap

> **Strategic realignment in progress.** From v0.3.0 onwards, watchman owns its
> analytical layer. The AI provider becomes an optional narrative enrichment
> step instead of the engine of the product. See [`docs/REALIGNMENT.md`](docs/REALIGNMENT.md)
> for the full rationale and end-state architecture.

## v0.1.0 — Foundation (done)

- [x] Elixir CLI with `bin/wm` wrapper
- [x] SQLite persistence (5 tables)
- [x] Parallel analysis pipeline (Task.async_stream)
- [x] Market providers: Brapi, Yahoo Finance (Strategy/Factory)
- [x] AI providers: Claude, Gemini, DeepSeek (Strategy/Factory)
- [x] Asset type auto-detection (acao/fii)
- [x] Interactive setup wizard
- [x] System keyring for API keys
- [x] One-line installer
- [x] Show command for stored analyses
- [x] Retrospectives (weekly/monthly)

## v0.2.0 — Automation & Alerts (done)

- [x] File logging with rotation (OTP logger_std_h, 10MB, 7 files)
- [x] Scheduled runs (systemd timer / cron generation)
- [x] Schedule management (status, unschedule)
- [x] Log viewer (`wm logs`, `-f`, `-n`)
- [x] Telegram alerts on actionable recommendations (configurable triggers)
- [x] Discord webhook alerts (alternative or complement to Telegram)
- [x] Rate limiting for free-tier API compliance
- [x] Alert CLI commands (`wm alerts test`, `wm alerts status`)

---

## v0.3.0 — Track 1: Accuracy Tracking (done)

**Goal:** close the feedback loop on past analyses using data already in the DB.
Zero new APIs. Zero new dependencies. Immediate credibility win.

- [x] `analysis_outcomes` table + Ecto migration (hit/miss/pending, lookahead window, evaluated price)
- [x] Outcome closer step inside `wm run`: scan analyses past their lookahead and persist outcomes
- [x] `Watchman.Accuracy` query layer (hit rate per ticker, per provider, overall)
- [x] `wm accuracy` CLI with `--ticker`, `--provider`, `--days`, `--since` flags
- [x] Tabular report formatter
- [x] Tests against in-memory SQLite sandbox

Detailed prep in [`docs/track-1-accuracy.md`](docs/track-1-accuracy.md). Shipped commits: `5ec3b40` → `b4c55ed` (final hardening). See [`CHANGELOG.md`](CHANGELOG.md).

## v0.4.0 — Track 2: Technical Analysis (done)

**Goal:** own deterministic indicators computed from stored `price_snapshots`.
Pure functions. 100% unit-testable. No DB calls, no external APIs.

- [x] `Watchman.Analysis.Technical` module
- [x] SMA, EMA, RSI, z-score, streak, drawdown
- [x] `Watchman.Analysis.Indicators` struct (sma7, sma21, sma50, ema21, rsi14, zscore21, streak, drawdown_from_peak)
- [x] `Technical.indicators/1` convenience aggregator
- [x] Tagged tuple errors on insufficient data — never raise
- [x] Exhaustive ExUnit suite with spreadsheet-validated reference values
- [x] Not yet wired into `Pipeline` — used directly by Track 4

Detailed prep in [`docs/track-2-technical.md`](docs/track-2-technical.md). Shipped commits: `b31cb54` → `daaee56`. See [`CHANGELOG.md`](CHANGELOG.md).

## v0.5.0 — Track 3: News Provider Layer (next)

**Goal:** stop delegating news to the AI provider's web search. Own the audit trail.

- [ ] `Watchman.News.Provider` behaviour (mirrors `Market.Provider` / `AI.Provider`)
- [ ] `Watchman.News.CVM` adapter — fatos relevantes, ITR, material events
- [ ] `Watchman.News.Infomoney` adapter — per-ticker RSS feed
- [ ] `Watchman.News.Factory` with `"cvm" | "infomoney" | "all"` resolution
- [ ] News categories: `:material_fact | :financial_result | :dividend | :other`
- [ ] Migration: `source` and `category` columns on `news_items`
- [ ] Graceful degradation — empty list on provider failure, pipeline continues
- [ ] HTTP layer mocked with `Mox`
- [ ] `SweetXml` dependency for CVM/RSS parsing

Detailed prep in [`docs/track-3-news.md`](docs/track-3-news.md).

## v0.6.0 — Track 4: Signal Classifier + Pipeline Integration

**Goal:** deterministic signal derived from indicators + news, with AI demoted to enrichment.

- [ ] `Watchman.Analysis.Classifier.classify/2` returning `%Signal{level, direction, reasons, confidence}`
- [ ] Rule engine: ordered list of rule structs evaluated in priority order
- [ ] Exhaustive branch-coverage tests (every rule fires and doesn't-fire)
- [ ] `Pipeline` rewrite: parallel news + price fetch, indicators, signal, optional AI enrichment
- [ ] AI prompts updated to receive `%Signal{}` as context (reference, not re-derive)
- [ ] Signal formatter for AI-less mode
- [ ] Outcome closer (Track 1) invoked before writing new analyses

---

## v0.7.0 — Portfolio Intelligence (deferred from previous roadmap)

- [ ] Portfolio tracking (quantity, avg price, P&L per asset)
- [ ] Dividend tracking (yield, ex-dates, payment history)
- [ ] Multi-asset correlation (link causes across assets)
- [ ] Sector grouping and sector-level trends

## v0.8.0 — Data & Export

- [ ] Export analyses to CSV/JSON
- [ ] Custom analysis prompts per asset type
- [ ] Historical price chart in terminal (sparklines)

## v0.9.0 — Experience

- [ ] TUI dashboard (Ratatouille) — prices, history, recommendations, signals
- [ ] i18n (English prompts/output for international users)
- [ ] Docker image for users without Elixir
- [ ] Plugin system for custom providers

## Future / Maybe

- [ ] Phoenix LiveView web dashboard
- [ ] Shared analysis feeds (community insights)
- [ ] Backtesting engine (replay rule engine + AI on historical price series)
- [ ] Options and crypto asset support
- [ ] Integration with brokerage APIs (read-only, position sync)
