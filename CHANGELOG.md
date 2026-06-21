# Changelog


### Bug Fixes

- Check Fprintln error for lint

- Bound price/news fetches with a 10s client timeout


### Documentation

- Add git-cliff changelog config

- Mark plan Tasks 1-11 complete (ralph)

- Rewrite README and CONTRIBUTING for Go

- README + CHANGELOG for Phase A glance


### Features

- List held tickers

- Parse Yahoo close history

- Add/remove + wm wallet commands + flow test

- Fetch close history over HTTP + flow test

- Z-score of latest move

- Deterministic ignore/LOOK rule

- Parse CVM feed + per-ticker freshness

- Fetch CVM feed over HTTP + flow test

- Price-only run glance via wm run

- Env URL override seam (WATCHMAN_PRICES_URL/NEWS_URL)


### Refactor

- Move entrypoint to cmd/wm, build binary to bin/wm


### Tests

- Black-box wm suite + mock-driven run + live smoke


### Tooling

- Reset to Go static-binary CLI for v2

- Add Makefile dev targets

- Add golangci-lint v2 config

- Add coverage threshold gate

- Add lefthook pre-commit + conventional-commit hook

- GoReleaser cross-platform release + CI gates

- Remove Elixir leftovers (installers, stale docs, completions, lefthook)

- Consolidate git hooks on .githooks, coverage output to test/

- Update .gitignore to streamline ignored files and add specific test database patterns

- Exclude misspell on test fixtures (Portuguese CVM text)

- Raise coverage floor to 80


### Documentation

- Add Track 5 (daemon paradigm shift, v0.7.0)

- Add Track 4 (classifier + pipeline integration) prep doc

- Mark Track 4 (classifier + pipeline) shipped at v0.6.0


### Features

- Add %Watchman.Analysis.Signal{} struct

- Add %Watchman.Analysis.Classifier.Rule{} struct

- Add signal-based dispatcher entry point

- Accept Signal as enrichment context (analyze/4)

- Add signal columns

- Add Classifier engine + SignalFormatter

- Wire Classifier + Signal columns; AI demoted to enrichment


### Tooling

- Bump version to 0.6.0


### Bug Fixes

- Change observed_snapshot_id on_delete to :restrict


### Documentation

- Refresh README heads-up for v0.3.0 + v0.4.0 shipped

- Clarify per-function length guards + ema seeding

- Add Track 3 (news provider) prep doc

- Expand to 4 adapters covering 8 news sources

- Mark Track 3 (news provider layer) shipped at v0.5.0


### Features

- Add source whitelist + category column to news_items

- Add Provider behaviour, TickerAliases, sweet_xml dep

- Add Watchman.News.CVM adapter

- Add Watchman.News.B3 adapter

- Add Watchman.News.Infomoney adapter

- Add Watchman.News.RssFeed adapter

- Add News.Factory + Config readers


### Refactor

- Extract shared prices/2 helper

- Inject config + single-pass stats + clearer comparisons


### Tests

- Add boundary tests + convention-lock comments

- Register Watchman.News.MockProvider for Mox


### Tooling

- Bump version to 0.5.0


### Documentation

- Add Track 2 (technical analysis) prep doc

- Mark Track 2 (technical analysis) shipped at v0.4.0


### Features

- Add %Watchman.Analysis.Indicators{} struct

- Add Technical module skeleton + sma/2

- Add Technical.ema/2 (SMA-seeded)

- Add Technical.rsi/2 with Wilder smoothing

- Add Technical.zscore/2 with sample stddev

- Add Technical.streak/1

- Add Technical.drawdown/2

- Add Technical.indicators/1 aggregator


### Tooling

- Bump version to 0.4.0


### Bug Fixes

- Use runtime project dir instead of hardcoded install path

- Group store_keys/2 clauses to resolve compilation warning

- Use file cache instead of app startup

- Resolve cache compile-time bug and add analyses unique index

- Correct cost calculation, error handling, and concurrency defaults

- Validate scheduler input, mask secrets, and use calendar month for retro

- Parser text block selection, remove System.halt, and improve ETF detection

- Fix 4 shell completion bugs and add update command

- Replace _wm call with compdef registration

- Remove unused default args in test helpers

- Call Cache.update_retro_ids after retro generation

- Default MIX_ENV=prod in bin/wm wrapper

- Suppress debug logs in prod environment

- Default MIX_ENV=prod in bin/wm wrapper

- Add unique index on (asset_id, date(analyzed_at))

- Safer update, fix cmd_logs, correct defaults, escape TOML

- Handle :io.get_password unsupported terminals, fix test dates

- Remove auto version bump from deploy-pr workflow

- Correct casing of Watchman.AI.Deepseek provider module name

- Harden closer against scale, zero-price, and unknown inputs


### Documentation

- Add README, license, and test helper

- Add project roadmap (v0.1 through v0.5)

- Update roadmap with completed v0.2 items

- Add shell completions, scheduling, and logs to README

- Add CONTRIBUTING.md, issue/PR templates, document wm update

- Realign roadmap and architecture around owned analytical layer

- Mark Track 1 (accuracy tracking) shipped at v0.3.0


### Features

- Add SQLite persistence layer with auto-migration

- Add Ecto schemas for all domain entities

- Add CLI entry point and TOML config support

- Add price data providers with strategy pattern

- Add Claude, Gemini, and DeepSeek analysis providers

- Add parallel analysis and retrospective generation

- Add show command to display stored analyses

- Add short flag aliases for retro and show

- Auto-detect asset type and add retry for AI requests

- Add interactive setup wizard

- Add system keyring support for API key storage

- Add one-line installer and uninstaller scripts

- Add file logging with rotation

- Add wm schedule for automated daily runs

- Add unschedule, schedule status, and logs commands

- Add list and show subcommands for retrospectives

- Add shell completions for bash and zsh

- Enhance status with last run and analysis info

- Add comprehensive test suite with Mox

- Add GitHub Actions CI pipeline and fix formatting

- Boost test coverage to 72% and add code analysis tools

- Add wm update command to pull latest from GitHub

- Add mix aliases for quality, lint, and ci workflows

- Add pre-commit hook for auto-formatting

- Add Brapi free-tier usage tracking and warnings

- Add Telegram and Discord notification system

- Add alerts subcommands to bash/zsh completion

- Implement alert system and update watchman provider integration tests

- Implement database migrations and update model tests for v0.2.0 alerts

- Add analysis_outcomes table and AnalysisOutcome model

- Add Accuracy.classify_outcome/3 pure classifier

- Add [accuracy] config keys (lookahead_days, drop_threshold_pct)

- Add Watchman.Calendar.add_business_days/2

- Add Accuracy.close_pending_outcomes/0 idempotent closer

- Wire Accuracy closer into Pipeline.run/0

- Add Accuracy.report/1 query layer

- Add wm accuracy CLI

- Document wm accuracy in README and shell completions

- Bump version to 0.3.0


### Refactor

- Resolve credo strict issues across codebase

- Resolve all credo strict issues to zero

- Restore moduledocs and resolve credo strict issues

- Extract shared prompts and utilities into Watchman.AI.Shared


### Tooling

- Initialize Elixir project with dependencies

- Update repository URLs from placeholder to carvalhosauro/watchman

- Run setup-hooks automatically via mix setup

- Add GitHub Actions CI, git-cliff changelog, release workflow

- Add deploy-to-main PR and auto-tag release workflows

- Add deploy-to-main PR and auto-tag release workflows

- Auto-commit CHANGELOG.md on tag release

- Use PR instead of direct push for CHANGELOG.md

- Trigger auto-tagging on push to main instead of PR closure


### Style

- Format pipeline, config, setup, scheduler, and retro

- Use sigil for @doc with multiple quotes (Credo fix)

- Alias nested modules, fix test for unique date index

- Format escape_toml_string line break

- Fix all credo suggestions

- Format dispatcher.ex

