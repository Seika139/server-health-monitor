#!/usr/bin/env bash
#MISE description="全ての静的解析を実行します (shellcheck, markdownlint, yamllint)"
set -euo pipefail

exit_code=0

printf "\033[33m%s\033[0m\n" "Running shellcheck..."
find . -name '*.sh' -type f | while read -r file; do
    echo "  Checking $file"
    shellcheck --severity=warning "$file" || exit_code=1
done

printf "\033[33m%s\033[0m\n" "Running markdownlint..."
markdownlint-cli2 || exit_code=1

printf "\033[33m%s\033[0m\n" "Running yamllint..."
yamllint . || exit_code=1

if [ "$exit_code" -eq 0 ]; then
    printf "\033[32m%s\033[0m\n" "All checks passed."
else
    printf "\033[31m%s\033[0m\n" "Some checks failed."
    exit 1
fi
