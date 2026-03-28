#!/usr/bin/env bash
# =============================================================================
# acp-monitor.sh - Monitor ACP session context window usage
# Wrapper that sources config.env and calls acp-monitor.py
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run via systemd, EnvironmentFile provides config as env vars.
# When run manually, source config.env directly.
if [[ -z "${ACP_MONITOR_ENABLED:-}" ]]; then
    CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.env}"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: config.env not found at $CONFIG_FILE" >&2
        exit 1
    fi
    # shellcheck source=../config.env
    source "$CONFIG_FILE"
fi

# Skip if ACP monitoring is disabled
if [[ "${ACP_MONITOR_ENABLED:-false}" != "true" ]]; then
    exit 0
fi

# Check Python 3 availability
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required for ACP monitoring" >&2
    exit 1
fi

# Export variables needed by the Python script
export DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
export ACP_MONITOR_WARN="${ACP_MONITOR_WARN:-0.7}"
export ACP_MONITOR_DANGER="${ACP_MONITOR_DANGER:-0.85}"
export ACP_MONITOR_SESSIONS="${ACP_MONITOR_SESSIONS:-}"
export ACP_MONITOR_PROJECTS="${ACP_MONITOR_PROJECTS:-}"
export ALERT_COOLDOWN="${ALERT_COOLDOWN:-300}"
export SERVER_NAME="${SERVER_NAME:-$(hostname)}"

exec python3 "$SCRIPT_DIR/acp-monitor.py" "$@"
