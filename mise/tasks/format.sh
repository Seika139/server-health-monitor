#!/usr/bin/env bash
#MISE description="Markdownファイルのフォーマットを実行します"
set -euo pipefail

printf "\033[33m%s\033[0m\n" "Running markdownlint --fix..."
markdownlint-cli2 --fix || true
printf "\033[32m%s\033[0m\n" "Format complete."
