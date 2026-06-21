# watchman vs. the Go OSS CLI standard — gap report

> Date: 2026-06-21 · Branch: `v2-go` · Goal: bring `wm` to the conventions the Go
> community expects, so adoption and contribution are frictionless.
>
> Method: surveyed how real, popular Go CLIs are structured and tested —
> `cli/cli` (gh), `goreleaser/goreleaser`, `charmbracelet/gum` & `glow`,
> `derailed/k9s`, `dnote/dnote`, `spf13/cobra` — plus official GitHub/Go docs.
> Citations inline.

## TL;DR

watchman's **Go code, layout, and tooling are already idiomatic** (cobra + `cmd/wm`
entry + `internal/` packages + table/httptest/cobra-buffer tests + golangci-lint +
GoReleaser + Conventional Commits + git-cliff). Three categories need work:

1. **Testing style** — the bash+python e2e suite is the one clear non-idiomatic
   choice. Go projects keep everything inside `go test ./...`. Port it to
   **`testscript` (.txtar)** — the de-facto Go CLI integration-test tool.
2. **Community-health files** — missing `CODE_OF_CONDUCT.md`, `SECURITY.md`,
   README badges, and contributor on-ramps (`good first issue`, `make help`).
3. **Distribution reach** — GoReleaser ships only linux/darwin tarballs; the
   standard adds Windows, completions+man pages in archives, and a Homebrew tap.

Nothing here blocks a first release. It's the difference between "works" and
"a contributor lands in a repo that looks exactly like the ones they already know."

---

## 1. Testing — the core question

### Is bash+python e2e the Go market standard? No.

Across every project surveyed, CLI testing lives **inside `go test`**. Not one uses
shell+python end-to-end scripts. The idiomatic toolbox:

| Technique | What | Who uses it |
|---|---|---|
| Table-driven unit tests, colocated `*_test.go` | pure logic | universal |
| **cobra in-process** (`cmd.SetArgs` + `cmd.SetOut(buf)` + `Execute()`) | command flows, assert on a `bytes.Buffer` | universal; watchman already does this |
| **`net/http/httptest`** + httpmock helpers | network | cli/cli `pkg/httpmock`; watchman already does this |
| **`testscript` (.txtar)** — `rogpeppe/go-internal` | black-box CLI: run the binary, match stdout/files, set env | Go toolchain `cmd/go`, **cli/cli `acceptance/*.txtar`**, GoReleaser, Caddy, mvdan/sh |
| **Golden files** — `testdata/*.golden` + `-update` flag | snapshot large output | cli/cli, hugo |
| CI: `go test -race ./...` on **ubuntu+macos+windows** | + govulncheck (gh, charm), CodeQL (gh) | gh, charm, goreleaser |

Sources: cli/cli layout & acceptance tests
<https://github.com/cli/cli/blob/trunk/docs/project-layout.md>,
<https://github.com/cli/cli/tree/trunk/acceptance>,
<https://github.com/cli/cli/tree/trunk/pkg/httpmock>;
testscript <https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript>;
gh CI <https://github.com/cli/cli/blob/trunk/.github/workflows/go.yml>.

### Why Go devs avoid shell e2e (the trade-offs they cite)

- **One entrypoint.** `go test ./...` must run *everything*. A separate
  `bash test/e2e/*.sh` is invisible to contributors and to `go test`-based CI.
- **Cross-platform.** GoReleaser ships darwin (and the standard adds Windows).
  bash+`python3` aren't guaranteed there; tests that only run on Linux under-test
  the matrix.
- **No coverage credit.** Out-of-process binary runs don't count toward the
  coverage gate; the in-process cobra tests do.
- **No extra runtime deps.** Requiring `python3` to run the suite is contributor
  friction. `testscript` needs only the Go toolchain.

### What this means for watchman specifically

- `cmd/run_test.go` **already** drives `wm run` in-process with httptest + the env
  seams — that *is* the standard, and it already covers the verdict pipeline
  deterministically. The bash suite largely **duplicates** it out-of-process.
- The genuinely new thing the bash suite adds is *true-binary* black-box coverage
  (real arg parsing, real `completion`, exit codes). That is exactly
  **testscript's** job, and watchman's three env seams
  (`WATCHMAN_WALLET`, `WATCHMAN_PRICES_URL`, `WATCHMAN_NEWS_URL`) make it a clean
  fit: a `.txtar` sets env, runs `wm`, and matches output — no python mock needed
  if the mock is a tiny Go `httptest` started by a test-local helper, or the txtar
  asserts the offline/graceful path.

**Recommendation:** replace `test/e2e/*.sh` + `mock_server.py` with
`testscript` txtar files under `cmd/wm/testdata/script/` (or `acceptance/`),
driven by a `TestMain`/`testscript.Run` harness. Keep the existing in-process
cobra tests. Net effect: `go test ./...` covers unit + integration + true-binary,
cross-platform, coverage-counted, zero non-Go deps.

---

## 2. Project structure — already idiomatic ✓

| Dimension | Standard (gh, dive, gum, dnote) | watchman | Verdict |
|---|---|---|---|
| `package main` location | `cmd/<name>/main.go` (gh `cmd/gh`, dive `cmd/dive`) or repo root (gum, glow) | `cmd/wm/main.go` | ✓ matches |
| Private packages | `internal/` | `internal/{wallet,prices,news,anomaly,verdict,glance}` | ✓ matches |
| `pkg/` for public API | only large projects (gh) | none | ✓ fine for a small CLI (gum has none either) |
| cobra command package | `pkg/cmd/` (gh), `pkg/cli/cmd/` (dnote), or root | `cmd/` package (parent of `cmd/wm`) | ⚠ minor: the `cmd` package being *both* the cobra-command package and the parent dir of `cmd/wm/` is slightly unusual naming. Works; rename to `internal/cli/` only if it ever confuses. Low priority. |
| Pure/impure split | common | `BuildRow`/`Format` (pure) vs `Run` (impure) | ✓ a notch above average |

**No action needed** beyond the optional `cmd` → `internal/cli` rename (P2).

---

## 3. Community-health & adoption files — the biggest adoption gap

GitHub scores a repo's "Community Standards" page on a fixed checklist
(<https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories>).

| File / signal | Standard | watchman | Priority |
|---|---|---|---|
| README | ✓ | ✓ (rewritten, good) | — |
| LICENSE | ✓ | ✓ GPL-2.0-only | see note ↓ |
| CONTRIBUTING.md | ✓ | ✓ | — |
| Issue templates | ✓ `.github/ISSUE_TEMPLATE/` | ✓ bug + feature | — |
| PR template | ✓ | ✓ | — |
| CHANGELOG | keep-a-changelog | ✓ git-cliff | — |
| **CODE_OF_CONDUCT.md** | Contributor Covenant — "most widely adopted", used by 9/10 largest OSS projects | **✗ missing** | **P1** |
| **SECURITY.md** | vuln-reporting policy; surfaced in Security tab | **✗ missing** | **P1** |
| **README badges** | pkg.go.dev, CI, release, license, coverage | **✗ none** | **P1** |
| `good first issue` / `help wanted` labels | auto-surfaced on `/contribute` + discovery feeds | ✗ | P2 |
| CODEOWNERS | review routing | ✗ | P2 |
| dependabot.yml | gomod + github-actions weekly | ✗ | P2 |

Sources: GitHub community profile docs (above); Contributor Covenant
<https://www.contributor-covenant.org/>; good-first-issue mechanics
<https://github.blog/open-source/maintainers/how-we-built-good-first-issues/>.

**License note (neutral, your call):** the Go CLI ecosystem skews **MIT/Apache-2.0**
(gh = MIT, gum/glow = MIT, dnote = Apache-2.0, k9s = Apache-2.0). GPL-2.0 is a
deliberate copyleft stance; it's legitimate but can deter some corporate users and
contributors. If broad adoption is the goal, this is worth a conscious decision —
not a defect.

### Badges to add (copy-paste, module = `github.com/carvalhosauro/watchman`)

```markdown
[![Go Reference](https://pkg.go.dev/badge/github.com/carvalhosauro/watchman.svg)](https://pkg.go.dev/github.com/carvalhosauro/watchman)
[![CI](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml/badge.svg)](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/carvalhosauro/watchman)](https://github.com/carvalhosauro/watchman/releases/latest)
[![License](https://img.shields.io/github/license/carvalhosauro/watchman)](./LICENSE)
[![Go Version](https://img.shields.io/github/go-mod/go-version/carvalhosauro/watchman)](./go.mod)
```

> Skip the **Go Report Card** badge: goreportcard.com is announced to shut down
> 2026-07-01 (<https://goreportcard.com/about>). Use the pkg.go.dev badge instead.

---

## 4. Discoverability (pkg.go.dev) — small, cheap wins

| Signal | Standard | watchman | Priority |
|---|---|---|---|
| Doc comments on exported identifiers | `// Package x …`, `// Foo returns …` | ✓ all packages have package docs | mostly ✓ |
| `Example` functions (runnable on pkg.go.dev) | common in libs | ✗ | P2 (low value for a binary-only CLI) |
| Tagged release so pkg.go.dev indexes | required | pending first tag | happens at release |

Sources: <https://go.dev/doc/comment>, <https://go.dev/blog/examples>,
<https://pkg.go.dev/about>.

---

## 5. CI / release / dev-ergonomics

| Dimension | Standard | watchman | Priority |
|---|---|---|---|
| `go test -race` in CI | ✓ | ✓ (via `coverage.sh`) | — |
| OS matrix | ubuntu+macos+windows (gh, charm) | **ubuntu only** | P1 |
| Security scan | govulncheck (charm/gh), CodeQL (gh) | ✗ | P1 (add `govulncheck`) |
| Coverage upload | Codecov/Coveralls badge (glow) | gate only, no badge/upload | P2 |
| GoReleaser | ✓ | ✓ | — |
| └ Windows build | `format_overrides` → zip | **✗ linux/darwin only** | P1 |
| └ completions + man pages in archives | `archives.files:` + cobra `doc.GenManTree` | ✗ | P2 |
| └ Homebrew tap | `brews:` → `homebrew-tap` (goreleaser, k9s, charm) | ✗ | P2 |
| └ nfpm .deb/.rpm | gh, charm | ✗ | P3 |
| `make help` self-documenting | k9s ships the grep/awk pattern | ✗ | P2 (nice, cheap) |

Sources: gh `.goreleaser.yml`
<https://github.com/cli/cli/blob/trunk/.goreleaser.yml>; GoReleaser archives
<https://goreleaser.com/customization/archive/>; cobra completions/man
<https://cobra.dev/docs/how-to-guides/shell-completion/>,
<https://pkg.go.dev/github.com/spf13/cobra/doc>; k9s self-documenting Makefile
<https://github.com/derailed/k9s/blob/master/Makefile>.

---

## Prioritized action plan

**P0 — before the first public release**
- Decide testing direction: port `test/e2e/*.sh` → `testscript` (.txtar), or
  accept the bash suite as a deliberate, documented extra. (Recommend port.)

**P1 — adoption essentials (cheap, high signal)**
- Add `CODE_OF_CONDUCT.md` (Contributor Covenant) + `SECURITY.md`.
- Add README badges (block above).
- CI: add OS matrix (ubuntu/macos/windows) + a `govulncheck` step.
- GoReleaser: add Windows (`format_overrides` → zip).

**P2 — polish & reach**
- `make help` target; `good first issue`/`help wanted` labels + 2-3 starter issues.
- GoReleaser: bundle completions + man pages (`doc.GenManTree`); Homebrew tap.
- `dependabot.yml`; CODEOWNERS; Codecov upload + badge.
- Optional `cmd` → `internal/cli` rename.

**P3 — later**
- nfpm (.deb/.rpm); Example funcs if any library surface emerges.

---

## What watchman already does right (don't change)

cobra + `cmd/wm` entry · `internal/` packages · pure/impure split ·
table + httptest + in-process-cobra tests · golangci-lint (v2) · coverage gate ·
GoReleaser cross-build + checksums · Conventional Commits + git-cliff changelog ·
pre-commit hooks · solid package doc comments · README/CONTRIBUTING/issue+PR
templates. This is a clean, idiomatic base — the gaps above are additive, not
rework.
