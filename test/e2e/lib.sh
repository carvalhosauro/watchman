#!/usr/bin/env bash
# Shared harness for wm black-box e2e scripts: build the binary, isolate config,
# and provide self-asserting helpers with a pass/fail tally.
#
# Usage: source this file, then call assert_* helpers and finish with `summary`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WM="$REPO_ROOT/bin/wm"

# Isolate from the real environment: a throwaway HOME and wallet per run, so the
# suite never reads or writes ~/.config/watchman.
E2E_TMP="$(mktemp -d)"
export HOME="$E2E_TMP/home"
export WATCHMAN_WALLET="$E2E_TMP/wallet"
mkdir -p "$HOME"

PASS=0
FAIL=0
CURRENT="(none)"

# Colors only when stdout is a terminal.
if [ -t 1 ]; then GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else GREEN=""; RED=""; BOLD=""; DIM=""; OFF=""; fi

cleanup() { rm -rf "$E2E_TMP"; }
trap cleanup EXIT

section() { CURRENT="$1"; printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$OFF"; }

pass() { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
fail() {
	FAIL=$((FAIL + 1))
	printf '  %s✗ %s%s\n' "$RED" "$1" "$OFF"
	[ -n "${2:-}" ] && printf '    %sgot: %s%s\n' "$DIM" "$2" "$OFF"
}

# Reset the wallet to a known empty state between cases.
reset_wallet() { rm -rf "$E2E_TMP/wallet" "$(dirname "$E2E_TMP/wallet")"/sub 2>/dev/null; export WATCHMAN_WALLET="$E2E_TMP/wallet"; }

# wm <args...> — runs the binary, capturing combined output in $OUT and code in $RC.
wm() { OUT="$("$WM" "$@" 2>&1)"; RC=$?; return 0; }

assert_rc() { # assert_rc <expected> <label>
	if [ "$RC" -eq "$1" ]; then pass "$2 (exit $1)"; else fail "$2 — expected exit $1, got $RC" "$OUT"; fi
}
assert_rc_nonzero() { # assert_rc_nonzero <label>
	if [ "$RC" -ne 0 ]; then pass "$1 (exit $RC ≠ 0)"; else fail "$1 — expected non-zero exit, got 0" "$OUT"; fi
}
assert_contains() { # assert_contains <haystack> <needle> <label>
	if printf '%s' "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3 — missing '$2'" "$1"; fi
}
assert_not_contains() { # assert_not_contains <haystack> <needle> <label>
	if printf '%s' "$1" | grep -qF -- "$2"; then fail "$3 — unexpected '$2'" "$1"; else pass "$3"; fi
}
assert_eq() { # assert_eq <actual> <expected> <label>
	if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 — expected '$2'" "$1"; fi
}
assert_file_eq() { # assert_file_eq <path> <expected-content> <label>
	local got; got="$(cat "$1" 2>/dev/null)"
	if [ "$got" = "$2" ]; then pass "$3"; else fail "$3 — file '$1'" "$got"; fi
}

summary() {
	printf '\n%s%d passed, %d failed%s\n' "$BOLD" "$PASS" "$FAIL" "$OFF"
	[ "$FAIL" -eq 0 ]
}

# Build the binary once if missing or stale relative to sources.
ensure_binary() {
	if [ ! -x "$WM" ] || [ -n "$(find "$REPO_ROOT/cmd" "$REPO_ROOT/internal" -name '*.go' -newer "$WM" 2>/dev/null)" ]; then
		printf '%sbuilding %s …%s\n' "$DIM" "$WM" "$OFF"
		( cd "$REPO_ROOT" && go build -o bin/wm ./cmd/wm ) || { echo "build failed"; exit 1; }
	fi
}
