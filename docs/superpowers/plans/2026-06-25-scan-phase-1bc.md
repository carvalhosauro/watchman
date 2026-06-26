# wm scan — Phase 1b + 1c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Model routing:** Plan = Opus xhigh | Exec atômica = Sonnet high | Exec complexa = Opus xhigh | Review = Opus xhigh | Final = Opus xhigh

**Goal:** Ship phases **1b** (`docs/indicators/` reference + `wm explain`) and **1c** (wallet multi-add, `clear --yes`, default `list`) on top of the shipped 1a `wm scan`.

**Architecture:** 1b adds a markdown reference set under `docs/indicators/`, embedded into the binary by a new root-level `package watchman` asset file, and surfaced by a thin `cmd/explain.go`. 1c extends the pure `internal/wallet` package with `AddMany` + `Clear`, then rewires `cmd/wallet.go` for multi-ticker add, a confirm-gated clear, and a default `list` when no subcommand is given. `wm run` and `wm scan` are untouched.

**Tech Stack:** Go 1.24+, cobra, stdlib `embed`. Tests: table tests + testscript (`.txtar`) via the existing in-process `wm` harness.

**Spec:** [`docs/superpowers/specs/2026-06-25-scan-opportunity-design.md`](../specs/2026-06-25-scan-opportunity-design.md) — this plan implements **phases 1b and 1c only**. Phase 1a (`internal/scan`, `wm scan`) is already shipped.

## Global Constraints

- Module `github.com/carvalhosauro/watchman`; binary `wm`; Go floor **1.24**.
- No DB, no `config.toml` changes, no new HTTP data sources.
- Do **not** import `internal/verdict` or anomaly `Severity` types anywhere in this work.
- Every commit passes: `gofmt`, `goimports`, `golangci-lint run` (0 issues), `go test -race ./...`, coverage **≥80%** (`bash scripts/coverage.sh 80`).
- Conventional Commits; one commit per task.
- Branch: `cursor/scan-phase-1bc-<slug>` off `dev`.
- Indicator docs are written in **English** (decision: EN only), factual/reference tone; each ends with a **"What it does not mean"** section (spec §Documentation).

## Architectural Decision — embed location (deviation from spec)

The spec sketches `internal/indicators/doc.go` embedding `docs/indicators/*.md`. **Go `//go:embed` cannot reference files outside the embedding package's own directory tree** (no `..`), and `internal/indicators/` is not an ancestor of `docs/`. The only ancestor of `docs/` that can host a Go package is the **module root**.

**Resolution:** keep the human-readable markdown at `docs/indicators/` (single source of truth, linked from README) and add a root-level `embed.go` in a new `package watchman` that embeds those files and exposes `IndicatorKeys` + `IndicatorDoc`. `cmd/explain.go` imports the root package. No copy step, no duplication, embed works.

## File Map

| File | Responsibility |
|---|---|
| `docs/indicators/README.md` | How to read `wm scan`; links to each indicator; not-advice disclaimer |
| `docs/indicators/range.md` | Reference for RANGE (position in 52-week band) |
| `docs/indicators/drawdown.md` | Reference for DRAWDOWN |
| `docs/indicators/sma200.md` | Reference for vs SMA200 |
| `docs/indicators/rsi.md` | Reference for RSI(14) |
| `docs/indicators/volume.md` | Reference for VOL |
| `embed.go` | **new** root `package watchman`: `//go:embed` of the 5 docs, `IndicatorKeys`, `IndicatorDoc` |
| `embed_test.go` | **new** root: each key loads non-empty; unknown key errors |
| `cmd/explain.go` | **new** `wm explain [INDICATOR]` + `--list` |
| `cmd/wm/testdata/script/explain.txtar` | **new** black-box explain flows |
| `internal/wallet/wallet.go` | add `AddMany`, `Clear`; `Add` delegates to `AddMany` |
| `internal/wallet/wallet_test.go` | tests for `AddMany`, `Clear` |
| `cmd/wallet.go` | multi-add, `clear --yes`, default subcommand = `list` |
| `cmd/wm/testdata/script/wallet.txtar` | extend: multi-add, default list, clear ±`--yes` |
| `README.md` | document `wm explain` + new wallet commands |
| `ROADMAP.md` | mark 1b and 1c *Done* |

---

# Part A — Phase 1b: `docs/indicators/` + `wm explain`

### Task A1: Indicator reference docs `[atômica]`

**Files:**
- Create: `docs/indicators/README.md`
- Create: `docs/indicators/range.md`
- Create: `docs/indicators/drawdown.md`
- Create: `docs/indicators/sma200.md`
- Create: `docs/indicators/rsi.md`
- Create: `docs/indicators/volume.md`

**Interfaces:**
- Produces: six markdown files. Task A2 embeds `range.md`, `drawdown.md`, `sma200.md`, `rsi.md`, `volume.md` by exact path. Each indicator file's **first line must be a `# <UPPER-LABEL> …` heading** matching the table label so `wm explain` output is greppable. README is human-only (not embedded).

> No automated test for prose; A2's `embed_test.go` is the gate that every embedded file exists and is non-empty. Keep each file short and factual — no buy/sell language.

- [ ] **Step 1: Write `docs/indicators/range.md`**

```markdown
# RANGE — position in the 52-week band

**Formula:** `(close − low) / (high − low) × 100`, over the full available
series (≥ 200 trading days from the ~1-year window).

**Unit:** % from 0 to 100.

## How to read

- **Near 0%** — the close sits near the period's low.
- **Near 100%** — the close sits near the period's high.
- **~50%** — mid-band.

It is the price's relative position inside the year's low–high range. The
`wm scan` table sorts by RANGE ascending (lowest position first) — that is only
a sort key, not a recommendation.

## Limitations

- Needs ≥ 200 trading days; with fewer, the field is omitted.
- Low and high are closes, not intraday extremes.
- A narrow band (high ≈ low) makes the position unstable.

## What it does not mean

A low RANGE does **not** mean "cheap" and a high RANGE does **not** mean
"expensive". It is price geometry, not valuation. It is not a buy or sell signal.
```

- [ ] **Step 2: Write `docs/indicators/drawdown.md`**

```markdown
# DRAWDOWN — decline from the peak

**Formula:** `(close − peak) / peak × 100`, where peak is the highest close in
the series.

**Unit:** % (always ≤ 0).

## How to read

- **0%** — the current close is the series peak.
- **−22%** — 22% below the highest close of the period.

`wm scan --detail` also shows the reference peak's date and value.

## Limitations

- Needs ≥ 2 trading days.
- Uses closes; ignores intraday highs.
- Measures distance from the top, not how long the decline lasted.

## What it does not mean

A large DRAWDOWN does **not** signal an imminent recovery nor that the asset
"has to" rebound. It is a descriptive measure of how far price fell from its
top, not a forecast.
```

- [ ] **Step 3: Write `docs/indicators/sma200.md`**

```markdown
# vs SMA200 — distance from the 200-day average

**Formula:** `(close − SMA200) / SMA200 × 100`, where SMA200 is the simple
average of the last 200 closes.

**Unit:** % (+ above, − below).

## How to read

- **Positive** — the close is above the long-term average.
- **Negative** — below it.

`wm scan --detail` shows the absolute SMA200 value.

## Limitations

- Needs ≥ 200 trading days; with fewer, the field is omitted.
- Simple (unweighted) average; reacts slowly to recent moves.

## What it does not mean

Being above or below the SMA200 is **not** a buy or sell signal. It is a
descriptive long-term trend reference, not a prediction.
```

- [ ] **Step 4: Write `docs/indicators/rsi.md`**

```markdown
# RSI — Relative Strength Index (14)

**Calculation:** Wilder RSI with a 14-period over closes — the same algorithm as
the `wm run` anomaly engine.

**Unit:** 0 to 100.

## How to read

- **> 70** — conventionally called "overbought".
- **< 30** — conventionally called "oversold".
- **~50** — neutral momentum.

## Limitations

- Needs ≥ 15 closes.
- In strong trends the RSI can sit at an extreme for a long time.

## What it does not mean

A low RSI does **not** mean "buy" and a high RSI does **not** mean "sell".
Extremes describe recent momentum; they do not turn price on their own.
```

- [ ] **Step 5: Write `docs/indicators/volume.md`**

```markdown
# VOL — volume vs the 20-day average

**Formula:** `last session's volume ÷ average volume of the prior 20 sessions`.

**Unit:** multiple (×).

## How to read

- **1.0×** — volume in line with the recent average.
- **2.0×** — twice the 20-day average.
- **< 1.0×** — below average.

## Limitations

- Needs ≥ 21 sessions with volume.
- Sensitive to auctions, corporate events, and low liquidity.

## What it does not mean

High volume does **not** indicate direction — only participation. It does not
say whether a rise or fall will continue. It is context, not a buy or sell
signal.
```

- [ ] **Step 6: Write `docs/indicators/README.md`**

```markdown
# `wm scan` indicators

`wm scan` prints a **neutral, factual** technical readout of the tickers you
follow — numbers, with no buy or sell verdict. This folder explains each column.

| Column | Indicator | Reference |
|---|---|---|
| RANGE | Position in the 52-week band | [range.md](range.md) |
| DRAWDOWN | Decline from the peak | [drawdown.md](drawdown.md) |
| vs SMA200 | Distance from the 200-day average | [sma200.md](sma200.md) |
| RSI | Relative strength (Wilder 14) | [rsi.md](rsi.md) |
| VOL | Volume vs the 20-day average | [volume.md](volume.md) |

The table sorts by **RANGE ascending** (lowest position in the band first). That
is only a sort key, **not** a recommendation.

In the terminal: `wm explain <indicator>` (e.g. `wm explain range`) or
`wm explain --list`.

## Disclaimer

`watchman` gives no buy/sell advice, price targets, or valuation. Technical
indicators are **descriptive, not predictive**. Fundamentals are out of scope.
```

- [ ] **Step 7: Commit**

```bash
git add docs/indicators/
git commit -m "docs(indicators): add scan indicator reference (phase 1b)"
```

---

### Task A2: Root embed package `[atômica]`

**Files:**
- Create: `embed.go`
- Create: `embed_test.go`

**Interfaces:**
- Consumes: the five `docs/indicators/*.md` files from Task A1 (must exist or the build fails).
- Produces: `package watchman` exporting `var IndicatorKeys []string` (canonical order `range, drawdown, sma200, rsi, volume`) and `func IndicatorDoc(key string) (string, error)`. Task A3 imports these.

- [ ] **Step 1: Write the failing test** — `embed_test.go`

```go
package watchman

import (
	"strings"
	"testing"
)

func TestIndicatorDocLoadsEachKey(t *testing.T) {
	for _, k := range IndicatorKeys {
		doc, err := IndicatorDoc(k)
		if err != nil {
			t.Fatalf("IndicatorDoc(%q) error: %v", k, err)
		}
		if strings.TrimSpace(doc) == "" {
			t.Fatalf("IndicatorDoc(%q) returned empty", k)
		}
	}
}

func TestIndicatorDocUnknown(t *testing.T) {
	if _, err := IndicatorDoc("bogus"); err == nil {
		t.Fatal("want error for unknown indicator")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test . -run TestIndicatorDoc -v`
Expected: FAIL — `IndicatorKeys` / `IndicatorDoc` undefined (or package `watchman` not found).

- [ ] **Step 3: Write the implementation** — `embed.go`

```go
// Package watchman bundles assets compiled into the wm binary — currently the
// indicator reference docs surfaced by `wm explain`. The markdown lives under
// docs/indicators/ (human-readable, single source of truth) and is embedded
// here because //go:embed cannot reach files outside the embedding package's
// directory, and the module root is the only Go-package ancestor of docs/.
package watchman

import (
	"embed"
	"fmt"
)

//go:embed docs/indicators/range.md docs/indicators/drawdown.md docs/indicators/sma200.md docs/indicators/rsi.md docs/indicators/volume.md
var indicatorDocs embed.FS

// IndicatorKeys is the canonical display order for `wm explain --list` and the
// scan table columns.
var IndicatorKeys = []string{"range", "drawdown", "sma200", "rsi", "volume"}

// IndicatorDoc returns the reference markdown for key, or an error if key is not
// a known indicator.
func IndicatorDoc(key string) (string, error) {
	for _, k := range IndicatorKeys {
		if k == key {
			b, err := indicatorDocs.ReadFile("docs/indicators/" + key + ".md")
			if err != nil {
				return "", err
			}
			return string(b), nil
		}
	}
	return "", fmt.Errorf("unknown indicator %q", key)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test . -run TestIndicatorDoc -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add embed.go embed_test.go
git commit -m "feat(explain): embed indicator docs in a root asset package"
```

---

### Task A3: `wm explain` command + testscript `[atômica]`

**Files:**
- Create: `cmd/explain.go`
- Create: `cmd/wm/testdata/script/explain.txtar`

**Interfaces:**
- Consumes: `watchman.IndicatorKeys`, `watchman.IndicatorDoc` from Task A2.
- Produces: `wm explain [INDICATOR]` and `wm explain --list`. Behavior: `--list` or no args → one-line key list + usage hint to stdout; a known indicator → its markdown to stdout; an unknown indicator → error (non-zero exit) with a hint.

- [ ] **Step 1: Write the command** — `cmd/explain.go`

```go
package cmd

import (
	"fmt"
	"strings"

	"github.com/carvalhosauro/watchman"
	"github.com/spf13/cobra"
)

func init() {
	var list bool
	cmd := &cobra.Command{
		Use:   "explain [INDICATOR]",
		Short: "print reference docs for a scan indicator",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			out := cmd.OutOrStdout()
			if list || len(args) == 0 {
				_, _ = fmt.Fprintf(out, "Indicators: %s\n", strings.Join(watchman.IndicatorKeys, ", "))
				_, _ = fmt.Fprintln(out, "Run: wm explain <indicator>")
				return nil
			}
			doc, err := watchman.IndicatorDoc(args[0])
			if err != nil {
				return fmt.Errorf("%w — run 'wm explain --list' to see indicators", err)
			}
			_, _ = fmt.Fprint(out, doc)
			return nil
		},
	}
	cmd.Flags().BoolVar(&list, "list", false, "list indicator keys")
	rootCmd.AddCommand(cmd)
}
```

- [ ] **Step 2: Build to verify wiring**

Run: `make build && ./bin/wm explain --list`
Expected: build succeeds; prints `Indicators: range, drawdown, sma200, rsi, volume`.

- [ ] **Step 3: Write the testscript** — `cmd/wm/testdata/script/explain.txtar`

```text
# --list shows every indicator key
wm explain --list
stdout 'range'
stdout 'drawdown'
stdout 'sma200'
stdout 'rsi'
stdout 'volume'

# bare explain also lists, with a usage hint
wm explain
stdout 'Indicators:'
stdout 'wm explain <indicator>'

# a known indicator prints its reference doc
wm explain range
stdout 'RANGE'
stdout 'What it does not mean'

# unknown indicator exits non-zero with a hint
! wm explain bogus
stderr 'unknown indicator'
stderr 'wm explain --list'
```

- [ ] **Step 4: Run the testscript**

Run: `go test -race ./cmd/wm/ -run TestScripts -v`
Expected: PASS (all `.txtar`, including new `explain.txtar`).

- [ ] **Step 5: Commit**

```bash
git add cmd/explain.go cmd/wm/testdata/script/explain.txtar
git commit -m "feat(explain): add wm explain [INDICATOR] and --list"
```

---

### Task A4: Document `wm explain` (README + ROADMAP) `[atômica]`

**Files:**
- Modify: `README.md` (Usage block, after the `wm scan --json` line)
- Modify: `ROADMAP.md` (Explain 1b bullet, line 23)

- [ ] **Step 1: Add explain to README Usage** — insert after the `wm scan --json` line:

```markdown
wm explain range          # reference doc for an indicator (range, drawdown, …)
wm explain --list         # list indicator keys
```

- [ ] **Step 2: Mark 1b done in ROADMAP** — replace line 23:

```markdown
- **Explain (1b)** — *Done* — `docs/indicators/` reference + `wm explain [INDICATOR]` / `--list`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md ROADMAP.md
git commit -m "docs: document wm explain (phase 1b)"
```

---

# Part B — Phase 1c: wallet UX (multi-add, clear, default list)

### Task B1: `wallet.AddMany` `[atômica]`

**Files:**
- Modify: `internal/wallet/wallet.go`
- Modify: `internal/wallet/wallet_test.go`

**Interfaces:**
- Produces: `func AddMany(path string, tickers ...string) error` — reads current list once, appends each new ticker uppercased/trimmed, dedupes against existing and within the input, skips blanks, writes once. `Add` is refactored to delegate: `func Add(path, ticker string) error { return AddMany(path, ticker) }`. Task B3 calls `AddMany`.

- [ ] **Step 1: Write the failing test** — append to `internal/wallet/wallet_test.go`

```go
func TestAddMany(t *testing.T) {
	p := filepath.Join(t.TempDir(), "wallet")
	if err := AddMany(p, "petr4", "VALE3", "petr4", "  mxrf11 ", ""); err != nil {
		t.Fatal(err)
	}
	got, _ := List(p)
	want := []string{"PETR4", "VALE3", "MXRF11"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	// dedupes against what is already stored
	if err := AddMany(p, "PETR4", "ITUB4"); err != nil {
		t.Fatal(err)
	}
	got, _ = List(p)
	want = []string{"PETR4", "VALE3", "MXRF11", "ITUB4"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/wallet/ -run TestAddMany -v`
Expected: FAIL — `AddMany` undefined.

- [ ] **Step 3: Implement** — in `internal/wallet/wallet.go`, replace the existing `Add` with:

```go
// Add appends ticker (uppercased) to the wallet at path, ignoring duplicates.
func Add(path, ticker string) error { return AddMany(path, ticker) }

// AddMany appends every ticker (uppercased, trimmed) to the wallet at path in a
// single write, skipping blanks and duplicates — both against the existing list
// and within the input.
func AddMany(path string, tickers ...string) error {
	cur, err := List(path)
	if err != nil {
		return err
	}
	seen := make(map[string]bool, len(cur))
	for _, t := range cur {
		seen[t] = true
	}
	for _, t := range tickers {
		t = strings.ToUpper(strings.TrimSpace(t))
		if t == "" || seen[t] {
			continue
		}
		seen[t] = true
		cur = append(cur, t)
	}
	return write(path, cur)
}
```

(`slices` import is now unused — remove it from the import block.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/wallet/ -run 'TestAdd' -v`
Expected: PASS (both `TestAddMany` and the existing `TestAddRemove`).

- [ ] **Step 5: Commit**

```bash
git add internal/wallet/wallet.go internal/wallet/wallet_test.go
git commit -m "feat(wallet): add AddMany for multi-ticker add"
```

---

### Task B2: `wallet.Clear` `[atômica]`

**Files:**
- Modify: `internal/wallet/wallet.go`
- Modify: `internal/wallet/wallet_test.go`

**Interfaces:**
- Produces: `func Clear(path string) error` — truncates the wallet file to empty (creating its parent dir if needed); a subsequent `List` returns an empty slice. Task B3 calls `Clear`.

- [ ] **Step 1: Write the failing test** — append to `internal/wallet/wallet_test.go`

```go
func TestClear(t *testing.T) {
	p := filepath.Join(t.TempDir(), "sub", "wallet")
	if err := AddMany(p, "PETR4", "VALE3"); err != nil {
		t.Fatal(err)
	}
	if err := Clear(p); err != nil {
		t.Fatal(err)
	}
	got, err := List(p)
	if err != nil || len(got) != 0 {
		t.Fatalf("after clear got %v,%v want empty,nil", got, err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/wallet/ -run TestClear -v`
Expected: FAIL — `Clear` undefined.

- [ ] **Step 3: Implement** — append to `internal/wallet/wallet.go`

```go
// Clear empties the wallet at path, removing all tickers. The file is left in
// place (truncated to empty) so List keeps working without special-casing.
func Clear(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte{}, 0o644)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/wallet/ -run TestClear -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/wallet/wallet.go internal/wallet/wallet_test.go
git commit -m "feat(wallet): add Clear to empty the wallet"
```

---

### Task B3: Rewire `cmd/wallet.go` — multi-add, clear, default list `[complexa]`

**Files:**
- Modify: `cmd/wallet.go` (full rewrite of `init`)

**Interfaces:**
- Consumes: `wallet.AddMany` (B1), `wallet.Clear` (B2), existing `wallet.List` / `wallet.Remove`.
- Produces CLI behavior: `wm wallet` (no subcommand) → list; `wm wallet list` → list; `wm wallet add T1 T2 …` → multi-add; `wm wallet remove T` → remove; `wm wallet clear` → error unless `--yes`, then empties.

**Note (cobra nuance):** the parent `wallet` command sets `RunE = runList` and `Args = cobra.NoArgs`. Cobra resolves subcommand names (`add`/`remove`/`list`/`clear`) before the parent's arg check, so those still dispatch normally; a bare `wm wallet` runs `runList`; an unknown token like `wm wallet PETR4` fails `NoArgs` rather than silently mis-adding. This is intentional — adds require the explicit `add` verb.

- [ ] **Step 1: Rewrite** — replace the entire body of `cmd/wallet.go`

```go
package cmd

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	runList := func(cmd *cobra.Command, _ []string) error {
		ts, err := wallet.List(wallet.Path())
		if err != nil {
			return err
		}
		for _, t := range ts {
			_, _ = fmt.Fprintln(cmd.OutOrStdout(), t)
		}
		return nil
	}

	walletCmd := &cobra.Command{
		Use:   "wallet",
		Short: "manage held tickers",
		Args:  cobra.NoArgs,
		RunE:  runList, // bare `wm wallet` defaults to list
	}

	walletCmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "list tickers",
		Args:  cobra.NoArgs,
		RunE:  runList,
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "add TICKER [TICKER...]",
		Short: "add one or more tickers",
		Args:  cobra.MinimumNArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.AddMany(wallet.Path(), a...) },
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "remove TICKER",
		Short: "remove a ticker",
		Args:  cobra.ExactArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.Remove(wallet.Path(), a[0]) },
	})

	var clearYes bool
	clearCmd := &cobra.Command{
		Use:   "clear",
		Short: "remove all tickers (requires --yes)",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if !clearYes {
				return fmt.Errorf("refusing to clear wallet without --yes")
			}
			return wallet.Clear(wallet.Path())
		},
	}
	clearCmd.Flags().BoolVar(&clearYes, "yes", false, "confirm removing all tickers")
	walletCmd.AddCommand(clearCmd)

	rootCmd.AddCommand(walletCmd)
}
```

- [ ] **Step 2: Build + smoke the new surface**

Run:
```bash
make build
WATCHMAN_WALLET=$(mktemp) ./bin/wm wallet add PETR4 vale3
WATCHMAN_WALLET=/tmp/does-not-matter ./bin/wm wallet clear   # expect: error, exit 1
```
Expected: build succeeds; multi-add stores `PETR4`, `VALE3`; `clear` without `--yes` prints the refuse error and exits 1.

- [ ] **Step 3: Run the existing cmd test**

Run: `go test ./cmd/ -run TestWalletCommands -v`
Expected: PASS (`wm wallet add petr4` still stores `PETR4\n`).

- [ ] **Step 4: Commit**

```bash
git add cmd/wallet.go
git commit -m "feat(wallet): multi-add, clear --yes, default list subcommand"
```

---

### Task B4: Extend wallet testscript `[atômica]`

**Files:**
- Modify: `cmd/wm/testdata/script/wallet.txtar`

**Note:** the existing script asserts `! wm wallet add A B` **fails** (old `ExactArgs(1)`). Multi-add now makes that succeed, so that line **must be replaced**. Keep `! wm wallet add` (zero args still fails).

- [ ] **Step 1: Replace the arg-validation block** — change the existing lines:

Old:
```text
# arg validation: add needs exactly one ticker
! wm wallet add
! wm wallet add A B
```

New:
```text
# arg validation: add needs at least one ticker
! wm wallet add

# multi-add: several tickers in one call, deduped and uppercased
env WATCHMAN_WALLET=$WORK/multi
wm wallet add petr4 VALE3 petr4
cmp multi want_multi

# default subcommand: bare `wm wallet` lists
wm wallet
stdout '^PETR4$'
stdout '^VALE3$'

# clear requires --yes; without it the wallet is untouched
! wm wallet clear
stderr 'yes'
cmp multi want_multi

# clear --yes empties the wallet
wm wallet clear --yes
wm wallet list
! stdout .
```

- [ ] **Step 2: Add the `want_multi` fixture** — append to the file's txtar archive section (after `want_mxrf`):

```text
-- want_multi --
PETR4
VALE3
```

- [ ] **Step 3: Run the testscript**

Run: `go test -race ./cmd/wm/ -run TestScripts -v`
Expected: PASS (updated `wallet.txtar`).

- [ ] **Step 4: Commit**

```bash
git add cmd/wm/testdata/script/wallet.txtar
git commit -m "test(wallet): cover multi-add, default list, clear --yes"
```

---

### Task B5: Document wallet UX (README + ROADMAP) `[atômica]`

**Files:**
- Modify: `README.md` (Usage wallet block)
- Modify: `ROADMAP.md` (Wallet UX 1c bullet, line 24)

- [ ] **Step 1: Update README wallet usage** — replace the wallet lines:

```markdown
wm wallet add PETR4 VALE3   # track one or more assets (dedupes, uppercases)
wm wallet                   # list tracked tickers (default subcommand)
wm wallet list              # same, explicit
wm wallet remove PETR4
wm wallet clear --yes       # remove all tracked tickers (--yes required)
```

- [ ] **Step 2: Mark 1c done in ROADMAP** — replace line 24:

```markdown
- **Wallet UX (1c)** — *Done* — multi-ticker `add`, `clear --yes`, default `list`.
```

- [ ] **Step 3: Final CI gate**

Run: `make ci`
Expected: PASS — gofmt clean, golangci-lint 0 issues, `go test -race ./...` green, coverage ≥80%, build ok.

- [ ] **Step 4: Commit**

```bash
git add README.md ROADMAP.md
git commit -m "docs: document wallet multi-add/clear/default list (phase 1c)"
```

---

## Spec Coverage Checklist

| Spec requirement (§) | Task |
|---|---|
| `docs/indicators/` README + 5 indicator files | A1 |
| Each doc ends with "What it does not mean" | A1 |
| English reference tone (EN-only decision) | A1 (Global Constraints) |
| `wm explain INDICATOR` prints embedded doc | A2, A3 |
| `wm explain --list` prints keys | A3 |
| Unknown indicator → exit 1 with hint | A3 |
| Embedded content (not filesystem-dependent) | A2 |
| `wm wallet add T1 T2 …` multi, dedupe, uppercase | B1, B3 |
| `wm wallet clear` requires `--yes` | B2, B3 |
| `wm wallet` defaults to `list` | B3 |
| Existing add/remove/list unchanged in behavior | B1, B3 (delegation + explicit `list`) |
| testscript wallet cases | B4 |
| No breaking change to wallet file format | B1, B2 (same `write`/empty-file shape) |
| README + ROADMAP updated | A4, B5 |
| Coverage ≥80% | B5 (`make ci`) |

**Explicitly out of scope (later phases):** history NDJSON, `wm schedule`, Cursor skill, `--sort` flag, config knobs for scan thresholds, MACD/SMA-cross/streak signals.

## Self-Review Notes

- **Embed deviation** from spec's `internal/indicators/doc.go` is forced by Go's embed rule (no `..`); root `package watchman` is the minimal correct home. Documented above so the executor doesn't "fix" it back.
- **`slices` import** becomes unused in `wallet.go` once `Add` delegates to `AddMany` — Task B1 Step 3 calls this out; `goimports`/golangci would otherwise fail.
- **Existing `! wm wallet add A B`** assertion is invalidated by multi-add — Task B4 explicitly replaces it (a silent miss here would fail CI).
- **Default-list cobra wiring** (parent `RunE` + `NoArgs`) is the one subtle piece → Task B3 tagged `[complexa]` for Opus.
- **Coverage:** the root `package watchman` is new code; `embed_test.go` exercises both `IndicatorDoc` branches (known + unknown) to keep the package above the 80% floor.
- Parts A and B are independent and could be executed/reviewed separately; ordering A→B is for a single clean branch and one `make ci` at the end.
