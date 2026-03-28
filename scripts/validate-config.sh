#!/usr/bin/env bash
# =============================================================================
# validate-config.sh - Validate config.env values
# Usage: bash validate-config.sh [config_file]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${CONFIG_FILE:-$SCRIPT_DIR/../config.env}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=../config.env
source "$CONFIG_FILE"

errors=0
warnings=0

err()  { echo "  ERROR:   $1"; (( errors++ )) || true; }
warn() { echo "  WARNING: $1"; (( warnings++ )) || true; }
ok()   { echo "  OK:      $1"; }

is_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }

echo "=== Validating $CONFIG_FILE ==="
echo ""

# ---------------------------------------------------------------------------
# Required fields
# ---------------------------------------------------------------------------
if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    warn "DISCORD_WEBHOOK_URL is empty (no alerts will be sent)"
elif [[ ! "$DISCORD_WEBHOOK_URL" =~ ^https:// ]]; then
    err "DISCORD_WEBHOOK_URL must start with https://"
else
    ok "DISCORD_WEBHOOK_URL is set"
fi

# ---------------------------------------------------------------------------
# Threshold ranges (0-100)
# ---------------------------------------------------------------------------
for var_name in CPU_THRESHOLD MEMORY_THRESHOLD DISK_THRESHOLD; do
    val="${!var_name:-}"
    if [[ -z "$val" ]]; then
        err "$var_name is not set"
    elif ! is_integer "$val"; then
        err "$var_name must be an integer (got: '$val')"
    elif (( val < 1 || val > 100 )); then
        err "$var_name must be between 1 and 100 (got: $val)"
    else
        ok "$var_name=$val"
    fi
done

# SWAP_IO_THRESHOLD (pages/sec, 0 = disabled)
val="${SWAP_IO_THRESHOLD:-}"
if [[ -z "$val" ]]; then
    err "SWAP_IO_THRESHOLD is not set"
elif ! is_integer "$val"; then
    err "SWAP_IO_THRESHOLD must be an integer (got: '$val')"
else
    ok "SWAP_IO_THRESHOLD=$val"
fi

# LOAD_THRESHOLD_MULTIPLIER (positive integer)
val="${LOAD_THRESHOLD_MULTIPLIER:-}"
if [[ -z "$val" ]]; then
    err "LOAD_THRESHOLD_MULTIPLIER is not set"
elif ! is_integer "$val"; then
    err "LOAD_THRESHOLD_MULTIPLIER must be an integer (got: '$val')"
elif (( val < 1 )); then
    err "LOAD_THRESHOLD_MULTIPLIER must be >= 1 (got: $val)"
else
    ok "LOAD_THRESHOLD_MULTIPLIER=$val"
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
val="${LOG_RETENTION_DAYS:-}"
if [[ -n "$val" ]] && ! is_integer "$val"; then
    err "LOG_RETENTION_DAYS must be an integer (got: '$val')"
elif [[ -n "$val" ]] && (( val < 1 )); then
    err "LOG_RETENTION_DAYS must be >= 1 (got: $val)"
else
    ok "LOG_RETENTION_DAYS=${val:-30}"
fi

# ---------------------------------------------------------------------------
# Alert cooldown
# ---------------------------------------------------------------------------
val="${ALERT_COOLDOWN:-}"
if [[ -n "$val" ]] && ! is_integer "$val"; then
    err "ALERT_COOLDOWN must be an integer (got: '$val')"
elif [[ -n "$val" ]] && (( val < 0 )); then
    err "ALERT_COOLDOWN must be >= 0 (got: $val)"
else
    ok "ALERT_COOLDOWN=${val:-300}"
fi

# ---------------------------------------------------------------------------
# TOP_PROCESSES
# ---------------------------------------------------------------------------
val="${TOP_PROCESSES:-}"
if [[ -n "$val" ]] && ! is_integer "$val"; then
    err "TOP_PROCESSES must be an integer (got: '$val')"
else
    ok "TOP_PROCESSES=${val:-5}"
fi

# ---------------------------------------------------------------------------
# Heartbeat
# ---------------------------------------------------------------------------
if [[ -n "${HEARTBEAT_URL:-}" ]]; then
    if [[ ! "$HEARTBEAT_URL" =~ ^https?:// ]]; then
        err "HEARTBEAT_URL must start with http:// or https:// (got: '$HEARTBEAT_URL')"
    else
        ok "HEARTBEAT_URL is set"
    fi
    method="${HEARTBEAT_METHOD:-GET}"
    if [[ "$method" != "GET" && "$method" != "POST" && "$method" != "get" && "$method" != "post" ]]; then
        err "HEARTBEAT_METHOD must be GET or POST (got: '$method')"
    else
        ok "HEARTBEAT_METHOD=$method"
    fi
fi

# ---------------------------------------------------------------------------
# WATCH_PROCESSES (format check)
# ---------------------------------------------------------------------------
if [[ -n "${WATCH_PROCESSES:-}" ]]; then
    IFS=',' read -ra procs <<< "$WATCH_PROCESSES"
    for p in "${procs[@]}"; do
        p=$(echo "$p" | xargs)
        if [[ -z "$p" ]]; then
            continue
        fi
        if [[ "$p" =~ [[:space:]] ]]; then
            err "WATCH_PROCESSES entry '$p' contains spaces (use exact process name)"
        fi
    done
    ok "WATCH_PROCESSES=${WATCH_PROCESSES}"
fi

# ---------------------------------------------------------------------------
# ACP monitoring
# ---------------------------------------------------------------------------
if [[ "${ACP_MONITOR_ENABLED:-false}" == "true" ]]; then
    if ! command -v python3 &>/dev/null; then
        err "ACP_MONITOR_ENABLED=true but python3 is not installed"
    else
        ok "ACP_MONITOR_ENABLED=true (python3 found)"
    fi

    for var_name in ACP_MONITOR_WARN ACP_MONITOR_DANGER; do
        val="${!var_name:-}"
        if [[ -n "$val" ]]; then
            if ! awk "BEGIN{exit !($val >= 0 && $val <= 1)}" 2>/dev/null; then
                err "$var_name must be between 0.0 and 1.0 (got: '$val')"
            else
                ok "$var_name=$val"
            fi
        fi
    done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
if (( errors > 0 )); then
    echo "  Result: FAILED ($errors error(s), $warnings warning(s))"
    exit 1
elif (( warnings > 0 )); then
    echo "  Result: PASSED with $warnings warning(s)"
    exit 0
else
    echo "  Result: PASSED"
    exit 0
fi
