# Starter issues & labels (contributor on-ramp)

Drafts for the maintainer to create on GitHub. Labels and issues live on GitHub,
not in the repo tree — apply these with `gh` (or the web UI). Once the
`good first issue` label exists on open issues, GitHub auto-surfaces them on
`github.com/carvalhosauro/watchman/contribute`.

## Labels to create

```bash
gh label create "good first issue" --color 7057ff --description "Good for newcomers"
gh label create "help wanted"      --color 008672 --description "Extra attention is welcome"
```

## Drafted starter issues

### 1. Add ticker aliases for the news match
- **Labels:** `good first issue`
- **Why:** `news.Fresh` matches a CVM headline by exact ticker substring, so a fato
  relevante that names the company ("Petrobras") instead of the ticker ("PETR4")
  is missed.
- **Task:** add a small alias map (ticker → known name variants) consulted by
  `Fresh`, plus table tests.
- **Acceptance:** `Fresh("PETR4", items, today)` returns true when an item's title
  contains a configured alias; existing tests stay green; new table test covers it.
- **Files:** `internal/news/news.go`, `internal/news/news_test.go`.

### 2. Friendlier "no price data" reason
- **Labels:** `good first issue`
- **Why:** when a fetch fails the row reads `no price data`, which doesn't say why
  (unknown ticker vs. network/upstream error).
- **Task:** distinguish the fetch-error cause in `glance.BuildRow` (e.g. "unknown
  ticker" vs "price source unavailable") without changing the LOOK/ignore logic.
- **Acceptance:** `BuildRow` returns a more specific reason per error class; a test
  asserts each message; no behavior change to the verdict.
- **Files:** `internal/glance/glance.go`, `internal/glance/glance_test.go`.

### 3. `wm wallet path` subcommand
- **Labels:** `good first issue`, `help wanted`
- **Why:** users can't easily discover where the wallet file lives.
- **Task:** add `wm wallet path` printing `wallet.Path()`; wire it into the cobra
  tree next to list/add/remove; cover it with a cmd flow test.
- **Acceptance:** `wm wallet path` prints the resolved path (honoring
  `WATCHMAN_WALLET`); `go test ./cmd/...` covers it; help lists the subcommand.
- **Files:** `cmd/wallet.go`, `cmd/wallet_test.go`.
