# watchman

> Is this market move noise, or worth a look? A local CLI that watches your B3 assets.

**Status:** v2 rewrite in Go (was Elixir) — work in progress. See
[`docs/superpowers/plans/2026-06-20-watchman-v2-noise-glance.md`](docs/superpowers/plans/2026-06-20-watchman-v2-noise-glance.md).

## Build

```bash
make build        # -> bin/wm  (static binary, no runtime deps)
```

Requires Go 1.22+.

## Usage (current)

```bash
wm wallet add PETR4      # track an asset
wm wallet add MXRF11
wm wallet list           # show tracked tickers
wm wallet remove PETR4
wm completion bash       # shell completion (also: zsh, fish, powershell)
```

Wallet lives at `~/.config/watchman/wallet` (override with `$WATCHMAN_WALLET`).
`wm run` — the noise/look glance — arrives with Phase A (Task 14).

## Develop

```bash
./bin/setup-hooks    # install git hooks (.githooks/)
make ci              # gofmt + golangci-lint + coverage + build
make test            # go test -race ./...
```

[License GPL-2.0-only](LICENSE)
