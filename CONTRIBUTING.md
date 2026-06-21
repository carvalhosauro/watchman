# Contributing to watchman

## Dev environment

```bash
git clone https://github.com/carvalhosauro/watchman.git
cd watchman
.githooks/setup-hooks  # installs the pre-commit + commit-msg hooks
make build             # -> bin/wm
make help              # list all targets
```

Requires Go 1.24+.

## Gates (run before pushing)

```bash
make ci      # gofmt, golangci-lint, coverage (>=80%), build
make test    # go test -race ./...  (unit + cobra + testscript black-box)
make smoke   # optional: live network smoke against real Yahoo/CVM
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
