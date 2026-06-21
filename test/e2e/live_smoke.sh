#!/usr/bin/env bash
# Live smoke test: drives `wm run` against the REAL Yahoo + CVM upstreams.
# Network-dependent and tolerant by design — it asserts the SHAPE of the output
# (dated header, one verdict line per ticker, exit 0), not specific verdicts,
# because real prices move and Yahoo may rate-limit (429 -> graceful "no price
# data", still a valid row). Run before a release to confirm the real wiring.
#
#   bash test/e2e/live_smoke.sh        (or: make e2e-live)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
ensure_binary

# Make sure no mock override leaks in from the shell.
unset WATCHMAN_PRICES_URL WATCHMAN_NEWS_URL
TODAY="$(date -u +%Y-%m-%d)"

section "live — wm run against real Yahoo/CVM"
reset_wallet
printf 'PETR4\nITUB4\nXPTO3INVALID\n' > "$WATCHMAN_WALLET"
wm run
assert_rc 0 "live run exits 0"
assert_contains "$OUT" "watchman — $TODAY" "live run prints today's dated header"

for tk in PETR4 ITUB4 XPTO3INVALID; do
	LINE="$(printf '%s\n' "$OUT" | grep "$tk")"
	assert_contains "$LINE" "$tk" "row present for $tk"
	if printf '%s' "$LINE" | grep -qE 'LOOK|ignore'; then
		pass "$tk row is a valid verdict (LOOK/ignore)"
	else
		fail "$tk row missing a verdict" "$LINE"
	fi
done

NLINES="$(printf '%s\n' "$OUT" | grep -cE 'LOOK|ignore')"
assert_eq "$NLINES" "3" "exactly one verdict line per held ticker"

printf '\n%sNote:%s real prices vary and Yahoo may return 429 (rate-limited) ->\n' "$BOLD" "$OFF"
printf 'a ticker may legitimately show "no price data" here; that is still a pass.\n'

summary
