# watchman

[![Go Reference](https://pkg.go.dev/badge/github.com/carvalhosauro/watchman.svg)](https://pkg.go.dev/github.com/carvalhosauro/watchman)
[![CI](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml/badge.svg)](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/carvalhosauro/watchman)](https://github.com/carvalhosauro/watchman/releases/latest)
[![License](https://img.shields.io/github/license/carvalhosauro/watchman)](./LICENSE)
[![Go Version](https://img.shields.io/github/go-mod/go-version/carvalhosauro/watchman)](./go.mod)

> Is this market move noise, or worth a look? A single static CLI that watches the B3 assets you hold and, in one screen, tells you which to **ignore** and which to **LOOK** at.

`wm` fetches ~1 year of daily prices and runs a deterministic, multi-signal anomaly engine per ticker. No database, no account, no advice, no AI — just a glance you can read in a breath, with every call explained.

## The engine

Each held ticker is scored by five independent, pure signals — each a different lens on "is something unusual happening?":

| Signal | What it catches | watch | LOOK |
|---|---|---|---|
| **z-score** | today's move vs its own recent volatility | \|z\| ≥ 2 | \|z\| ≥ 3 |
| **RSI(14)** | momentum exhaustion (overbought/oversold) | >70 / <30 | >80 / <20 |
| **drawdown** | cumulative decline from the recent peak | ≤ −10% | ≤ −20% |
| **52-week** | proximity to / break of the 1-year high or low | within 3% | new high/low |
| **volume** | participation vs the 20-day average | ≥ 2× | ≥ 3× |

A ticker's **severity** is the worst of its signals — **calm**, **watch**, or **⚠ LOOK** — and the number of signals firing breaks ties. `wm run` ranks your holdings worst-first and prints the reason, so you can audit exactly why each fired. No editorial weights; thresholds are yours to tune.

```text
watchman — 2026-06-22
  ⚠ LOOK PETR4    RSI 27 · -22% vs peak
  watch  ITUB4    -19% vs peak
  watch  VALE3    -10% vs peak
    —    XPTO3    No data
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

wm run                   # ranked glance over everything you hold
wm run PETR4 VALE3       # limit to specific tickers (need not be in the wallet)
wm run --look            # show only watch/LOOK rows (hide calm)
wm run --detail PETR4    # show every signal's value, calm or not

wm scan                   # neutral technical readout (RANGE, DRAWDOWN, vs SMA200, RSI)
wm scan SCAN1             # single ticker
wm scan --detail SCAN1    # expanded factual context
wm scan --json            # machine-readable output

wm explain range          # reference doc for an indicator (range, drawdown, …)
wm explain --list         # list indicator keys
```

The wallet is a plain text file at `~/.config/watchman/wallet` (one ticker per line; `#` comments and blank lines ignored). Override the location with `$WATCHMAN_WALLET`.

### Tuning thresholds

Every threshold is configurable via `~/.config/watchman/config.toml` (override with `$WATCHMAN_CONFIG`); any missing key keeps its built-in default. See [`docs/config.example.toml`](docs/config.example.toml).

```toml
[zscore]
look = 4.0   # only flag LOOK at |z| ≥ 4
```

Shell completion is built in:

```bash
wm completion bash       # also: zsh, fish, powershell
```

## What it doesn't do

- No buy/sell advice or price targets — it points, it doesn't recommend. Technical signals are descriptive, not predictive; `wm scan` shows numbers only, not advice.
- No fundamentals, valuation, or screening — it watches what you hold, it doesn't pick.
- No news/material-fact signal (dropped — sourcing didn't justify the value).
- No database, no daemon, no background alerts or schedule (yet).
- No AI, no editorial weighting — severity is the worst signal, ties broken by count.

History, schedule, and self-update are the next phases — see [ROADMAP.md](ROADMAP.md).

## Develop

```bash
.githooks/setup-hooks    # point git at .githooks/ (pre-commit gates + conventional-commit msg)
make test                # go test -race ./...
make cover               # coverage gate (floor 80%)
make ci                  # gofmt + golangci-lint + coverage + build — the full local gate
```

Every package is tested. Network and CLI paths are tested via `net/http/httptest` (the `prices.BaseURL`, `news.FeedURL`, and `$WATCHMAN_WALLET` seams keep the whole flow injectable) — no live calls in the test suite.

[License GPL-2.0-only](LICENSE)
