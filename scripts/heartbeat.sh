#!/usr/bin/env bash
# =============================================================================
# heartbeat.sh - Send a "still alive" signal to an external monitoring service
# Usage: heartbeat.sh [message]
#
# Reads HEARTBEAT_URL and HEARTBEAT_METHOD from config.env.
# If HEARTBEAT_URL is empty, exits silently (heartbeat disabled).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    exit 0
fi
# shellcheck source=../config.env
source "$CONFIG_FILE"

# If no URL configured, heartbeat is disabled
if [[ -z "${HEARTBEAT_URL:-}" ]]; then
    exit 0
fi

MESSAGE="${1:-ok}"
METHOD="${HEARTBEAT_METHOD:-GET}"

# Escape message for safe JSON embedding
json_escape_msg() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

case "$METHOD" in
    GET|get)
        curl -fsS -o /dev/null -m 10 "$HEARTBEAT_URL" 2>/dev/null || true
        ;;
    POST|post)
        ESCAPED_MSG=$(json_escape_msg "$MESSAGE")
        curl -fsS -o /dev/null -m 10 -X POST \
            -H "Content-Type: application/json" \
            -d "{\"status\":\"ok\",\"msg\":\"$ESCAPED_MSG\"}" \
            "$HEARTBEAT_URL" 2>/dev/null || true
        ;;
    *)
        echo "WARNING: Unknown HEARTBEAT_METHOD '$METHOD', skipping" >&2
        ;;
esac
