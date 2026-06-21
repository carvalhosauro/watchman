#!/usr/bin/env bash
set -euo pipefail
# Floor is 70 at the Phase-A-partial milestone (main = boilerplate, run.go tests land in Task 14);
# raise to 80 once Task 14 adds the run-command flow tests.
THRESHOLD=${1:-70}
go test -race -coverprofile=coverage.out ./...
pct=$(go tool cover -func=coverage.out | awk '/^total:/ {gsub(/%/,"",$3); print $3}')
echo "coverage: ${pct}% (threshold ${THRESHOLD}%)"
awk -v p="${pct:-0}" -v t="$THRESHOLD" 'BEGIN{exit !(p+0 >= t+0)}' \
  || { echo "coverage below threshold"; exit 1; }
