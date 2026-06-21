# watchman → Go OSS Standard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Model routing:** Plan = Opus xhigh | Exec atômica = Sonnet high | Exec complexa = Opus xhigh | Review = Opus xhigh | Final = Opus xhigh

**Goal:** Bring `wm` to the conventions Go OSS contributors expect — tests that run inside `go test ./...`, the community-health files GitHub scores, cross-platform CI + distribution — so the repo "looks like the ones contributors already know" before the first public release.

**Architecture:** No product behavior changes. Work is in test harness (bash/python e2e → `testscript` txtar driven by a Go `httptest` mock), repo metadata (CoC/SECURITY/badges/labels/dependabot/CODEOWNERS), CI workflows (OS matrix + govulncheck), and GoReleaser (Windows + completions/man + optional Homebrew tap). Source under `internal/` and `cmd/` is untouched except a tiny exit-code entrypoint seam.

**Tech Stack:** Go 1.22+, cobra, `rogpeppe/go-internal/testscript`, GoReleaser v2, GitHub Actions, golangci-lint v2, git-cliff. Static binary (`CGO_ENABLED=0`).

---

## Global Constraints

- **No product behavior change.** Every existing unit/cobra/httptest test stays green; the verdict/anomaly/wallet logic is not touched.
- **One entrypoint.** After Phase A, `go test ./...` runs unit + in-process cobra + black-box txtar. No test requires bash or python.
- **Every commit passes the gates** (gofmt, golangci-lint, `go test`, coverage ≥80) — `.githooks` locally, CI on PR. Conventional Commits; one commit per task.
- **Coverage floor stays 80.** The txtar suite is additive; the floor is satisfied by the existing unit + in-process cobra tests, so porting must not drop any in-process coverage.
- **Module path:** `github.com/carvalhosauro/watchman`. **Binary:** `wm`. **Branch:** `v2-go` (local; no push without explicit user go-ahead).

**Milestone (release-ready line):** after **Phase C** the repo is testable cross-platform inside `go test`, has the community-health files GitHub scores, and CI runs the OS matrix + a vuln scan — i.e. it meets "padrão OSS" for a first release. Phases D–E are reach/polish.

---

## Decisions & external actions required (non-code gates)

These are **not tasks**; they need a human call. Surface them; don't guess.

- **D1 — License.** Ecosystem norm is MIT/Apache-2.0 (gh/gum/glow MIT; k9s/dnote Apache-2.0); watchman is GPL-2.0-only. Keep GPL (copyleft, deliberate) or relicense for broader corporate adoption? **Default: keep GPL-2.0** unless the user says otherwise. No task changes the license without D1.
- **D2 — Homebrew tap (Task D3).** Requires a separate public repo `carvalhosauro/homebrew-tap` + a `HOMEBREW_TAP_GITHUB_TOKEN` (or reuse `GITHUB_TOKEN` with cross-repo PAT) secret in the watchman repo. Task D3 writes the GoReleaser `brews:` block but is **gated** on the user creating the tap repo + secret. If not ready, D3 ships disabled/commented.
- **D3 — `good first issue` labels + starter issues (Task E4).** Creating labels and issues happens on GitHub (via `gh`), not in the repo tree. Task E4 produces the label set + 3 drafted starter issues; the user (or an authorized `gh` run) applies them.

---

## Phase A — Tests to the Go standard (P0)

> Replace the bash+python e2e with `testscript` (.txtar) driven by a Go `httptest` mock, so true-binary black-box flows run inside `go test ./...`, cross-platform, no external interpreter. Keep all existing in-process tests.

### Task A1: Add testscript dependency + exit-code entrypoint seam · `[atômica]`

**Objective:** Make `cmd` invocable as a testscript command and vendor the dep, without changing CLI behavior.

**Files:** `go.mod`, `go.sum`, `cmd/root.go` (add `func Run() int`), `cmd/wm/main.go` (use it).

- [ ] `go get github.com/rogpeppe/go-internal@latest` (testscript).
- [ ] In `cmd/root.go` add `func Run() int { if err := rootCmd.Execute(); err != nil { return 1 }; return 0 }`; keep `Execute()` delegating to it (`if Run() != 0 { os.Exit(1) }`) so existing callers/tests are unaffected.
- [ ] `cmd/wm/main.go` → `func main() { os.Exit(cmd.Run()) }`.
- [ ] `go mod tidy`.

**Acceptance criteria:**
- `go build -o bin/wm ./cmd/wm` succeeds; `./bin/wm --version` and `./bin/wm wallet list` behave exactly as before.
- `go test ./...` stays green; coverage ≥80.
- `go.mod` requires `github.com/rogpeppe/go-internal`; `golangci-lint run` clean.

### Task A2: Go test-fixture mock server (port of mock_server.py) · `[complexa]`

**Objective:** A reusable in-process `httptest`-style mock returning deterministic price/news fixtures by request path, so txtar (and any Go test) can drive `wm run` with no real network.

**Files:** `cmd/wm/mock_test.go` (test-only helper, package `main`).

- [ ] `newMockServer(t)` returns an `*httptest.Server` whose handler routes by path:
  - contains `news` → RSS with one `VALE3 - Fato Relevante` item dated **today UTC** (RFC1123).
  - contains `PETR4` → JSON closes `[10]*30 + [13]` (abnormal → LOOK).
  - contains `XPTO3` → Yahoo error payload (`"error":"Not Found"` → no price data).
  - else (MXRF11, VALE3, …) → calm series `[10,10.1]*20` (|z|<2 → ignore).
- [ ] Today's date computed at request time (`time.Now().UTC()`), so freshness always matches the run day.

**Acceptance criteria:**
- A throwaway Go test that points `prices.BaseURL`/`news.FeedURL` at the mock and calls `glance.Run([...])` yields PETR4→Look, MXRF11→!Look, VALE3→Look(news), XPTO3→!Look("no price data"). (This assertion may live temporarily in A3's harness.)
- `gofmt`/`golangci-lint` clean; no real network.

### Task A3: testscript harness + TestMain · `[complexa]`

**Objective:** Wire `testscript` so `wm` runs as an in-process command and every `.txtar` under `cmd/wm/testdata/script/` executes with the mock URLs and an isolated wallet injected via env.

**Files:** `cmd/wm/script_test.go`.

- [ ] `TestMain` registers `wm` via `testscript.RunMain(m, map[string]func() int{"wm": cmd.Run})`.
- [ ] `TestScripts(t)` starts the A2 mock, then `testscript.Run(t, Params{Dir: "testdata/script", Setup: ...})` where `Setup` sets `WATCHMAN_PRICES_URL`, `WATCHMAN_NEWS_URL` (→ mock), and `WATCHMAN_WALLET` (→ `$WORK/wallet`).

**Acceptance criteria:**
- `go test ./cmd/wm/ -run TestScripts` discovers and runs txtar files (passes once A4 adds them).
- The mock is closed on test end (no leaked goroutine/port); `go test -race ./cmd/wm/` clean.

### Task A4: Port deterministic flows to .txtar · `[complexa]`

**Objective:** Reproduce the bash suite's coverage (CLI surface, wallet CRUD/edge cases, full `run` glance) as black-box txtar scripts.

**Files:** `cmd/wm/testdata/script/{cli,wallet,run}.txtar`.

- [ ] `cli.txtar`: `wm --version` (stdout matches `version`); `wm --help` (lists wallet/run/completion); unknown command exits non-zero (`! wm bogus`); `wm completion bash|zsh|fish|powershell` each exit 0 and emit the shell name.
- [ ] `wallet.txtar`: add/list/dedupe/uppercase/trim; comments+blank lines skipped; remove drops; remove-nonexistent is a no-op exit 0; `! wm wallet add` (needs 1 arg); `! wm wallet add A B`; wallet file content assertions via `cmp`.
- [ ] `run.txtar`: seed `WATCHMAN_WALLET` with `PETR4\nMXRF11\nVALE3\nXPTO3`; `wm run`; assert dated header, PETR4→`LOOK`+`moved`, MXRF11→`ignore`+`quiet`, VALE3→`LOOK`+`news`, XPTO3→`ignore`+`no price data`; empty-wallet case prints the `No tickers` hint.

**Acceptance criteria:**
- `go test ./cmd/wm/ -run TestScripts` → all three txtar pass, deterministic, no real network.
- Each assertion from the old `test/e2e/e2e.sh` has an equivalent in txtar (CLI surface, wallet edge cases, the 4-ticker glance, empty-wallet hint). The graceful "upstream down" case stays covered by the existing in-process `cmd/run_test.go` (no txtar duplication).

### Task A5: Port the live smoke to a tagged Go test · `[atômica]`

**Objective:** Keep the real-network smoke as an opt-in Go test (not a shell script), runnable via `go test -tags live`.

**Files:** `cmd/wm/live_test.go` (`//go:build live`).

- [ ] In-process drive `wm run` against the **real** Yahoo/CVM (no env override), wallet seeded `PETR4\nITUB4\nXPTO3INVALID`; tolerant asserts: exit 0, dated header, one verdict line per ticker (LOOK|ignore), tolerant of 429 → "no price data".

**Acceptance criteria:**
- `go test -tags live ./cmd/wm/` runs the smoke and passes (network permitting); `go test ./...` (no tag) **does not** run it.

### Task A6: Remove bash/python e2e + repoint Makefile/CI · `[atômica]`

**Objective:** Delete the non-idiomatic suite and make `go test` / `make` the single path.

**Files:** delete `test/e2e/lib.sh`, `test/e2e/e2e.sh`, `test/e2e/live_smoke.sh`, `test/e2e/mock_server.py`; `Makefile`; `.github/workflows/ci.yml` (if it referenced e2e — it does not currently).

- [ ] Remove `make e2e` / `e2e-live` bash targets; add `smoke: ## run live network smoke` → `go test -tags live -count=1 ./cmd/wm/`.
- [ ] Confirm `make test` (`go test -race ./...`) now includes the txtar suite.

**Acceptance criteria:**
- `test/e2e/` no longer contains shell/python files; `git grep -nE 'python3|\.sh' -- test/` is empty.
- `make test` runs unit + cobra + txtar green; `make smoke` runs the tagged live test; `make ci` green (gofmt, lint, coverage ≥80, build).
- No reference to the deleted scripts remains in README/Makefile/CI/docs.

---

## Phase B — Community-health files (P1)

### Task B1: CODE_OF_CONDUCT.md (Contributor Covenant) · `[atômica]`

**Objective:** Add the most widely adopted CoC so GitHub's community profile scores it and the project reads as welcoming.

**Files:** `CODE_OF_CONDUCT.md`.

- [ ] Contributor Covenant v2.1 verbatim; enforcement contact = the maintainer's real email (ask if unknown; placeholder flagged otherwise).

**Acceptance criteria:**
- File at repo root, Contributor Covenant 2.1, with a working contact in the Enforcement section.
- README/CONTRIBUTING link to it.

### Task B2: SECURITY.md · `[atômica]`

**Objective:** A vuln-reporting policy surfaced in the GitHub Security tab.

**Files:** `SECURITY.md`.

- [ ] Supported versions (the latest minor) + how to report privately (GitHub private vulnerability reporting and/or email); response-time expectation.

**Acceptance criteria:**
- File at root (or `.github/`); states supported versions + a private reporting channel; no secrets/PII.

### Task B3: README badges · `[atômica]`

**Objective:** Health-signal badges at the top of the README.

**Files:** `README.md`.

- [ ] Add the 5-badge block (pkg.go.dev, CI, Release, License, Go Version) from the report. **Omit Go Report Card** (goreportcard.com shutting down 2026-07-01).

**Acceptance criteria:**
- Five badges render; each links correctly (CI → `actions/workflows/ci.yml`, Release → `/releases/latest`, License → `./LICENSE`, Go Version → `./go.mod`, Reference → pkg.go.dev module path).
- `gofmt`/lint unaffected; markdown valid.

---

## Phase C — CI / security hardening (P1)  ·  **MILESTONE: release-ready**

### Task C1: Cross-OS test job · `[complexa]`

**Objective:** Run the suite on ubuntu+macos+windows, mirroring gh/charm, so cross-platform breakage is caught before release.

**Files:** `.github/workflows/ci.yml`.

- [ ] Split into jobs: keep `check` (ubuntu) = gofmt + golangci-lint + `coverage.sh 80` (race) + build. Add `test` job with `strategy.matrix.os: [ubuntu-latest, macos-latest, windows-latest]` running `go test ./...` (use `shell: bash` only where needed; `-race` on ubuntu/macos, plain `go test` on windows to avoid the CGO/gcc race requirement, or document that windows-latest ships gcc and keep -race).
- [ ] Ensure the txtar suite passes on Windows (paths via `filepath`, the mock uses `httptest` — both portable).

**Acceptance criteria:**
- CI YAML parses; the `test` job is defined for all three OS and runs `go test ./...`.
- The txtar suite is OS-agnostic (no hardcoded `/` paths, no bash assumptions in Go tests).
- `check` job still enforces gofmt/lint/coverage80/build on ubuntu.

### Task C2: govulncheck job · `[atômica]`

**Objective:** A dependency/stdlib vulnerability scan in CI (charm/gh standard).

**Files:** `.github/workflows/ci.yml` (or a new `govulncheck.yml`).

- [ ] Add a job: `setup-go` (version from go.mod) → `go install golang.org/x/vuln/cmd/govulncheck@latest` → `govulncheck ./...`.

**Acceptance criteria:**
- CI runs `govulncheck ./...`; job passes on the current tree (no known vulns) and would fail on an introduced vulnerable dep.

---

## Phase D — Distribution reach (P1/P2)

### Task D1: GoReleaser Windows builds · `[atômica]`

**Objective:** Ship Windows binaries (zip), matching the standard cross-platform matrix.

**Files:** `.goreleaser.yaml`.

- [ ] Add `windows` to `builds.goos`; add `archives.format_overrides` → `formats: [zip]` for `goos: windows`.

**Acceptance criteria:**
- `goreleaser check` valid; `goreleaser release --snapshot --clean && ls dist/` produces `wm_windows_amd64.zip` + `wm_windows_arm64.zip` alongside the existing linux/darwin tar.gz and `checksums.txt`.

### Task D2: Bundle completions + man pages in archives · `[complexa]`

**Objective:** Ship shell completions and a man page inside the release archives (cobra `doc.GenManTree` + completion generation), so package managers and users get them.

**Files:** `cmd/wm/gen_docs.go` or a `make` recipe + `.goreleaser.yaml` (`builds.hooks`/`before.hooks` + `archives.files`).

- [ ] Generate `completions/wm.{bash,zsh,fish}` and `manpages/wm.1` at release time (cobra `GenBashCompletionV2`/`GenZshCompletion`/`GenFishCompletion` + `doc.GenManTree`), e.g. a `cmd/gen-docs` helper invoked by a GoReleaser `before.hook` or `make gen-docs`.
- [ ] `archives.files` includes `completions/*` and `manpages/*` (+ `LICENSE`, `README.md`).

**Acceptance criteria:**
- `make gen-docs` (or the release hook) writes the four artifacts; `goreleaser release --snapshot --clean` archives contain `completions/` + `manpages/wm.1` + LICENSE + README.
- Generated files are git-ignored (built artifacts), or a documented committed copy — pick one and apply consistently.

### Task D3: Homebrew tap (GATED on D2 decision) · `[atômica]`

**Objective:** A `brew install carvalhosauro/tap/wm` path via GoReleaser `brews:`.

**Files:** `.goreleaser.yaml`.

- [ ] Add a `brews:` block targeting `carvalhosauro/homebrew-tap`, with `install` wiring the binary + completions + man page, and a `test: system "#{bin}/wm --version"`.
- [ ] **Gate:** requires the external `homebrew-tap` repo + token secret (Decision D2). If not provisioned, ship the block commented with a TODO referencing this task.

**Acceptance criteria:**
- `goreleaser check` valid with the block present.
- If the tap repo + secret exist: a snapshot/dry-run renders a valid `wm.rb` formula. If not: the block is clearly commented as pending external setup, and `goreleaser check` still passes.

---

## Phase E — Dev ergonomics & contributor on-ramp (P2)

### Task E1: Self-documenting `make help` · `[atômica]`

**Objective:** `make` / `make help` prints the available targets (k9s pattern).

**Files:** `Makefile`.

- [ ] Add `.DEFAULT_GOAL := help` + a `help:` target (grep/awk over `## ` comments); annotate each target with `## description`.

**Acceptance criteria:**
- bare `make` and `make help` print a formatted target list with descriptions; all existing targets still run.

### Task E2: dependabot.yml · `[atômica]`

**Objective:** Automated weekly dependency PRs for gomod + github-actions.

**Files:** `.github/dependabot.yml`.

- [ ] Two ecosystems (`gomod`, `github-actions`), weekly schedule, `chore` commit prefix.

**Acceptance criteria:**
- Valid dependabot schema (parses); covers both ecosystems on a weekly cadence.

### Task E3: CODEOWNERS · `[atômica]`

**Objective:** Route reviews to the maintainer.

**Files:** `.github/CODEOWNERS`.

- [ ] `* @carvalhosauro` (confirm the GitHub handle).

**Acceptance criteria:**
- File present; the owner handle is the real maintainer; GitHub recognizes it (valid syntax).

### Task E4: good-first-issue label set + starter issues (GATED, see D3) · `[atômica]`

**Objective:** Lower the contribution barrier with curated starter work that GitHub auto-surfaces on `/contribute`.

**Files:** `docs/contributing/starter-issues.md` (drafts; the labels/issues are applied on GitHub, not in-tree).

- [ ] Define labels `good first issue`, `help wanted`; draft 3 small, self-contained starter issues (e.g. "add ticker alias support", "add `wm history` skeleton", "improve `no price data` message").

**Acceptance criteria:**
- A doc lists the label names + 3 drafted issues (title + body + acceptance) ready to paste/`gh issue create`. Application to GitHub is a user/`gh` action, not a repo change.

---

## Phase F — Final review

### Task F1: Full-suite + community-profile verification · `[complexa]`

**Objective:** Confirm the repo meets "padrão OSS" and nothing regressed.

- [ ] `make ci` green; `go test ./...` green incl. txtar; `go test -tags live ./cmd/wm/` (network permitting).
- [ ] `goreleaser check` + snapshot produces linux/darwin/windows archives + checksums (+ completions/man if D2 done).
- [ ] Manual community-profile pass: README badges, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, issue+PR templates, dependabot, CODEOWNERS all present.
- [ ] Opus review pass over the full diff: no behavior change to wallet/anomaly/verdict/glance; no dead refs to deleted e2e; CI YAML valid.

**Acceptance criteria:**
- All gates green; GitHub community-standards checklist would be 100% (README, LICENSE, CONTRIBUTING, CoC, SECURITY, issue templates, PR template).
- Reviewer sign-off recorded; the only open items are the explicitly-gated external actions (D1 license, D2 tap repo+secret, E4 label/issue creation).

---

## Task summary

| Phase | Task | Tag | Gated? |
|---|---|---|---|
| A | A1 testscript dep + `cmd.Run()` seam | atômica | |
| A | A2 Go mock server (port mock_server.py) | complexa | |
| A | A3 testscript harness + TestMain | complexa | |
| A | A4 port flows → .txtar | complexa | |
| A | A5 live smoke → `-tags live` Go test | atômica | |
| A | A6 remove bash/python + repoint Makefile/CI | atômica | |
| B | B1 CODE_OF_CONDUCT.md | atômica | |
| B | B2 SECURITY.md | atômica | |
| B | B3 README badges | atômica | |
| C | C1 cross-OS test job | complexa | |
| C | C2 govulncheck job | atômica | |
| D | D1 GoReleaser Windows | atômica | |
| D | D2 completions + man in archives | complexa | |
| D | D3 Homebrew tap | atômica | D2 (repo+secret) |
| E | E1 `make help` | atômica | |
| E | E2 dependabot.yml | atômica | |
| E | E3 CODEOWNERS | atômica | |
| E | E4 starter issues + labels | atômica | GitHub apply |
| F | F1 final review | complexa | |

**Recommended order:** A (testing) → B (files) → C (CI) = release-ready milestone; then D → E (reach/polish) → F. Phases B and E's atomic file-adds can run in parallel with A if executed by separate agents.
