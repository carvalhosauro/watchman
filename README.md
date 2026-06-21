# watchman

[![Go Reference](https://pkg.go.dev/badge/github.com/carvalhosauro/watchman.svg)](https://pkg.go.dev/github.com/carvalhosauro/watchman)
[![CI](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml/badge.svg)](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/carvalhosauro/watchman)](https://github.com/carvalhosauro/watchman/releases/latest)
[![License](https://img.shields.io/github/license/carvalhosauro/watchman)](./LICENSE)
[![Go Version](https://img.shields.io/github/go-mod/go-version/carvalhosauro/watchman)](./go.mod)

> Is this market move noise, or worth a look? A single static CLI that watches the B3 assets you hold and, in one screen, tells you which to **ignore** and which to **LOOK** at.

`wm` fetches recent price history and the CVM material-fact feed, then applies one deterministic rule per ticker. No database, no account, no advice — just a glance you can read in a breath.

## The rule

A ticker is flagged **LOOK** when **either**:

- its latest daily move is **abnormal** — a z-score of |Z| ≥ 2 against the last ~30 days of returns, **or**
- there is **fresh material news** (a CVM fato relevante) for it **today**.

Otherwise it's **ignore** (noise). The reason is always printed, so you can audit why it fired.

```text
watchman — 2026-06-21
  ⚠ LOOK   PETR4    moved -6.1% (-2.8σ/30d) + fresh material news
    ignore MXRF11   quiet (0.6% (1.0σ/30d))
```

## Install

Download a prebuilt static binary from [Releases](https://github.com/carvalhosauro/watchman/releases) (`wm_<os>_<arch>.tar.gz`, linux/darwin × amd64/arm64), extract, and put `wm` on your `PATH`.

Or build from source (Go 1.24+):

```bash
go install github.com/carvalhosauro/watchman/cmd/wm@latest
# or, in a clone:
make build        # -> bin/wm  (CGO_ENABLED=0, no runtime deps)
```

## Usage

```bash
wm wallet add PETR4      # track an asset (dedupes, uppercases)
wm wallet add MXRF11
wm wallet list           # show tracked tickers
wm wallet remove PETR4

wm run                   # the noise/look glance for everything you hold
```

The wallet is a plain text file at `~/.config/watchman/wallet` (one ticker per line; `#` comments and blank lines ignored). Override the location with `$WATCHMAN_WALLET`.

Shell completion is built in:

```bash
wm completion bash       # also: zsh, fish, powershell
```

## What it doesn't do

- No buy/sell advice or price targets — it points, it doesn't recommend.
- No database, no daemon, no background alerts or schedule (yet).
- No history log, weighting, or per-ticker tuning (yet).
- News is matched by ticker substring on the CVM feed; aliases and a live RSS feed URL are roadmap items. Until then `wm run` degrades gracefully to a price-only glance.

These are deliberate cuts for the value-core MVP. History, schedule, and self-update are the next phase.

## Develop

```bash
.githooks/setup-hooks    # point git at .githooks/ (pre-commit gates + conventional-commit msg)
make test                # go test -race ./...
make cover               # coverage gate (floor 80%)
make ci                  # gofmt + golangci-lint + coverage + build — the full local gate
```

Every package is tested. Network and CLI paths are tested via `net/http/httptest` (the `prices.BaseURL`, `news.FeedURL`, and `$WATCHMAN_WALLET` seams keep the whole flow injectable) — no live calls in the test suite.

[License GPL-2.0-only](LICENSE)
