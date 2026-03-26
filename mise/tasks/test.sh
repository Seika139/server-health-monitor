#!/usr/bin/env bash
#MISE description="bats-core でユニットテストを実行します"
set -euo pipefail

if ! command -v bats &>/dev/null; then
    printf "\033[31m%s\033[0m\n" "ERROR: bats is not installed"
    echo "Install: brew install bats-core  (macOS)"
    echo "         apt-get install bats     (Ubuntu)"
    exit 1
fi

printf "\033[33m%s\033[0m\n" "Running bats tests..."
bats tests/
