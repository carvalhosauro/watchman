# watchman v2 (Go) — Morning Noise/Real Glance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Model routing (deep-plan):** Plan = Opus xhigh | Exec atômica = Sonnet high | Exec complexa = Opus xhigh | Review = Opus xhigh | Final = Opus xhigh
> **Execution mode for THIS build:** default = *you author, AI tutors/reviews* (credibility goal = "explain every line"). Each feature task carries complete code + a **Concept to understand**.

**Goal:** A single static `wm` binary that, for the B3 assets you hold, says in one screen which to **ignore** and which to **LOOK** at — abnormal price move OR fresh official news — shipped to OSS standard.

**Architecture:** Go CLI (cobra). No DB. `wm run` fetches trailing price history (Yahoo) + the CVM feed live, computes a pure z-score anomaly + a pure verdict, prints rows. Every package is tested — pure logic table-tested, and network + CLI **flows tested via `httptest`** (no live calls in tests). Old Elixir repo kept only as a **reference**.

**Tech Stack:** Go 1.22+, cobra; stdlib net/http, encoding/json, encoding/xml. Tooling: gofmt/goimports, golangci-lint, lefthook, git-cliff, GoReleaser, GitHub Actions. Static binary (`CGO_ENABLED=0`).

## Global Constraints

- **You write and understand every line.** Don't type code you can't explain.
- **Phases:** **Phase 0** = env reset + OSS tooling/guardrails (Tasks 1–7). **Phase A** = value core: wallet CRUD + `wm run` (Tasks 8–17). **Phase B** = history/schedule/update/completions (roadmap; detail after the n=1 value signal passes per `mvp-watchman-noise-glance-2026-06-20.md`).
- **Every commit passes the gates** (gofmt, golangci-lint, tests) — lefthook enforces locally, CI enforces on PR. Conventional Commits required (commit-msg hook).
- **One source each, hardcoded:** prices = Yahoo (`<TICKER>.SA`), news = CVM feed. No DB.
- **Every package has tests, including flow/integration tests** via `net/http/httptest` — no real network in tests. Seams `prices.BaseURL`, `news.FeedURL`, and the `WATCHMAN_WALLET` env make the whole flow injectable. Pure logic stays table-tested; nothing ships untested.
- **Module path:** `github.com/carvalhosauro/watchman`. **Binary:** `wm`. One commit per task.

**Milestone (fallback line):** after **Task 14** you have a working price-only glance end-to-end.

---

## Phase 0 — Environment reset + OSS tooling

### Task 1: Reset env + Go module + cobra skeleton  ·  `[complexa]`

**Files:** `go.mod`, `main.go`, `cmd/root.go`, `.gitignore`; delete Elixir sources; keep `LICENSE`, `.github/ISSUE_TEMPLATE/`, `pull_request_template.md`, `CONTRIBUTING.md`.

**Concept to understand:** `go mod init`, cobra root pattern, ldflags version injection (`-X .../cmd.version=...`), why `internal/` is import-private.

- [ ] **Step 1: Preserve Elixir, new branch**

```bash
git tag v0.6.0-elixir-reference
git switch -c v2-go
git rm -r lib mix.exs mix.lock config test priv .formatter.exs .credo.exs _build deps cover 2>/dev/null; true
```

- [ ] **Step 2: Init module + dep**

```bash
go mod init github.com/carvalhosauro/watchman
go get github.com/spf13/cobra@latest
```

- [ ] **Step 3: `cmd/root.go`** (with version for `--version` + future auto-update)

```go
package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

// version is injected at release time via -ldflags "-X .../cmd.version=...".
var version = "dev"

var rootCmd = &cobra.Command{
	Use:     "wm",
	Short:   "watchman — is this market move noise or worth a look?",
	Version: version,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
```

- [ ] **Step 4: `main.go`**

```go
package main

import "github.com/carvalhosauro/watchman/cmd"

func main() { cmd.Execute() }
```

- [ ] **Step 5: `.gitignore`** (append)

```
/wm
/dist/
/coverage.out
*.test
```

- [ ] **Step 6: Verify + commit**

```bash
go build -o wm . && ./wm --version && ./wm --help
git add -A && git commit -m "chore!: reset to Go static-binary CLI for v2"
```

**✅ Done when:**
- `go build -o wm . && ./wm --version && ./wm --help` → builds clean; prints `wm version dev`; help lists `completion` + `help`.
- `git ls-files | grep -E '^(mix\.exs|lib/|test/)'` → prints nothing (Elixir removed from tracking).

---

### Task 2: Dev task runner (Makefile)  ·  `[atômica]`

**Files:** Create `Makefile`.

**Concept to understand:** one reproducible entrypoint per dev action; Make recipes require **TAB** indentation.

- [ ] **Step 1: Create `Makefile`** (indent recipes with real tabs)

```makefile
.PHONY: build test cover fmt lint tidy ci snapshot changelog

build:
	go build -o wm .

test:
	go test -race ./...

cover:
	bash scripts/coverage.sh 80

fmt:
	gofmt -w . && goimports -w .

lint:
	golangci-lint run

tidy:
	go mod tidy

changelog:
	git cliff -o CHANGELOG.md

snapshot:
	goreleaser release --snapshot --clean

ci: fmt lint cover build
```

- [ ] **Step 2: Verify + commit**

```bash
make build
git add Makefile && git commit -m "build: add Makefile dev targets"
```

**✅ Done when:**
- `make build` → exit 0, produces `./wm`. (If `missing separator`: recipes are indented with spaces, must be TABs.)

---

### Task 3: Formatter + linter (golangci-lint)  ·  `[atômica]`

**Files:** Create `.golangci.yml`.

**Concept to understand:** golangci-lint bundles vet/staticcheck/errcheck/etc.; a strict-but-sane set is a credibility signal. Install: `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` (or brew).

- [ ] **Step 1: Create `.golangci.yml`**

```yaml
run:
  timeout: 3m
linters:
  enable:
    - govet
    - staticcheck
    - errcheck
    - ineffassign
    - unused
    - gofmt
    - goimports
    - revive
    - misspell
    - unconvert
issues:
  exclude-rules:
    - path: _test\.go
      linters: [errcheck]
```

- [ ] **Step 2: Verify (must be clean on the skeleton) + commit**

```bash
go install golang.org/x/tools/cmd/goimports@latest
golangci-lint run
git add .golangci.yml && git commit -m "ci: add golangci-lint config"
```

**✅ Done when:**
- `golangci-lint run` → exit 0, zero findings on the skeleton, no config-parse error.

---

### Task 4: Test coverage gate  ·  `[atômica]`

**Files:** Create `scripts/coverage.sh`.

**Concept to understand:** a coverage floor that fails CI prevents silent erosion; `go tool cover -func` `total:` line is the number to parse.

- [ ] **Step 1: Create `scripts/coverage.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
THRESHOLD=${1:-70}
go test -race -coverprofile=coverage.out ./...
pct=$(go tool cover -func=coverage.out | awk '/^total:/ {gsub(/%/,"",$3); print $3}')
echo "coverage: ${pct}% (threshold ${THRESHOLD}%)"
awk -v p="$pct" -v t="$THRESHOLD" 'BEGIN{exit !(p+0 >= t+0)}' \
  || { echo "coverage below threshold"; exit 1; }
```

- [ ] **Step 2: Make executable, verify, commit**

```bash
chmod +x scripts/coverage.sh
bash scripts/coverage.sh 0   # 0% floor: passes even with no tests yet
git add scripts/coverage.sh && git commit -m "ci: add coverage threshold gate"
```

> Floor is `80` (Makefile + CI). With flow tests covering the network + CLI paths in addition to pure logic, the suite clears 80% comfortably.

**✅ Done when:**
- `bash scripts/coverage.sh 0` → prints `coverage: …%` and exit 0.
- `bash scripts/coverage.sh 999` → prints `coverage below threshold` and exit 1 (proves the gate actually bites — not a no-op).

---

### Task 5: Pre-commit hooks + Conventional Commits (lefthook)  ·  `[atômica]`

**Files:** Create `lefthook.yml`, `scripts/commit-msg.sh`.

**Concept to understand:** lefthook is a single Go binary (no Python), runs gates pre-commit and validates the commit message format. Install: `go install github.com/evilmartians/lefthook@latest` (or brew).

- [ ] **Step 1: Create `lefthook.yml`**

```yaml
pre-commit:
  parallel: true
  commands:
    fmt:
      run: test -z "$(gofmt -l .)"
    lint:
      run: golangci-lint run
    test:
      run: go test ./...
commit-msg:
  commands:
    conventional:
      run: bash scripts/commit-msg.sh {1}
```

- [ ] **Step 2: Create `scripts/commit-msg.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
header=$(head -1 "$1")
regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9_-]+\))?!?: .+'
if [[ ! "$header" =~ $regex ]]; then
  echo "Commit message must follow Conventional Commits: type(scope): subject"
  echo "got: $header"
  exit 1
fi
```

- [ ] **Step 3: Install hooks, verify, commit**

```bash
chmod +x scripts/commit-msg.sh
lefthook install
git add lefthook.yml scripts/commit-msg.sh && git commit -m "ci: add lefthook pre-commit + conventional-commit hook"
```

**✅ Done when:**
- `printf 'bad msg\n' > /tmp/m && bash scripts/commit-msg.sh /tmp/m` → exit 1 + format error.
- `printf 'feat(x): ok\n' > /tmp/m && bash scripts/commit-msg.sh /tmp/m` → exit 0.
- `lefthook run pre-commit` → runs fmt + lint + test.

---

### Task 6: Changelog (git-cliff)  ·  `[atômica]`

**Files:** Create `cliff.toml`, `CHANGELOG.md` (generated).

**Concept to understand:** git-cliff turns Conventional Commits into a changelog deterministically (single Rust binary). Install: `cargo install git-cliff` or brew. You can adapt the old repo's `cliff.toml` (it's in `v0.6.0-elixir-reference`).

- [ ] **Step 1: Create `cliff.toml`** (minimal conventional config)

```toml
[changelog]
header = "# Changelog\n\n"
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | upper_first }}
{% for commit in commits %}
- {{ commit.message | upper_first }}
{% endfor %}
{% endfor %}
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true
commit_parsers = [
  { message = "^feat", group = "Features" },
  { message = "^fix", group = "Bug Fixes" },
  { message = "^docs", group = "Documentation" },
  { message = "^perf", group = "Performance" },
  { message = "^refactor", group = "Refactor" },
  { message = "^test", group = "Tests" },
  { message = "^(build|ci|chore)", group = "Tooling" },
]
tag_pattern = "v[0-9]*"
```

- [ ] **Step 2: Generate, verify, commit**

```bash
git cliff -o CHANGELOG.md
git add cliff.toml CHANGELOG.md && git commit -m "docs: add git-cliff changelog config"
```

**✅ Done when:**
- `git cliff -o CHANGELOG.md` → exit 0; `CHANGELOG.md` starts with `# Changelog` and lists prior commits under a `### Tooling`/`### Features` group.

---

### Task 7: Releases + CI (GoReleaser + GitHub Actions)  ·  `[complexa]`

**Files:** Create `.goreleaser.yaml`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`. Remove old Elixir workflows.

**Concept to understand:** GoReleaser cross-builds static binaries (linux/darwin × amd64/arm64), publishes a GitHub Release with archives + checksums on a `v*` tag → this IS your easy-distribution + the asset source for Phase B auto-update. CI gates every PR.

- [ ] **Step 1: Remove stale Elixir CI**

```bash
git rm .github/workflows/*.yml 2>/dev/null; true
```

- [ ] **Step 2: `.goreleaser.yaml`** (GoReleaser v2)

```yaml
version: 2
project_name: watchman
before:
  hooks: [go mod tidy]
builds:
  - id: wm
    binary: wm
    main: .
    env: [CGO_ENABLED=0]
    goos: [linux, darwin]
    goarch: [amd64, arm64]
    ldflags:
      - -s -w -X github.com/carvalhosauro/watchman/cmd.version={{ .Version }}
archives:
  - id: wm
    formats: [tar.gz]
    name_template: "wm_{{ .Os }}_{{ .Arch }}"
checksum:
  name_template: checksums.txt
changelog:
  disable: true   # git-cliff owns the changelog
release:
  github:
    owner: carvalhosauro
    name: watchman
```

- [ ] **Step 3: `.github/workflows/ci.yml`**

```yaml
name: CI
on:
  push:
    branches: [main, v2-go]
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: "1.22" }
      - run: test -z "$(gofmt -l .)"
      - uses: golangci/golangci-lint-action@v6
        with: { version: latest }
      - run: bash scripts/coverage.sh 80
      - run: go build -o wm .
```

- [ ] **Step 4: `.github/workflows/release.yml`**

```yaml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-go@v5
        with: { go-version: "1.22" }
      - uses: goreleaser/goreleaser-action@v6
        with: { version: latest, args: release --clean }
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 5: Verify locally (no publish) + commit**

```bash
goreleaser check
goreleaser release --snapshot --clean   # builds dist/ artifacts locally
git add .goreleaser.yaml .github/workflows && git commit -m "ci: GoReleaser cross-platform release + CI gates"
```

**✅ Done when:**
- `goreleaser check` → config valid.
- `goreleaser release --snapshot --clean && ls dist/` → produces `wm_linux_amd64*`, `wm_linux_arm64*`, `wm_darwin_amd64*`, `wm_darwin_arm64*` archives + `checksums.txt`.
- `gofmt -l .` → empty; both workflow YAMLs parse.

**Phase 0 done:** clean Go repo with formatter, linter, coverage gate, pre-commit hooks, conventional commits, changelog, and a working cross-platform release pipeline. Now build features on top of green rails.

---

## Phase A — Value core (wallet CRUD + `wm run`)

### Task 8: Wallet — list (read)  ·  `[atômica]`

**Files:** Create `internal/wallet/wallet.go`, `internal/wallet/wallet_test.go`.

**Interfaces:** `wallet.Path() string` (`~/.config/watchman/wallet`); `wallet.List(path string) ([]string, error)` — uppercased, trimmed, blank/`#` skipped; missing file → `([]string{}, nil)`.

**Concept to understand:** `os.ReadFile`+`os.IsNotExist`, string cleanup, path-as-parameter for testability.

- [ ] **Step 1: Failing test** — `internal/wallet/wallet_test.go`

```go
package wallet

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestList(t *testing.T) {
	p := filepath.Join(t.TempDir(), "wallet")
	os.WriteFile(p, []byte("petr4\n\n# fiis\nmxrf11\nITUB4\n"), 0o644)
	got, err := List(p)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"PETR4", "MXRF11", "ITUB4"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestListMissing(t *testing.T) {
	if got, err := List("/no/such/file"); err != nil || len(got) != 0 {
		t.Fatalf("want empty,nil got %v,%v", got, err)
	}
}

func TestPathEnvOverride(t *testing.T) {
	t.Setenv("WATCHMAN_WALLET", "/tmp/x/wallet")
	if Path() != "/tmp/x/wallet" {
		t.Fatalf("env override ignored: %s", Path())
	}
}
```

- [ ] **Step 2: `go test ./internal/wallet/` → fails (no impl).**
- [ ] **Step 3: Implement** — `internal/wallet/wallet.go`

```go
// Package wallet stores the tickers the user holds in a plain text file.
package wallet

import (
	"os"
	"path/filepath"
	"strings"
)

// Path is the wallet file location; WATCHMAN_WALLET overrides it (test seam + power users).
func Path() string {
	if p := os.Getenv("WATCHMAN_WALLET"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "watchman", "wallet")
}

func List(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}
	out := []string{}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, strings.ToUpper(line))
	}
	return out, nil
}
```

- [ ] **Step 4: test passes → commit** — `git add internal/wallet && git commit -m "feat(wallet): list held tickers"`

**✅ Done when:**
- `go test ./internal/wallet/ -v` → `TestList`, `TestListMissing`, `TestPathEnvOverride` PASS (uppercased, comments/blanks skipped, missing file → empty; `WATCHMAN_WALLET` overrides the path).

---

### Task 9: Wallet — add/remove + `wm wallet` commands  ·  `[atômica]`

**Files:** Modify `internal/wallet/wallet.go` + `_test.go`; create `cmd/wallet.go`.

**Interfaces:** `wallet.Add(path, ticker string) error` (dedupe, uppercase, mkdir); `wallet.Remove(path, ticker string) error`.

**Concept to understand:** idempotent set writes, cobra subcommand tree.

- [ ] **Step 1: Failing test (append)**

```go
func TestAddRemove(t *testing.T) {
	p := filepath.Join(t.TempDir(), "sub", "wallet")
	must := func(err error) { if err != nil { t.Fatal(err) } }
	must(Add(p, "petr4"))
	must(Add(p, "PETR4")) // dedupe
	must(Add(p, "mxrf11"))
	must(Remove(p, "petr4"))
	got, _ := List(p)
	if want := []string{"MXRF11"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}
```

- [ ] **Step 2: fails → Step 3 implement (append to wallet.go)**

```go
func Add(path, ticker string) error {
	ticker = strings.ToUpper(strings.TrimSpace(ticker))
	cur, err := List(path)
	if err != nil {
		return err
	}
	for _, t := range cur {
		if t == ticker {
			return nil
		}
	}
	return write(path, append(cur, ticker))
}

func Remove(path, ticker string) error {
	ticker = strings.ToUpper(strings.TrimSpace(ticker))
	cur, err := List(path)
	if err != nil {
		return err
	}
	out := []string{}
	for _, t := range cur {
		if t != ticker {
			out = append(out, t)
		}
	}
	return write(path, out)
}

func write(path string, tickers []string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Join(tickers, "\n")+"\n"), 0o644)
}
```

- [ ] **Step 4: `cmd/wallet.go`**

```go
package cmd

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	walletCmd := &cobra.Command{Use: "wallet", Short: "manage held tickers"}
	walletCmd.AddCommand(&cobra.Command{
		Use: "list", Short: "list tickers",
		RunE: func(_ *cobra.Command, _ []string) error {
			ts, err := wallet.List(wallet.Path())
			if err != nil {
				return err
			}
			for _, t := range ts {
				fmt.Println(t)
			}
			return nil
		},
	})
	walletCmd.AddCommand(&cobra.Command{
		Use: "add TICKER", Short: "add a ticker", Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, a []string) error { return wallet.Add(wallet.Path(), a[0]) },
	})
	walletCmd.AddCommand(&cobra.Command{
		Use: "remove TICKER", Short: "remove a ticker", Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, a []string) error { return wallet.Remove(wallet.Path(), a[0]) },
	})
	rootCmd.AddCommand(walletCmd)
}
```

- [ ] **Step 4b: Flow test the wallet commands** (`cmd/wallet_test.go`)

```go
package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWalletCommands(t *testing.T) {
	wf := filepath.Join(t.TempDir(), "wallet")
	t.Setenv("WATCHMAN_WALLET", wf)

	rootCmd.SetArgs([]string{"wallet", "add", "petr4"})
	if err := rootCmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(wf); string(data) != "PETR4\n" {
		t.Fatalf("wallet file = %q", string(data))
	}
}
```

- [ ] **Step 5: Verify + commit**

```bash
go test ./internal/wallet/ ./cmd/ -v
go build -o wm . && ./wm wallet add PETR4 && ./wm wallet list
git add internal/wallet cmd/wallet.go cmd/wallet_test.go && git commit -m "feat(wallet): add/remove + wm wallet commands + flow test"
```

**✅ Done when:**
- `go test ./internal/wallet/ ./cmd/ -v` → wallet unit tests + `cmd.TestWalletCommands` (`wm wallet add petr4` → file contains `PETR4`) PASS (add dedupes, remove drops).
- `./wm wallet add PETR4 && ./wm wallet add petr4 && ./wm wallet list` → `PETR4` once; then `./wm wallet remove PETR4 && ./wm wallet list` → empty.

---

### Task 10: Prices — parse Yahoo JSON (pure)  ·  `[atômica]`

**Files:** Create `internal/prices/prices.go`, `_test.go`.

**Interfaces:** `prices.Parse(body []byte) ([]float64, error)` — closes oldest→newest, nils dropped; error payload → `ErrNoData`.

**Concept to understand:** json struct tags, `*float64` to tell `null` from `0.0`, parse isolated from HTTP.

- [ ] **Step 1: Failing test**

```go
package prices

import (
	"reflect"
	"testing"
)

const fixture = `{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10.0,10.5,null,11.0]}]}}]}}`

func TestParse(t *testing.T) {
	got, err := Parse([]byte(fixture))
	if err != nil {
		t.Fatal(err)
	}
	if want := []float64{10.0, 10.5, 11.0}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestParseError(t *testing.T) {
	if _, err := Parse([]byte(`{"chart":{"error":"Not Found","result":null}}`)); err != ErrNoData {
		t.Fatalf("want ErrNoData got %v", err)
	}
}
```

- [ ] **Step 2: fails → Step 3 implement**

```go
// Package prices fetches trailing daily closes from Yahoo Finance (B3 via ".SA").
package prices

import (
	"encoding/json"
	"errors"
)

var ErrNoData = errors.New("no price data")

type chartResp struct {
	Chart struct {
		Error  interface{} `json:"error"`
		Result []struct {
			Indicators struct {
				Quote []struct {
					Close []*float64 `json:"close"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
	} `json:"chart"`
}

func Parse(body []byte) ([]float64, error) {
	var r chartResp
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, err
	}
	if r.Chart.Error != nil {
		return nil, ErrNoData
	}
	if len(r.Chart.Result) == 0 || len(r.Chart.Result[0].Indicators.Quote) == 0 {
		return nil, ErrNoData
	}
	out := []float64{}
	for _, c := range r.Chart.Result[0].Indicators.Quote[0].Close {
		if c != nil {
			out = append(out, *c)
		}
	}
	return out, nil
}
```

- [ ] **Step 4: pass → commit** — `git add internal/prices && git commit -m "feat(prices): parse Yahoo close history"`

**✅ Done when:**
- `go test ./internal/prices/ -v` → `TestParse` (nils dropped → `[10, 10.5, 11]`) + `TestParseError` (→ `ErrNoData`) PASS.

---

### Task 11: Prices — HTTP fetch (thin)  ·  `[complexa]`

**Files:** Modify `internal/prices/prices.go`; add to `internal/prices/prices_test.go`.

**Interfaces:** `prices.History(ticker string) ([]float64, error)`; `prices.BaseURL` (overridable in tests).

**Concept to understand:** an injectable `BaseURL` is the seam that lets a flow test hit an `httptest.Server` instead of real Yahoo (no live network in tests); `User-Agent` (Yahoo blocks empty); `defer Body.Close()`.

- [ ] **Step 1: Implement with an injectable base URL**

```go
import (
	"fmt"
	"io"
	"net/http"
)

// BaseURL is overridable in tests (httptest); default = Yahoo Finance chart API.
var BaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

func History(ticker string) ([]float64, error) {
	url := fmt.Sprintf("%s/%s.SA?range=2mo&interval=1d", BaseURL, ticker)
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("User-Agent", "watchman/2.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return Parse(body)
}
```

- [ ] **Step 2: Flow test against httptest** (append to `internal/prices/prices_test.go`; reuses `fixture` from Task 10, same package)

```go
import (
	"net/http"
	"net/http/httptest"
)

func TestHistoryFlow(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("missing User-Agent")
		}
		w.Write([]byte(fixture))
	}))
	defer srv.Close()
	BaseURL = srv.URL

	got, err := History("PETR4")
	if err != nil || len(got) != 3 || got[2] != 11.0 {
		t.Fatalf("got %v err %v", got, err)
	}
}

func TestHistoryHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(500) }))
	defer srv.Close()
	BaseURL = srv.URL
	if _, err := History("PETR4"); err == nil {
		t.Fatal("want error on HTTP 500")
	}
}
```

- [ ] **Step 3: Run + commit**

```bash
go test ./internal/prices/ -v
git add internal/prices && git commit -m "feat(prices): fetch close history over HTTP + flow test"
```

**✅ Done when:**
- `go test ./internal/prices/ -v` → `TestParse`, `TestParseError`, `TestHistoryFlow` (httptest → `[10,10.5,11]`), `TestHistoryHTTPError` (500 → error) PASS. No real network in tests. (Live-run `429` from Yahoo = rate-limit, retry.)

---

### Task 12: Anomaly — z-score (pure)  ·  `[atômica]`

**Files:** Create `internal/anomaly/anomaly.go`, `_test.go`.

**Interfaces:** `anomaly.Analyze(closes []float64) (Result, error)`; `Result{Pct, Z float64; Abnormal bool}`; `<3` → `ErrInsufficient`; `Abnormal = |Z|>=2.0`.

**Concept to understand:** returns→mean→stddev→z; guard `sigma==0`. **Cross-check Z vs old `analysis/technical.ex` (spreadsheet-validated reference).**

- [ ] **Step 1: Failing test**

```go
package anomaly

import "testing"

func TestAbnormal(t *testing.T) {
	closes := make([]float64, 30)
	for i := range closes {
		closes[i] = 10.0
	}
	closes = append(closes, 13.0)
	r, err := Analyze(closes)
	if err != nil {
		t.Fatal(err)
	}
	if !r.Abnormal || r.Z <= 2.0 {
		t.Fatalf("got %+v", r)
	}
}

func TestCalm(t *testing.T) {
	closes := make([]float64, 40)
	for i := range closes {
		closes[i] = 10.0 + 0.01*float64(i%3)
	}
	if r, _ := Analyze(closes); r.Abnormal {
		t.Fatalf("got %+v", r)
	}
}

func TestInsufficient(t *testing.T) {
	if _, err := Analyze([]float64{10}); err != ErrInsufficient {
		t.Fatalf("got %v", err)
	}
}
```

- [ ] **Step 2: fails → Step 3 implement**

```go
// Package anomaly scores how unusual the latest daily move is vs recent returns.
package anomaly

import (
	"errors"
	"math"
)

const threshold = 2.0

var ErrInsufficient = errors.New("insufficient data")

type Result struct {
	Pct      float64
	Z        float64
	Abnormal bool
}

func Analyze(closes []float64) (Result, error) {
	if len(closes) < 3 {
		return Result{}, ErrInsufficient
	}
	returns := make([]float64, 0, len(closes)-1)
	for i := 1; i < len(closes); i++ {
		returns = append(returns, (closes[i]-closes[i-1])/closes[i-1]*100.0)
	}
	latest := returns[len(returns)-1]
	prior := returns[:len(returns)-1]
	mu := mean(prior)
	sigma := stddev(prior, mu)
	z := 0.0
	if sigma != 0 {
		z = (latest - mu) / sigma
	}
	return Result{Pct: latest, Z: z, Abnormal: math.Abs(z) >= threshold}, nil
}

func mean(xs []float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += x
	}
	return s / float64(len(xs))
}

func stddev(xs []float64, mu float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += (x - mu) * (x - mu)
	}
	return math.Sqrt(s / float64(len(xs)))
}
```

- [ ] **Step 4: pass → commit** — `git add internal/anomaly && git commit -m "feat(anomaly): z-score of latest move"`

**✅ Done when:**
- `go test ./internal/anomaly/ -v` → `TestAbnormal` (z>2), `TestCalm` (not abnormal), `TestInsufficient` (`ErrInsufficient`) PASS.
- Spot-check: the +30% jump's `Z` matches your reference `technical.ex` zscore within ±0.1.

---

### Task 13: Verdict — ignore/LOOK rule (pure)  ·  `[atômica]`

**Files:** Create `internal/verdict/verdict.go`, `_test.go`.

**Interfaces:** `verdict.Decide(a anomaly.Result, hasNews bool) Decision`; `Decision{Look bool; Reason string}`.

**Concept to understand:** ordered boolean `switch`; this rule IS the product — keep it one-breath explainable (the auditable/deterministic credibility point).

- [ ] **Step 1: Failing test (4 branches)**

```go
package verdict

import (
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/anomaly"
)

func TestDecide(t *testing.T) {
	calm := anomaly.Result{Pct: 0.3, Z: 0.4, Abnormal: false}
	wild := anomaly.Result{Pct: -6.1, Z: -2.8, Abnormal: true}
	cases := []struct {
		a    anomaly.Result
		news bool
		look bool
		must string
	}{
		{calm, false, false, "quiet"},
		{wild, false, true, "-6.1%"},
		{calm, true, true, "news"},
		{wild, true, true, "news"},
	}
	for _, c := range cases {
		d := Decide(c.a, c.news)
		if d.Look != c.look || !strings.Contains(d.Reason, c.must) {
			t.Fatalf("Decide(%+v,%v)=%+v want look=%v ~%q", c.a, c.news, d, c.look, c.must)
		}
	}
}
```

- [ ] **Step 2: fails → Step 3 implement**

```go
// Package verdict is the deterministic ignore/LOOK rule. You can read why it fired.
package verdict

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/anomaly"
)

type Decision struct {
	Look   bool
	Reason string
}

func Decide(a anomaly.Result, hasNews bool) Decision {
	move := fmt.Sprintf("%.1f%% (%.1fσ/30d)", a.Pct, a.Z)
	switch {
	case a.Abnormal && hasNews:
		return Decision{true, "moved " + move + " + fresh material news"}
	case hasNews:
		return Decision{true, "fresh material news"}
	case a.Abnormal:
		return Decision{true, "moved " + move + " vs 30d"}
	default:
		return Decision{false, "quiet (" + move + ")"}
	}
}
```

- [ ] **Step 4: pass → commit** — `git add internal/verdict && git commit -m "feat(verdict): deterministic ignore/LOOK rule"`

**✅ Done when:**
- `go test ./internal/verdict/ -v` → `TestDecide` PASS across all 4 branches (quiet→ignore; move-only/news-only/both→look, with the reason naming the cause).

---

### Task 14: Glance + `wm run` (price-only)  ·  `[complexa]`  ·  **MILESTONE**

**Files:** Create `internal/glance/glance.go`, `_test.go`, `internal/news/news.go` (stub), `cmd/run.go`.

**Interfaces:** `glance.BuildRow(ticker string, closes []float64, fetchErr error, hasNews bool) Row` (pure); `glance.Format(rows []Row) string` (pure); `glance.Run(tickers []string) []Row` (network); `Row{Ticker string; Look bool; Reason string}`.

**Concept to understand:** split pure (`BuildRow`/`Format`) from impure (`Run`); `strings.Builder`; cobra `run`.

- [ ] **Step 1: Failing test (pure)**

```go
package glance

import (
	"errors"
	"strings"
	"testing"
)

func TestBuildRowAbnormal(t *testing.T) {
	closes := make([]float64, 30)
	for i := range closes {
		closes[i] = 10.0
	}
	closes = append(closes, 13.0)
	if r := BuildRow("PETR4", closes, nil, false); !r.Look {
		t.Fatalf("want LOOK got %+v", r)
	}
}

func TestBuildRowFetchErr(t *testing.T) {
	r := BuildRow("XPTO3", nil, errors.New("x"), false)
	if r.Look || !strings.Contains(r.Reason, "no price") {
		t.Fatalf("got %+v", r)
	}
}

func TestFormat(t *testing.T) {
	out := Format([]Row{{"PETR4", true, "moved -6%"}, {"MXRF11", false, "quiet"}})
	if !strings.Contains(out, "LOOK") || !strings.Contains(out, "PETR4") || !strings.Contains(out, "MXRF11") {
		t.Fatalf("bad:\n%s", out)
	}
}
```

- [ ] **Step 2: news stub so it compiles** — `internal/news/news.go`

```go
package news

type Item struct{ Title, Date string }

func FetchItems() []Item                 { return nil }
func Fresh(string, []Item, string) bool  { return false }
```

- [ ] **Step 3: Implement `internal/glance/glance.go`**

```go
// Package glance assembles and formats the per-ticker ignore/LOOK output.
package glance

import (
	"fmt"
	"strings"
	"time"

	"github.com/carvalhosauro/watchman/internal/anomaly"
	"github.com/carvalhosauro/watchman/internal/news"
	"github.com/carvalhosauro/watchman/internal/prices"
	"github.com/carvalhosauro/watchman/internal/verdict"
)

type Row struct {
	Ticker string
	Look   bool
	Reason string
}

func BuildRow(ticker string, closes []float64, fetchErr error, hasNews bool) Row {
	if fetchErr != nil {
		return Row{ticker, false, "no price data"}
	}
	a, err := anomaly.Analyze(closes)
	if err != nil {
		return Row{ticker, false, "not enough price history"}
	}
	d := verdict.Decide(a, hasNews)
	return Row{ticker, d.Look, d.Reason}
}

func Run(tickers []string) []Row {
	items := news.FetchItems()
	today := time.Now().UTC().Format("2006-01-02")
	rows := make([]Row, 0, len(tickers))
	for _, t := range tickers {
		closes, err := prices.History(t)
		rows = append(rows, BuildRow(t, closes, err, news.Fresh(t, items, today)))
	}
	return rows
}

func Format(rows []Row) string {
	var b strings.Builder
	for _, r := range rows {
		if r.Look {
			fmt.Fprintf(&b, "  ⚠ LOOK   %-8s %s\n", r.Ticker, r.Reason)
		} else {
			fmt.Fprintf(&b, "    ignore %-8s %s\n", r.Ticker, r.Reason)
		}
	}
	return b.String()
}
```

- [ ] **Step 4: `cmd/run.go`**

```go
package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(&cobra.Command{
		Use: "run", Short: "fetch and show the noise/look glance",
		RunE: func(cmd *cobra.Command, _ []string) error {
			out := cmd.OutOrStdout() // testable: flow tests capture this
			ts, err := wallet.List(wallet.Path())
			if err != nil {
				return err
			}
			if len(ts) == 0 {
				fmt.Fprintln(out, "No tickers. Add with: wm wallet add PETR4")
				return nil
			}
			fmt.Fprintf(out, "watchman — %s\n", time.Now().UTC().Format("2006-01-02"))
			fmt.Fprint(out, glance.Format(glance.Run(ts)))
			return nil
		},
	})
}
```

- [ ] **Step 4b: Flow tests** — end-to-end with injected prices (news stub → nil, so price-only)

`internal/glance/glance_test.go` (append):
```go
import (
	"net/http"
	"net/http/httptest"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestRunFlow(t *testing.T) {
	body := `{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,13]}]}}]}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte(body)) }))
	defer srv.Close()
	prices.BaseURL = srv.URL

	rows := Run([]string{"PETR4"})
	if len(rows) != 1 || !rows[0].Look {
		t.Fatalf("got %+v", rows)
	}
}
```

`cmd/run_test.go` (new) — drive the cobra command, capture output:
```go
package cmd

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestRunCommand(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10,10,10,11]}]}}]}}`))
	}))
	defer srv.Close()
	prices.BaseURL = srv.URL

	wf := filepath.Join(t.TempDir(), "wallet")
	os.WriteFile(wf, []byte("PETR4\n"), 0o644)
	t.Setenv("WATCHMAN_WALLET", wf)

	var out bytes.Buffer
	rootCmd.SetOut(&out)
	rootCmd.SetArgs([]string{"run"})
	if err := rootCmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "PETR4") {
		t.Fatalf("output missing PETR4:\n%s", out.String())
	}
}
```

- [ ] **Step 5: Build + live milestone**

```bash
go test ./... && go build -o wm . && ./wm wallet add PETR4 && ./wm wallet add MXRF11 && ./wm run
```
Expected: two lines, `ignore`/`⚠ LOOK` + reason. **Working price-only glance — fallback line shipped.**

- [ ] **Step 6: Commit** — `git add internal/glance internal/news cmd/run.go && git commit -m "feat(glance): price-only run glance via wm run"`

**✅ Done when (MILESTONE):**
- `go test ./...` → all PASS, including `glance.TestRunFlow` (injected prices → abnormal → LOOK) and `cmd.TestRunCommand` (cobra `run` output contains the ticker). No real network in tests.
- `go build -o wm . && ./wm wallet add PETR4 && ./wm wallet add MXRF11 && ./wm run` → dated header + exactly one `ignore`/`⚠ LOOK …reason` line per held ticker, no crash. **Price-only glance works end-to-end.**

---

### Task 15: News — parse CVM feed + fresh? (pure)  ·  `[atômica]`

**Files:** Replace `internal/news/news.go`; create `_test.go`.

**Interfaces:** `news.ParseItems(body []byte) ([]Item, error)`; `news.Fresh(ticker string, items []Item, today string) bool`.

**Concept to understand:** `encoding/xml` tags (`xml:"channel>item"`), `time.Parse` RFC1123 + single-digit-day fallback, date as `"2006-01-02"`. Ticker substring match first; aliases (old `ticker_aliases.ex`) later.

- [ ] **Step 1: Failing test**

```go
package news

import "testing"

const xmlFix = `<rss><channel>
<item><title>PETR4 - Fato Relevante sobre dividendos</title><pubDate>Sat, 20 Jun 2026 09:00:00 GMT</pubDate></item>
<item><title>VALE3 - Comunicado</title><pubDate>Fri, 19 Jun 2026 18:00:00 GMT</pubDate></item>
</channel></rss>`

func TestParseAndFresh(t *testing.T) {
	items, err := ParseItems([]byte(xmlFix))
	if err != nil || len(items) != 2 {
		t.Fatalf("items=%v err=%v", items, err)
	}
	if items[0].Date != "2026-06-20" {
		t.Fatalf("date=%q", items[0].Date)
	}
	if !Fresh("PETR4", items, "2026-06-20") {
		t.Fatal("PETR4 should be fresh")
	}
	if Fresh("VALE3", items, "2026-06-20") || Fresh("ITUB4", items, "2026-06-20") {
		t.Fatal("only PETR4 fresh today")
	}
}
```

- [ ] **Step 2: fails → Step 3 implement**

```go
// Package news reads the CVM material-fact feed: fresh news for this ticker today?
package news

import (
	"encoding/xml"
	"strings"
	"time"
)

type Item struct {
	Title string
	Date  string // "2006-01-02"
}

type rss struct {
	Items []struct {
		Title   string `xml:"title"`
		PubDate string `xml:"pubDate"`
	} `xml:"channel>item"`
}

func ParseItems(body []byte) ([]Item, error) {
	var r rss
	if err := xml.Unmarshal(body, &r); err != nil {
		return nil, err
	}
	out := make([]Item, 0, len(r.Items))
	for _, it := range r.Items {
		out = append(out, Item{Title: it.Title, Date: parseDate(it.PubDate)})
	}
	return out, nil
}

func Fresh(ticker string, items []Item, today string) bool {
	for _, it := range items {
		if it.Date == today && strings.Contains(it.Title, ticker) {
			return true
		}
	}
	return false
}

func parseDate(pub string) string {
	for _, layout := range []string{time.RFC1123, "Mon, 2 Jan 2006 15:04:05 MST"} {
		if t, err := time.Parse(layout, pub); err == nil {
			return t.UTC().Format("2006-01-02")
		}
	}
	return ""
}
```

- [ ] **Step 4: pass → commit** — `git add internal/news && git commit -m "feat(news): parse CVM feed + per-ticker freshness"`

**✅ Done when:**
- `go test ./internal/news/ -v` → `TestParseAndFresh` PASS (2 items, date `2026-06-20`, `Fresh` true only for PETR4 today; VALE3/ITUB4 false).

---

### Task 16: News — fetch (thin) + flow test + wire into run  ·  `[complexa]`

**Files:** Modify `internal/news/news.go`; add to `internal/news/news_test.go`.

**Interfaces:** `news.FetchItems() []Item` — GET CVM feed, return `ParseItems` or `nil` on any failure (graceful). `news.FeedURL` overridable in tests. `glance.Run` already calls it — no change.

**Concept to understand:** graceful degradation (return `nil`, never error up); single fetch per run (no N+1); `FeedURL` seam for httptest flow testing.

- [ ] **Step 1: Implement (replace stub funcs)**

```go
import (
	"io"
	"net/http"
)

// FeedURL is overridable in tests (httptest).
// TODO: paste the exact CVM material-fact feed URL from reference lib/watchman/news/cvm.ex
var FeedURL = "REPLACE_WITH_CVM_FEED_URL"

func FetchItems() []Item {
	req, _ := http.NewRequest(http.MethodGet, FeedURL, nil)
	req.Header.Set("User-Agent", "watchman/2.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil
	}
	items, err := ParseItems(body)
	if err != nil {
		return nil
	}
	return items
}
```

> **Flagged marker:** replace `FeedURL`'s default with the real CVM feed URL from reference `cvm.ex`. Until then, `FetchItems` returns nil (glance still works, price-only).

- [ ] **Step 2: Flow test against httptest** (append to `internal/news/news_test.go`; reuses `xmlFix` from Task 15)

```go
import (
	"net/http"
	"net/http/httptest"
)

func TestFetchItemsFlow(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(xmlFix))
	}))
	defer srv.Close()
	FeedURL = srv.URL

	items := FetchItems()
	if len(items) != 2 || items[0].Date != "2026-06-20" {
		t.Fatalf("got %v", items)
	}
}

func TestFetchItemsGraceful(t *testing.T) {
	FeedURL = "http://127.0.0.1:0/bad"
	if items := FetchItems(); items != nil {
		t.Fatalf("want nil on failure, got %v", items)
	}
}
```

- [ ] **Step 3: Live check + commit**

```bash
go test ./internal/news/ -v
go build -o wm . && ./wm run   # with a real FeedURL: a fato-relevante ticker shows "fresh material news"
git add internal/news && git commit -m "feat(news): fetch CVM feed + flow test, wire into run"
```

**✅ Done when:**
- `go test ./internal/news/ -v` → `TestParseAndFresh`, `TestFetchItemsFlow` (httptest → 2 items, date `2026-06-20`), `TestFetchItemsGraceful` (bad host → nil, no panic) PASS — no real network.
- With a real `FeedURL`: `./wm run` shows `… fresh material news` for a ticker with a fato relevante today.

---

### Task 17: Phase A polish — README + changelog + first release  ·  `[atômica]`

**Files:** `README.md`, `CHANGELOG.md` (via git-cliff); git tag.

**Concept to understand:** the Phase 0 pipeline turns a tag into published binaries; this task is the first real exercise of it.

- [ ] **Step 1: Rewrite `README.md`** — what `wm` is; `wm wallet add/list/remove`, `wm run`; install (download release binary or `go install`); the deterministic rule (abnormal move OR fresh CVM news → LOOK); autocomplete (`wm completion bash|zsh`, cobra-generated); "what it doesn't do" (no advice, no DB, no alerts/schedule/history yet).
- [ ] **Step 2: Gates green, regenerate changelog**

```bash
make ci          # fmt + lint + cover(70) + build, all green
git cliff -o CHANGELOG.md
git add README.md CHANGELOG.md && git commit -m "docs: README + CHANGELOG for v2.0.0-mvp"
```

- [ ] **Step 3: Tag → triggers the release workflow**

```bash
git tag v2.0.0-mvp && git push origin v2-go --tags
```
Expected: `release.yml` runs GoReleaser → GitHub Release with `wm_linux_amd64.tar.gz` etc. + `checksums.txt`. Verify the assets exist.

**✅ Done when:**
- `make ci` → green (gofmt clean, golangci-lint clean, coverage ≥80%, build ok).
- `git tag v2.0.0-mvp && git push origin v2-go --tags` → `release.yml` publishes a GitHub Release with `wm_{linux,darwin}_{amd64,arm64}.tar.gz` + `checksums.txt`.

---

## Self-Review (against MVP spec + your feature list + Phase-0 ask)

- **Phase 0 ask covered:** env reset T1 · formatter+linter T3 · coverage gate T4 · pre-commit T5 · conventional commits T5 · changelog T6 · releases/tags/distribution T7 · CI guardrails T7. All present.
- **MVP IN covered:** wallet CRUD T8–T9 · price source+anomaly T10–T12 · fresh CVM news T15–T16 · verdict T13 · one run command T14 · price-only fallback = T14 milestone.
- **Feature-list mapping:** "carteira" T8–T9 · "executar" T14 · autocomplete = cobra free (documented T17) · History/Schedule/Update = **Phase B** (deferred per "value core first").
- **OUT honored:** no DB/AI/alerts/weighting/feedback/4-level/provider-abstraction in Phase A.
- **Type consistency:** `prices.History→([]float64,error)` ⇒ `glance.BuildRow`; `anomaly.Result{Pct,Z,Abnormal}` ⇒ `verdict.Decide`; `news.Item{Title,Date}`+`Fresh(string,[]Item,string)` stable T14 stub → T15/T16. `cmd.version` injected by ldflags (T1) and GoReleaser (T7) match.
- **Flagged placeholder:** `feedURL` (T16) — intentional, paste from reference `cvm.ex`.

---

## Phase B — product shell (roadmap, detail after value signal)

- **History** — append NDJSON per `wm run` to `~/.config/watchman/history.ndjson`; `wm history [-n N]`. No DB. (~2 tasks)
- **Schedule** — `wm schedule --every 1h` writes a systemd user timer / cron calling `wm run`; `wm unschedule`. Not a daemon. (~2 tasks)
- **Update / auto-update** — `wm update`: GitHub Releases API vs embedded `version` → download `wm_<os>_<arch>` asset → atomic self-replace. Auto-check on `run` (throttled, opt-out). Pipeline already exists (T7). Consider `minio/selfupdate`. (~3 tasks)
- **Autocomplete polish** — ship `wm completion` install step in the binary installer. (~1 task)

---

## Execution Handoff

Plan saved. Default = **option 3** (credibility goal = explain every line):

1. **Subagent-Driven** — AI writes each task. ⚠️ Recreates "code I didn't write." Not recommended.
2. **Inline (this session)** — I execute with checkpoints. Faster, still AI-authored.
3. **You author, AI tutors/reviews (recommended)** — you type each task from the code + "Concept to understand"; I review your Go after each (Opus xhigh) + answer concept questions. You own every line.

Which approach?
