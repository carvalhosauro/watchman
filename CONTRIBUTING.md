# Contributing to watchman

## Dev environment

```bash
git clone https://github.com/carvalhosauro/watchman.git
cd watchman
./bin/setup-hooks    # installs .githooks (pre-commit + commit-msg)
make build           # -> bin/wm
```

Requires Go 1.22+.

## Gates (run before pushing)

```bash
make ci      # gofmt, golangci-lint, coverage (>=70%), build
make test    # go test -race ./...
```

The pre-commit hook auto-formats staged Go files and runs lint + tests; the
commit-msg hook enforces Conventional Commits.

## Commit conventions

[Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add price-anomaly classifier
fix: correct FII ticker parsing
ci: tighten coverage threshold
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.

## Layout

- `cmd/wm/` — binary entry point (`package main`)
- `cmd/` — cobra commands
- `internal/` — packages (`wallet`, `prices`, …). Pure logic is table-tested;
  network and CLI flows are tested via `net/http/httptest` (no live calls).

## PRs

Branch from `main`, keep PRs focused (one feature/fix), ensure `make ci` is green.
