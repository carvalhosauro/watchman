#!/usr/bin/env bash
# Black-box end-to-end suite for the wm binary. Deterministic and offline:
# the `run` glance is driven by a local mock (test/e2e/mock_server.py), so no
# real Yahoo/CVM calls are made. Exits non-zero if any assertion fails.
#
#   bash test/e2e/e2e.sh        (or: make e2e)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
ensure_binary

TODAY="$(date -u +%Y-%m-%d)"

# ─────────────────────────────────────────────────────────────────────────────
section "CLI surface (version, help, completion)"
wm --version
assert_rc 0 "--version exits 0"
assert_contains "$OUT" "version" "--version prints a version"

wm --help
assert_rc 0 "--help exits 0"
assert_contains "$OUT" "wallet" "--help lists wallet"
assert_contains "$OUT" "run" "--help lists run"
assert_contains "$OUT" "completion" "--help lists completion"

wm
assert_rc 0 "no args exits 0 (shows help)"
assert_contains "$OUT" "Available Commands" "bare invocation shows command list"

wm bogus-cmd
assert_rc_nonzero "unknown command fails"

for sh in bash zsh fish powershell; do
	wm completion "$sh"
	assert_rc 0 "completion $sh exits 0"
	assert_contains "$OUT" "$sh" "completion $sh emits a $sh script"
done

# ─────────────────────────────────────────────────────────────────────────────
section "wallet — add / list / dedupe / case"
reset_wallet
wm wallet list
assert_rc 0 "list on missing wallet exits 0"
assert_eq "$OUT" "" "missing wallet lists nothing"

wm wallet add petr4
assert_rc 0 "add petr4 exits 0"
assert_file_eq "$WATCHMAN_WALLET" "PETR4" "add uppercases + persists"

wm wallet add PETR4
wm wallet list
assert_eq "$OUT" "PETR4" "duplicate add is idempotent"

wm wallet add mxrf11
wm wallet list
assert_eq "$OUT" "PETR4
MXRF11" "second ticker appended in order"

# ─────────────────────────────────────────────────────────────────────────────
section "wallet — remove (incl. nonexistent) + arg validation"
wm wallet remove PETR4
wm wallet list
assert_eq "$OUT" "MXRF11" "remove drops the ticker"

wm wallet remove petr4
assert_rc 0 "remove (lowercased) nonexistent is a no-op, exits 0"
wm wallet list
assert_eq "$OUT" "MXRF11" "wallet unchanged after no-op remove"

wm wallet add
assert_rc_nonzero "add with no ticker fails (needs 1 arg)"
wm wallet add A B
assert_rc_nonzero "add with two tickers fails (needs exactly 1)"

# ─────────────────────────────────────────────────────────────────────────────
section "wallet — comments, blank lines, env override path, nested mkdir"
reset_wallet
printf '# my fiis\n\npetr4\n  itub4  \nMXRF11\n' > "$WATCHMAN_WALLET"
wm wallet list
assert_eq "$OUT" "PETR4
ITUB4
MXRF11" "comments/blanks skipped, entries trimmed+uppercased"

NESTED="$E2E_TMP/deep/nested/wallet"
WATCHMAN_WALLET="$NESTED" "$WM" wallet add vale3 >/dev/null 2>&1
RC=$?
assert_rc 0 "add into a nonexistent nested dir succeeds"
assert_file_eq "$NESTED" "VALE3" "nested wallet dir created + written"

# ─────────────────────────────────────────────────────────────────────────────
section "run — empty wallet hint"
reset_wallet
wm run
assert_rc 0 "run on empty wallet exits 0"
assert_contains "$OUT" "No tickers" "empty wallet prints the add hint"
assert_contains "$OUT" "wm wallet add" "hint shows the add command"

# ─────────────────────────────────────────────────────────────────────────────
section "run — full glance against local mock (deterministic, no network)"
command -v python3 >/dev/null || { echo "python3 missing — skipping mock run"; summary; exit $?; }

MOCK_OUT="$E2E_TMP/mock.port"
python3 "$DIR/mock_server.py" >"$MOCK_OUT" 2>/dev/null &
MOCK_PID=$!
# wait for the port line (up to ~3s)
PORT=""
for _ in $(seq 1 30); do PORT="$(head -1 "$MOCK_OUT" 2>/dev/null)"; [ -n "$PORT" ] && break; sleep 0.1; done
if [ -z "$PORT" ]; then fail "mock server did not start"; kill "$MOCK_PID" 2>/dev/null; summary; exit $?; fi
trap 'kill "$MOCK_PID" 2>/dev/null; cleanup' EXIT

export WATCHMAN_PRICES_URL="http://127.0.0.1:$PORT/prices"
export WATCHMAN_NEWS_URL="http://127.0.0.1:$PORT/news"

reset_wallet
printf 'PETR4\nMXRF11\nVALE3\nXPTO3\n' > "$WATCHMAN_WALLET"
wm run
assert_rc 0 "run exits 0 against mock"
assert_contains "$OUT" "watchman — $TODAY" "dated header (today, UTC)"

# one line per ticker, exactly
NLINES="$(printf '%s\n' "$OUT" | grep -cE 'LOOK|ignore')"
assert_eq "$NLINES" "4" "exactly one verdict line per held ticker"

PETR4_LINE="$(printf '%s\n' "$OUT" | grep PETR4)"
assert_contains "$PETR4_LINE" "LOOK" "PETR4 (abnormal move) -> LOOK"
assert_contains "$PETR4_LINE" "moved" "PETR4 reason names the move"

MXRF_LINE="$(printf '%s\n' "$OUT" | grep MXRF11)"
assert_contains "$MXRF_LINE" "ignore" "MXRF11 (calm) -> ignore"
assert_contains "$MXRF_LINE" "quiet" "MXRF11 reason says quiet"

VALE_LINE="$(printf '%s\n' "$OUT" | grep VALE3)"
assert_contains "$VALE_LINE" "LOOK" "VALE3 (fresh news) -> LOOK"
assert_contains "$VALE_LINE" "news" "VALE3 reason names the news"

XPTO_LINE="$(printf '%s\n' "$OUT" | grep XPTO3)"
assert_contains "$XPTO_LINE" "ignore" "XPTO3 (no data) -> ignore"
assert_contains "$XPTO_LINE" "no price data" "XPTO3 reason says no price data"

unset WATCHMAN_PRICES_URL WATCHMAN_NEWS_URL

# ─────────────────────────────────────────────────────────────────────────────
section "run — graceful when upstreams are unreachable"
export WATCHMAN_PRICES_URL="http://127.0.0.1:$PORT/prices"
export WATCHMAN_NEWS_URL="http://127.0.0.1:$PORT/news"
kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null
trap cleanup EXIT
reset_wallet
printf 'PETR4\n' > "$WATCHMAN_WALLET"
wm run
assert_rc 0 "run still exits 0 when upstreams are down"
assert_contains "$OUT" "PETR4" "down upstream still prints the ticker row"
assert_contains "$OUT" "no price data" "down upstream degrades to 'no price data'"

summary
