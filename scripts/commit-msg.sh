#!/usr/bin/env bash
set -euo pipefail
header=$(head -1 "$1")
regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9_-]+\))?!?: .+'
if [[ ! "$header" =~ $regex ]]; then
  echo "Commit message must follow Conventional Commits: type(scope): subject"
  echo "got: $header"
  exit 1
fi
