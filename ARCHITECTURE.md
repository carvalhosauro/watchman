# Architecture

## Overview

Watchman is an Elixir CLI that analyzes Brazilian financial assets daily using AI.
It fetches market data, calls an AI provider with web search, and stores structured results in SQLite.

## Design Patterns

### Strategy + Factory (Providers)

Both market data and AI analysis use the Strategy pattern with a Factory resolver:

```
Provider (behaviour) ← Brapi, Yfinance       (Market)
Provider (behaviour) ← Claude, Gemini, DeepSeek  (AI)
Factory              → reads config, returns module
```

Adding a new provider = implement the behaviour + add to `@provider_map` in Config. Zero pipeline changes.

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
       ──< news_items
       ──< analyses ──> price_snapshots (snapshot_id)

retrospectives (standalone, generated from stored data)
```

5 tables in SQLite. Auto-migrated on first run.

## Pipeline Flow

```
wm run
 ├─ Load active assets from DB
 ├─ Task.async_stream (parallel, max_concurrency from config)
 │   └─ Per asset:
 │       ├─ Market.Factory.provider().fetch(ticker)
 │       │   └─ fallback to secondary provider on failure
 │       ├─ Persist PriceSnapshot
 │       ├─ AI.Factory.provider().analyze(asset, snapshot)
 │       ├─ Persist Analysis + NewsItems
 │       └─ Log result
 └─ Print summary
```

Idempotent: skips assets already analyzed today.

## Module Map

| Module | Responsibility |
|--------|---------------|
| `CLI` | Command dispatch, argument parsing |
| `Config` | TOML + env + keyring config reader |
| `Credentials` | System keyring interface (Linux/macOS) |
| `Pipeline` | Parallel analysis orchestrator |
| `Retro` | Retrospective generation from stored data |
| `Parser` | Claude response → structured analysis + news |
| `Scheduler` | systemd/cron setup and teardown |
| `Setup` | Interactive configuration wizard |
| `Market.Provider` | Behaviour for price fetching |
| `AI.Provider` | Behaviour for AI analysis |

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
- **Credo** for code smells and complexity
- **Dialyxir** for static type analysis

Coverage targets:
- Core modules (Pipeline, Retro, CLI, Parser): 75%+
- Models, Factories, Providers: 100%
- HTTP wrappers, Scheduler, Setup: excluded (I/O-bound)

## CI Pipeline

```
quality: format --check-formatted → compile --warnings-as-errors → credo --strict
test:    mix test --cover
release-gate: stricter checks on PRs to main
```

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| `bin/wm` wrapper, not escript | exqlite NIF can't load from escript zip |
| SQLite, not Postgres | Personal tool, zero setup, single file |
| `Task.async_stream` | Parallel with backpressure, timeout, isolation |
| Portuguese prompts | Brazilian market, PT-BR context improves analysis |
| No GenServer | Run-and-exit suits cron, avoids complexity |
| `retry: :transient` | Handles connection pool exhaustion under parallel load |
| Ignore HTTP wrappers in coverage | Thin wrappers, tested via integration |
