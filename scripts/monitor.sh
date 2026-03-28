#!/usr/bin/env bash
# =============================================================================
# monitor.sh - Collect system metrics, log them, and fire alerts if thresholds
#              are exceeded. Designed to be invoked every minute by systemd timer.
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

LOG_DIR="${LOG_DIR:-/var/log/health-monitor}"
mkdir -p "$LOG_DIR"

ALERT_SCRIPT="$SCRIPT_DIR/alert.sh"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE_TAG=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/metrics-${DATE_TAG}.log"

# =============================================================================
# Collect metrics
# =============================================================================

# CPU usage from /proc/stat (two 1-second snapshots, no external commands)
read_cpu_stat() {
    awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat
}

# Swap I/O from /proc/vmstat (pswpin + pswpout = total swap page operations)
read_swap_io() {
    awk '/^pswpin/{i=$2} /^pswpout/{o=$2} END{print i+o}' /proc/vmstat
}

read -r total1 idle1 <<< "$(read_cpu_stat)"
swap_io1=$(read_swap_io)
sleep 1
read -r total2 idle2 <<< "$(read_cpu_stat)"
swap_io2=$(read_swap_io)
cpu_delta=$(( total2 - total1 ))
idle_delta=$(( idle2 - idle1 ))
if (( cpu_delta > 0 )); then
    cpu_usage=$(awk "BEGIN{printf \"%.1f\", (1 - $idle_delta/$cpu_delta) * 100}")
    cpu_usage_int=${cpu_usage%.*}
else
    cpu_usage="0.0"
    cpu_usage_int=0
fi

# Memory usage
read -r mem_total mem_available <<< "$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print t, a}' /proc/meminfo)"
if (( mem_total > 0 )); then
    mem_usage=$(awk "BEGIN{printf \"%.1f\", (1 - $mem_available/$mem_total) * 100}")
    mem_usage_int=${mem_usage%.*}
else
    mem_usage="0.0"
    mem_usage_int=0
fi

# Swap usage
read -r swap_total swap_free <<< "$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print t, f}' /proc/meminfo)"
if (( swap_total > 0 )); then
    swap_usage=$(awk "BEGIN{printf \"%.1f\", (1 - $swap_free/$swap_total) * 100}")
else
    swap_usage="0.0"
fi

# Swap I/O rate (pages/sec)
swap_io_rate=$(( swap_io2 - swap_io1 ))

# Disk usage (root partition)
disk_usage=$(df / | awk 'NR==2{print $5}' | tr -d '%')

# Load average (1min)
load_1m=$(awk '{print $1}' /proc/loadavg)
cpu_cores=$(nproc)
load_threshold=$(awk "BEGIN{printf \"%.1f\", $cpu_cores * ${LOAD_THRESHOLD_MULTIPLIER:-2}}")

# =============================================================================
# Log metrics (TSV format for easy parsing)
# =============================================================================
printf '%s\tcpu=%s%%\tmem=%s%%\tswap=%s%%\tswap_io=%spg/s\tdisk=%s%%\tload=%s\tcores=%s\n' \
    "$TIMESTAMP" "$cpu_usage" "$mem_usage" "$swap_usage" "$swap_io_rate" "$disk_usage" "$load_1m" "$cpu_cores" \
    >> "$LOG_FILE" 2>/dev/null || echo "WARNING: Failed to write to $LOG_FILE (disk full?)" >&2

# Clean up old log files (date-based filenames are not handled by logrotate)
find "$LOG_DIR" -name 'metrics-*.log' -mtime "+${LOG_RETENTION_DAYS:-30}" -delete 2>/dev/null || true

# =============================================================================
# Top processes (for alert details)
# =============================================================================
get_top_cpu_processes() {
    ps aux --sort=-%cpu | awk 'NR>1 && NR<='"$((${TOP_PROCESSES:-5}+1))"'{printf "%-8s %-6s %5s%% %s\n", $1, $2, $3, $11}'
}

get_top_mem_processes() {
    ps aux --sort=-%mem | awk 'NR>1 && NR<='"$((${TOP_PROCESSES:-5}+1))"'{printf "%-8s %-6s %5s%% %s\n", $1, $2, $4, $11}'
}

# =============================================================================
# Alert state management (for recovery notifications)
# =============================================================================
ALERT_STATE_DIR="/var/log/health-monitor/.alert"
mkdir -p "$ALERT_STATE_DIR"

# fire_alert <type> <value> <threshold> <details>
#   Sends alert and marks state as "alerting" only on successful send
fire_alert() {
    local type="$1" value="$2" threshold="$3" details="$4"
    if "$ALERT_SCRIPT" "$type" "$value" "$threshold" "$details"; then
        touch "$ALERT_STATE_DIR/$type"
    fi
}

# check_recovery <type> <value> <threshold>
#   If previously alerting, send recovery and clear state
#   State is cleared only on successful send to avoid losing the "was alerting" marker
check_recovery() {
    local type="$1" value="$2" threshold="$3"
    if [[ -f "$ALERT_STATE_DIR/$type" ]]; then
        if "$ALERT_SCRIPT" recover "$type" "$value" "$threshold"; then
            rm -f "$ALERT_STATE_DIR/$type"
        fi
    fi
}

# =============================================================================
# Threshold checks & alerts
# =============================================================================

if (( cpu_usage_int > CPU_THRESHOLD )); then
    details=$(get_top_cpu_processes)
    fire_alert cpu "${cpu_usage}%" "${CPU_THRESHOLD}%" "$details"
else
    check_recovery cpu "${cpu_usage}%" "${CPU_THRESHOLD}%"
fi

if (( mem_usage_int > MEMORY_THRESHOLD )); then
    details=$(get_top_mem_processes)
    fire_alert memory "${mem_usage}%" "${MEMORY_THRESHOLD}%" "$details"
else
    check_recovery memory "${mem_usage}%" "${MEMORY_THRESHOLD}%"
fi

if (( disk_usage > DISK_THRESHOLD )); then
    details=$(df -h / | awk 'NR==2{printf "Used: %s / %s (%s)", $3, $2, $5}')
    fire_alert disk "${disk_usage}%" "${DISK_THRESHOLD}%" "$details"
else
    check_recovery disk "${disk_usage}%" "${DISK_THRESHOLD}%"
fi

# Compare load as integer * 10 to avoid float issues in bash
load_x10=$(awk "BEGIN{printf \"%d\", $load_1m * 10}")
threshold_x10=$(awk "BEGIN{printf \"%d\", $load_threshold * 10}")
if (( load_x10 > threshold_x10 )); then
    details=$(get_top_cpu_processes)
    fire_alert load "$load_1m" "$load_threshold" "$details"
else
    check_recovery load "$load_1m" "$load_threshold"
fi

# Swap I/O (0 = disabled)
if (( ${SWAP_IO_THRESHOLD:-200} > 0 && swap_io_rate > ${SWAP_IO_THRESHOLD:-200} )); then
    swap_total_h=$(awk "BEGIN{printf \"%.0f\", $swap_total/1024}")
    swap_used_h=$(awk "BEGIN{printf \"%.0f\", ($swap_total-$swap_free)/1024}")
    details="I/O: ${swap_io_rate} pg/s | Used: ${swap_used_h}MB / ${swap_total_h}MB (${swap_usage}%)"
    fire_alert swap_io "${swap_io_rate}pg/s" "${SWAP_IO_THRESHOLD:-200}pg/s" "$details"
elif (( ${SWAP_IO_THRESHOLD:-200} > 0 )); then
    check_recovery swap_io "${swap_io_rate}pg/s" "${SWAP_IO_THRESHOLD:-200}pg/s"
fi

# =============================================================================
# Process health check
# =============================================================================
if [[ -n "${WATCH_PROCESSES:-}" ]]; then
    IFS=',' read -ra procs <<< "$WATCH_PROCESSES"
    for proc_name in "${procs[@]}"; do
        proc_name=$(echo "$proc_name" | xargs)  # trim whitespace
        if [[ -z "$proc_name" ]]; then
            continue
        fi
        if ! pgrep -x "$proc_name" > /dev/null 2>&1; then
            fire_alert "process_${proc_name}" "$proc_name" "not running" "Process '$proc_name' is not running"
        else
            check_recovery "process_${proc_name}" "$proc_name" "running"
        fi
    done
fi

# =============================================================================
# Heartbeat: signal to external service that this server is alive
# =============================================================================
HEARTBEAT_SCRIPT="$SCRIPT_DIR/heartbeat.sh"
if [[ -x "$HEARTBEAT_SCRIPT" ]]; then
    "$HEARTBEAT_SCRIPT" "cpu=${cpu_usage}% mem=${mem_usage}% load=${load_1m}"
fi

exit 0
