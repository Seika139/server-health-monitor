#!/usr/bin/env bash
# =============================================================================
# status.sh - Show current health-monitor status at a glance
# Usage: bash status.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=../config.env
    source "$CONFIG_FILE"
fi

LOG_DIR="${LOG_DIR:-/var/log/health-monitor}"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

ok()   { printf "${GREEN}[OK]${RESET}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${RESET} %s\n" "$1"; }

# ---------------------------------------------------------------------------
# 1. systemd timer
# ---------------------------------------------------------------------------
echo "=== health-monitor status ==="
echo ""

if systemctl is-active --quiet health-monitor.timer 2>/dev/null; then
    ok "health-monitor.timer is active"
    next_run=$(systemctl show health-monitor.timer --property=NextElapseUSecRealtime --value 2>/dev/null || echo "unknown")
    echo "       Next run: $next_run"
else
    fail "health-monitor.timer is not active"
fi

# Last execution
last_result=$(systemctl show health-monitor.service --property=Result --value 2>/dev/null || echo "unknown")
last_time=$(systemctl show health-monitor.service --property=ExecMainStartTimestamp --value 2>/dev/null || echo "unknown")
if [[ "$last_result" == "success" ]]; then
    ok "Last run: $last_time (result: $last_result)"
elif [[ "$last_result" == "unknown" ]]; then
    warn "Last run: not yet executed"
else
    fail "Last run: $last_time (result: $last_result)"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Latest metrics
# ---------------------------------------------------------------------------
DATE_TAG=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/metrics-${DATE_TAG}.log"

echo "=== Latest metrics ==="
if [[ -f "$LOG_FILE" ]]; then
    tail -1 "$LOG_FILE" | tr '\t' '\n'
    echo ""
    line_count=$(wc -l < "$LOG_FILE")
    echo "       ($line_count entries today)"
else
    warn "No log file for today ($LOG_FILE)"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Disk usage for log directory
# ---------------------------------------------------------------------------
echo "=== Log storage ==="
if [[ -d "$LOG_DIR" ]]; then
    log_size=$(du -sh "$LOG_DIR" 2>/dev/null | awk '{print $1}')
    log_files=$(find "$LOG_DIR" -name '*.log' -o -name '*.log.gz' 2>/dev/null | wc -l)
    echo "       $LOG_DIR: $log_size ($log_files files)"
else
    warn "$LOG_DIR does not exist"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Dependencies
# ---------------------------------------------------------------------------
echo "=== Dependencies ==="
if systemctl is-active --quiet atop 2>/dev/null; then
    ok "atop is running"
else
    warn "atop is not running"
fi

# sysstat uses different unit names across Ubuntu versions
sysstat_active=false
for svc in sysstat sysstat-collect.timer sysstat-summary.timer; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        sysstat_active=true
        break
    fi
done
if $sysstat_active; then
    ok "sysstat is running"
else
    warn "sysstat is not running"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Configuration summary
# ---------------------------------------------------------------------------
echo "=== Configuration ==="
echo "       CPU threshold:    ${CPU_THRESHOLD:-80}%"
echo "       Memory threshold: ${MEMORY_THRESHOLD:-80}%"
echo "       Swap threshold:   ${SWAP_THRESHOLD:-50}%"
echo "       Disk threshold:   ${DISK_THRESHOLD:-90}%"
echo "       Load multiplier:  ${LOAD_THRESHOLD_MULTIPLIER:-2}x cores"
echo "       Alert cooldown:   ${ALERT_COOLDOWN:-300}s"

if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    ok "Discord webhook: configured"
else
    warn "Discord webhook: NOT configured"
fi

if [[ -n "${HEARTBEAT_URL:-}" ]]; then
    ok "Heartbeat: configured"
else
    echo "       Heartbeat: disabled"
fi

if [[ -n "${WATCH_PROCESSES:-}" ]]; then
    echo "       Watch processes: $WATCH_PROCESSES"
else
    echo "       Watch processes: disabled"
fi
