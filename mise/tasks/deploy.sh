#!/usr/bin/env bash
#MISE description="サーバーにファイルをコピーします (mise run deploy -- user@server)"
set -euo pipefail

host="${1:?Usage: mise run deploy -- user@server}"

echo "Deploying to $host..."
scp -r config.env scripts/ systemd/ install.sh uninstall.sh "$host":~/server-health-monitor/
printf "\033[32m%s\033[0m\n" "Deployed. SSH and run: cd ~/server-health-monitor && sudo bash install.sh"
