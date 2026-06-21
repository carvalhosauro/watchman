#!/usr/bin/env bash
set -euo pipefail
# Floor is 80: flow tests cover the network + CLI paths in addition to pure logic.
THRESHOLD=${1:-80}
mkdir -p test
go test -race -coverprofile=test/coverage.out ./...
pct=$(go tool cover -func=test/coverage.out | awk '/^total:/ {gsub(/%/,"",$3); print $3}')
echo "coverage: ${pct}% (threshold ${THRESHOLD}%)"
awk -v p="${pct:-0}" -v t="$THRESHOLD" 'BEGIN{exit !(p+0 >= t+0)}' \
  || { echo "coverage below threshold"; exit 1; }
