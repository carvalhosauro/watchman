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

## v0.5.0 — Track 3: News Provider Layer (done)

**Goal:** stop delegating news to the AI provider's web search. Own the audit trail.

- [x] `Watchman.News.Provider` behaviour (mirrors `Market.Provider` / `AI.Provider`)
- [x] `Watchman.News.CVM` adapter — fatos relevantes, ITR, material events
- [x] `Watchman.News.Infomoney` adapter — per-ticker RSS feed
- [x] `Watchman.News.B3` adapter — corporate actions (dividend / split / rights)
- [x] `Watchman.News.RssFeed` adapter — 5 outlets via config (Valor, Money Times, InvestNews, Suno, Brazil Journal)
- [x] `Watchman.News.TickerAliases` lookup for the RSS ticker filter
- [x] `Watchman.News.Factory` with `"cvm" | "infomoney" | "b3" | "rss" | "all" | "<csv>"` resolution
- [x] News categories: `:material_fact | :financial_result | :dividend | :other`
- [x] Migration: `source` (whitelisted) and `category` columns on `news_items`
- [x] Graceful degradation — single feed failure logged + skipped, pipeline continues
- [x] Mox-mocked Provider behaviour; pure parse_response fixtures per adapter
- [x] `sweet_xml` dependency for CVM/RSS parsing

Detailed prep in [`docs/track-3-news.md`](docs/track-3-news.md). Shipped commits: `708d4e5` → `89e5100`. See [`CHANGELOG.md`](CHANGELOG.md).

## v0.6.0 — Track 4: Signal Classifier + Pipeline Integration (next)

**Goal:** deterministic signal derived from indicators + news, with AI demoted to enrichment.

- [ ] `Watchman.Analysis.Classifier.classify/2` returning `%Signal{level, direction, reasons, confidence}`
- [ ] Rule engine: ordered list of rule structs evaluated in priority order
- [ ] Exhaustive branch-coverage tests (every rule fires and doesn't-fire)
- [ ] `Pipeline` rewrite: parallel news + price fetch, indicators, signal, optional AI enrichment
- [ ] AI prompts updated to receive `%Signal{}` as context (reference, not re-derive)
- [ ] Signal formatter for AI-less mode
- [ ] Outcome closer (Track 1) invoked before writing new analyses

Detailed prep in [`docs/track-4-classifier.md`](docs/track-4-classifier.md).

---

## v0.7.0 — Track 5: Daemon paradigm shift

> **Breaking architectural change.** The current `wm run` invocation
> driven by cron / systemd timer is replaced by a long-lived OTP
> daemon that owns all ingestion + analysis. The CLI becomes
> read-only against the daemon's database. **`wm run` is removed.**

**Goal:** stop stacking cron jobs as the number of news/price sources
grows. One supervised process owns every cadence with shared
rate-limit budget and pre-persistence dedup.

- [ ] `Watchman.Daemon.Supervisor` OTP supervision tree
- [ ] Per-source schedulers (`Daemon.NewsScheduler`, `Daemon.PriceScheduler`, `Daemon.AnalysisScheduler`, `Daemon.OutcomeCloser`)
- [ ] `Watchman.Daemon.RateLimiter` — shared Brapi free-tier budget
- [ ] `Watchman.Daemon.Interval` helper (`"15m" | "1h" | "1d"`)
- [ ] `[daemon]` TOML section with per-source intervals
- [ ] SQLite WAL mode at Repo boot (one writer + many readers)
- [ ] `wm daemon start | stop | status | restart` CLI commands
- [ ] systemd user-unit installer (`~/.config/systemd/user/wm-daemon.service`)
- [ ] daemon-status.json + graceful shutdown (drain in-flight Pipeline runs)
- [ ] **Remove `wm run`** — replace with removal message
- [ ] **Remove `wm schedule` / `wm unschedule`** — daemon owns scheduling
- [ ] `wm news TICKER [--since DATE] [--source X]` — read-only news listing
- [ ] `wm impact TICKER [--days N]` — recent news + price reaction window
- [ ] One-time migration message in `wm update` for cron users
- [ ] Documentation update flipping the "Key Decisions" pillar

After v0.7.0, the CLI keeps only read-only commands plus the
daemon-control subset: `setup`, `assets`, `list`, `remove`, `show`,
`retro`, `accuracy`, `news`, `impact`, `logs`, `daemon`,
`completions`, `update`. Ingestion is invisible to the user.

Detailed prep in [`docs/track-5-daemon.md`](docs/track-5-daemon.md).

---

## v0.8.0 — Portfolio Intelligence

- [ ] Portfolio tracking (quantity, avg price, P&L per asset)
- [ ] Dividend tracking (yield, ex-dates, payment history)
- [ ] Multi-asset correlation (link causes across assets)
- [ ] Sector grouping and sector-level trends

## v0.9.0 — Data & Export

- [ ] Export analyses to CSV/JSON
- [ ] Custom analysis prompts per asset type
- [ ] Historical price chart in terminal (sparklines)

## v0.10.0 — Experience

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
