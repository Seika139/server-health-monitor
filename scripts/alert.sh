#!/usr/bin/env bash
# =============================================================================
# alert.sh - Send health alerts to Discord via Webhook
# Usage: alert.sh <alert_type> <current_value> <threshold> <details>
#        alert.sh recover <alert_type> <current_value> <threshold>
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

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "ERROR: DISCORD_WEBHOOK_URL is not set in config.env" >&2
    exit 1
fi

IS_RECOVERY=false
if [[ "${1:-}" == "recover" ]]; then
    IS_RECOVERY=true
    shift
fi

ALERT_TYPE="${1:?Usage: alert.sh [recover] <type> <value> <threshold> [details]}"
CURRENT_VALUE="${2:?}"
THRESHOLD="${3:?}"
DETAILS="${4:-}"

# ---------------------------------------------------------------------------
# Cooldown check: skip if the same alert type fired recently
# (Recovery notifications skip cooldown — they should always arrive)
# ---------------------------------------------------------------------------
COOLDOWN_DIR="/var/log/health-monitor/.cooldown"
mkdir -p "$COOLDOWN_DIR"
COOLDOWN_FILE="$COOLDOWN_DIR/$ALERT_TYPE"

if ! $IS_RECOVERY && [[ -f "$COOLDOWN_FILE" ]]; then
    last_alert=$(cat "$COOLDOWN_FILE")
    now=$(date +%s)
    elapsed=$(( now - last_alert ))
    if (( elapsed < ALERT_COOLDOWN )); then
        exit 0
    fi
fi
# Cooldown timestamp is written AFTER successful send (see below)

# ---------------------------------------------------------------------------
# Build Discord embed
# ---------------------------------------------------------------------------
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Escape special characters for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

SERVER="${SERVER_NAME:-$(hostname)}"

if $IS_RECOVERY; then
    COLOR=3066993  # green
    case "$ALERT_TYPE" in
        cpu)        TITLE="CPU Recovered";;
        memory)     TITLE="Memory Recovered";;
        swap_io)    TITLE="Swap I/O Recovered";;
        disk)       TITLE="Disk Recovered";;
        load)       TITLE="Load Recovered";;
        process_*)  TITLE="Process Recovered: ${ALERT_TYPE#process_}";;
        process)    TITLE="Process Recovered";;
        *)          TITLE="Recovered: $ALERT_TYPE";;
    esac
    PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "$TITLE - $SERVER",
    "color": $COLOR,
    "fields": [
      {"name": "Current", "value": "${CURRENT_VALUE}", "inline": true},
      {"name": "Threshold", "value": "${THRESHOLD}", "inline": true}
    ],
    "timestamp": "$TIMESTAMP"
  }]
}
EOF
    )
else
    case "$ALERT_TYPE" in
        cpu)        COLOR=16711680; TITLE="CPU Alert";;        # red
        memory)     COLOR=16744448; TITLE="Memory Alert";;     # orange
        swap_io)    COLOR=16750848; TITLE="Swap I/O Alert";;    # dark orange
        disk)       COLOR=16776960; TITLE="Disk Alert";;       # yellow
        load)       COLOR=10494192; TITLE="Load Alert";;       # purple
        process_*)  COLOR=3447003;  TITLE="Process Alert: ${ALERT_TYPE#process_}";; # blue
        process)    COLOR=3447003;  TITLE="Process Alert";;    # blue
        *)          COLOR=8421504;  TITLE="Alert: $ALERT_TYPE";;
    esac
    ESCAPED_DETAILS=$(json_escape "$DETAILS")
    PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "$TITLE - $SERVER",
    "color": $COLOR,
    "fields": [
      {"name": "Current", "value": "${CURRENT_VALUE}", "inline": true},
      {"name": "Threshold", "value": "${THRESHOLD}", "inline": true},
      {"name": "Top Processes", "value": "\`\`\`${ESCAPED_DETAILS}\`\`\`"}
    ],
    "timestamp": "$TIMESTAMP"
  }]
}
EOF
    )
fi

# ---------------------------------------------------------------------------
# Send to Discord (with rate-limit retry)
# ---------------------------------------------------------------------------
RESPONSE_HEADERS=$(mktemp)
trap 'rm -f "$RESPONSE_HEADERS"' EXIT

send_webhook() {
    curl -s -o /dev/null -D "$RESPONSE_HEADERS" -w "%{http_code}" -m 10 \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$DISCORD_WEBHOOK_URL" || echo "000"
}

HTTP_CODE=$(send_webhook)

# Retry once on rate limit (429)
if [[ "$HTTP_CODE" == "429" ]]; then
    retry_after=$(grep -i '^retry-after:' "$RESPONSE_HEADERS" | awk '{print $2}' | tr -d '\r')
    retry_after="${retry_after:-2}"
    # Cap retry wait at 5 seconds to avoid blocking monitor too long
    if (( ${retry_after%.*} > 5 )); then
        retry_after=5
    fi
    echo "WARNING: Rate limited (429), retrying after ${retry_after}s..." >&2
    sleep "$retry_after"
    HTTP_CODE=$(send_webhook)
fi

if [[ "${HTTP_CODE:-000}" -ge 200 && "${HTTP_CODE:-000}" -lt 300 ]]; then
    # Record cooldown only on successful alert send (not recovery)
    if ! $IS_RECOVERY; then
        date +%s > "$COOLDOWN_FILE"
    fi
    exit 0
else
    echo "WARNING: Discord webhook returned HTTP ${HTTP_CODE:-timeout}" >&2
    exit 1
fi
