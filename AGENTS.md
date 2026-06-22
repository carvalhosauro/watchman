# AGENTS.md

## Cursor Cloud specific instructions

`watchman` (`wm`) is a single, static **Go CLI** (Go 1.24+) for monitoring B3
stock tickers. There is **no database, server, daemon, or port** — it is a
local binary whose only runtime dependency is an outbound HTTPS call to the
Yahoo Finance chart API. State lives in a plain-text wallet file.

### Build / test / lint / run

Standard targets are in the `Makefile` (run `make help`); the canonical
gate is `make ci` (gofmt + goimports + `golangci-lint` + coverage ≥80% +
build). Key commands: `make build` (-> `bin/wm`), `make test`
(`go test -race ./...`), `make cover`, `make lint`.

The update script installs `golangci-lint` (v2) and `goimports` into
`$(go env GOPATH)/bin`, which is already on `PATH`, so `make lint`/`make ci`
work without extra setup.

### Non-obvious gotchas

- **`make ci` runs `gofmt -w` and `goimports -w` (in-place writes).** Treat it
  as potentially mutating; check `git status` after running it.
- **`golangci-lint` config is schema `version: 2`** (`.golangci.yml`), so a v2
  binary is required — a v1 `golangci-lint` will fail to parse the config.
- **`wm run` hits the real Yahoo Finance API** and needs outbound internet.
  Yahoo rate-limits by client: `wm` sends `User-Agent: watchman/2.0` and gets
  `200`, but a plain `curl` (default UA) typically gets `429`. On a non-200 the
  ticker simply shows `No data` rather than failing the command.
- **The test suite needs no network.** Network/CLI paths are tested in-process
  via `net/http/httptest`; only `make smoke` (`-tags live`) makes live calls.
- **Wallet/config locations are env-overridable**: set `WATCHMAN_WALLET` and
  `WATCHMAN_CONFIG` (e.g. to a `mktemp` file) to avoid touching
  `~/.config/watchman/` when testing. `WATCHMAN_PRICES_URL` can point price
  fetches at a local mock for offline E2E runs.
