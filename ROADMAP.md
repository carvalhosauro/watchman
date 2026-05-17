# Roadmap

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

## v0.2.0 — Automation & Alerts

- [x] File logging with rotation (OTP logger_std_h, 10MB, 7 files)
- [x] Scheduled runs (systemd timer / cron generation)
- [x] Schedule management (status, unschedule)
- [x] Log viewer (`wm logs`, `-f`, `-n`)
- [ ] Telegram alerts on "investigar" or "vender" recommendations
- [ ] Discord webhook alerts (alternative to Telegram)
- [ ] Rate limiting for free-tier API compliance

## v0.3.0 — Portfolio Intelligence

- [ ] Portfolio tracking (quantity, avg price, P&L per asset)
- [ ] Dividend tracking (yield, ex-dates, payment history)
- [ ] Multi-asset correlation (link causes across assets)
- [ ] Benchmark mode (compare AI recommendation vs actual price after N days)
- [ ] Confidence scoring and accuracy tracking over time

## v0.4.0 — Data & Export

- [ ] Export analyses to CSV/JSON
- [ ] Sector grouping and sector-level trends
- [ ] Custom analysis prompts per asset type
- [ ] Historical price chart in terminal (sparklines)

## v0.5.0 — Experience

- [ ] TUI dashboard (Ratatouille) — prices, history, recommendations
- [ ] i18n (English prompts/output for international users)
- [ ] Docker image for users without Elixir
- [ ] Plugin system for custom providers

## Future / Maybe

- [ ] Phoenix LiveView web dashboard
- [ ] Shared analysis feeds (community insights)
- [ ] Backtesting engine (apply past recommendations to historical data)
- [ ] Options and crypto asset support
- [ ] Integration with brokerage APIs (read-only, position sync)
