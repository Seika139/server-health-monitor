#!/usr/bin/env bash
# =============================================================================
# test-alert.sh - Send a test notification to Discord and optionally heartbeat
# Usage: bash test-alert.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.env not found at $CONFIG_FILE" >&2
    exit 1
fi
# shellcheck source=../config.env
source "$CONFIG_FILE"

echo "=== Discord Webhook Test ==="
echo ""

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "ERROR: DISCORD_WEBHOOK_URL is not set in config.env" >&2
    exit 1
fi

# Temporarily clear cooldown for test alert
rm -f /tmp/health-monitor-cooldown/test 2>/dev/null || true

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SERVER="${SERVER_NAME:-$(hostname)}"

PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "Test Alert - $SERVER",
    "description": "This is a test notification from server-health-monitor.",
    "color": 3066993,
    "fields": [
      {"name": "Status", "value": "Configuration is working correctly", "inline": false}
    ],
    "timestamp": "$TIMESTAMP"
  }]
}
EOF
)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DISCORD_WEBHOOK_URL") || true

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    echo "Discord: OK (HTTP $HTTP_CODE)"
    echo "  -> Check your Discord channel for the test message."
else
    echo "Discord: FAILED (HTTP $HTTP_CODE)"
    echo "  -> Verify DISCORD_WEBHOOK_URL in config.env"
    exit 1
fi

echo ""

# Test heartbeat if configured
if [[ -n "${HEARTBEAT_URL:-}" ]]; then
    echo "=== Heartbeat Test ==="
    HEARTBEAT_SCRIPT="$SCRIPT_DIR/heartbeat.sh"
    if [[ -x "$HEARTBEAT_SCRIPT" ]]; then
        "$HEARTBEAT_SCRIPT" "test"
        echo "Heartbeat: sent to $HEARTBEAT_URL"
    else
        echo "Heartbeat: heartbeat.sh not found"
    fi
else
    echo "Heartbeat: skipped (HEARTBEAT_URL not configured)"
fi

echo ""
echo "All tests passed."
