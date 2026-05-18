# Contributing to watchman

Thanks for your interest in contributing. Here's everything you need to get started.

## Setting up the dev environment

```bash
git clone https://github.com/carvalhosauro/watchman.git
cd watchman
mix setup
```

`mix setup` installs dependencies, compiles the project, and sets up the pre-commit hook.

## Running tests

```bash
mix test
```

## Code style

The project uses `mix format`. A pre-commit hook enforces formatting automatically — if it fails, run:

```bash
mix format
```

and re-stage the files before committing.

## Commit conventions

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for new market provider
fix: correct price parsing for FII tickers
refactor: extract analysis logic into separate module
docs: update README with wm update command
chore: bump dependencies
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`.

## Language conventions

- **Project code**: English (module names, function names, variable names, comments)
- **User-facing strings**: Portuguese (pt-BR) — messages printed to the terminal, error descriptions, wizard prompts

## PR process

1. Fork the repository
2. Create a branch from `dev`: `git checkout -b feat/your-feature dev`
3. Make your changes
4. Run `mix test` and `mix format --check-formatted`
5. Open a PR against the `dev` branch

Please keep PRs focused. One feature or fix per PR makes review faster.

## What we welcome

- Bug fixes
- New market data providers (e.g., alternative APIs for Brazilian assets)
- New AI provider integrations
- Documentation improvements
- Translations (user-facing strings are in pt-BR; other locales are welcome)
- Test coverage improvements

## Questions

Open an issue or start a discussion on GitHub.
