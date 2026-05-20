# Changelog

All notable changes to this project will be documented in this file.

## [0.2.1] - 2026-05-18

### Bug Fixes

- Correct casing of Watchman.AI.Deepseek provider module name

### CI/CD

- **release:** Auto-commit CHANGELOG.md on tag release
- **release:** Use PR instead of direct push for CHANGELOG.md
- Trigger auto-tagging on push to main instead of PR closure

### Features

- Implement database migrations and update model tests for v0.2.0 alerts

## [0.2.0] - 2026-05-18

### Bug Fixes

- **scheduler:** Use runtime project dir instead of hardcoded install path
- Group store_keys/2 clauses to resolve compilation warning
- **completions:** Use file cache instead of app startup
- Resolve cache compile-time bug and add analyses unique index
- Correct cost calculation, error handling, and concurrency defaults
- Validate scheduler input, mask secrets, and use calendar month for retro
- Parser text block selection, remove System.halt, and improve ETF detection
- **completions:** Fix 4 shell completion bugs and add update command
- **completions:** Replace _wm call with compdef registration
- **test:** Remove unused default args in test helpers
- **completions:** Call Cache.update_retro_ids after retro generation
- **cli:** Default MIX_ENV=prod in bin/wm wrapper
- **config:** Suppress debug logs in prod environment
- **cli:** Default MIX_ENV=prod in bin/wm wrapper
- **db:** Add unique index on (asset_id, date(analyzed_at))
- **cli,config:** Safer update, fix cmd_logs, correct defaults, escape TOML
- **setup:** Handle :io.get_password unsupported terminals, fix test dates
- **ci:** Remove auto version bump from deploy-pr workflow

### CI/CD

- Add GitHub Actions CI, git-cliff changelog, release workflow
- Add deploy-to-main PR and auto-tag release workflows
- Add deploy-to-main PR and auto-tag release workflows

### Documentation

- Add README, license, and test helper
- Add project roadmap (v0.1 through v0.5)
- Update roadmap with completed v0.2 items
- Add shell completions, scheduling, and logs to README
- Add CONTRIBUTING.md, issue/PR templates, document wm update

### Features

- **db:** Add SQLite persistence layer with auto-migration
- **models:** Add Ecto schemas for all domain entities
- **cli:** Add CLI entry point and TOML config support
- **market:** Add price data providers with strategy pattern
- **ai:** Add Claude, Gemini, and DeepSeek analysis providers
- **pipeline:** Add parallel analysis and retrospective generation
- **cli:** Add show command to display stored analyses
- **cli:** Add short flag aliases for retro and show
- **cli:** Auto-detect asset type and add retry for AI requests
- **cli:** Add interactive setup wizard
- **security:** Add system keyring support for API key storage
- **install:** Add one-line installer and uninstaller scripts
- **logging:** Add file logging with rotation
- **scheduler:** Add wm schedule for automated daily runs
- **cli:** Add unschedule, schedule status, and logs commands
- **retro:** Add list and show subcommands for retrospectives
- **ux:** Add shell completions for bash and zsh
- **scheduler:** Enhance status with last run and analysis info
- **test:** Add comprehensive test suite with Mox
- **ci:** Add GitHub Actions CI pipeline and fix formatting
- **quality:** Boost test coverage to 72% and add code analysis tools
- **cli:** Add wm update command to pull latest from GitHub
- **dx:** Add mix aliases for quality, lint, and ci workflows
- **dx:** Add pre-commit hook for auto-formatting
- **market:** Add Brapi free-tier usage tracking and warnings
- **alerts:** Add Telegram and Discord notification system
- **completions:** Add alerts subcommands to bash/zsh completion
- Implement alert system and update watchman provider integration tests

### Miscellaneous

- Initialize Elixir project with dependencies
- Update repository URLs from placeholder to carvalhosauro/watchman
- Run setup-hooks automatically via mix setup

### Refactoring

- Resolve credo strict issues across codebase
- Resolve all credo strict issues to zero
- Restore moduledocs and resolve credo strict issues
- **ai:** Extract shared prompts and utilities into Watchman.AI.Shared

### Styling

- Format pipeline, config, setup, scheduler, and retro
- **ai:** Use sigil for @doc with multiple quotes (Credo fix)
- **market:** Alias nested modules, fix test for unique date index
- **setup:** Format escape_toml_string line break
- **alerts:** Fix all credo suggestions
- Format dispatcher.ex

