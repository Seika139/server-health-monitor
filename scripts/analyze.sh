#!/usr/bin/env bash
# =============================================================================
# analyze.sh - Analyze health metrics for a given date
# Usage: bash analyze.sh [YYYY-MM-DD]  (defaults to today)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=../config.env
    source "$CONFIG_FILE"
fi

LOG_DIR="${LOG_DIR:-/var/log/health-monitor}"
TARGET_DATE="${1:-$(date '+%Y-%m-%d')}"
LOG_FILE="$LOG_DIR/metrics-${TARGET_DATE}.log"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "ERROR: No log file found for $TARGET_DATE ($LOG_FILE)" >&2
    echo "Available dates:"
    ls "$LOG_DIR"/metrics-*.log 2>/dev/null | sed 's/.*metrics-//;s/\.log//' | sort || echo "  (none)"
    exit 1
fi

TOTAL_LINES=$(wc -l < "$LOG_FILE")

echo "============================================="
echo "  Health Report: $TARGET_DATE"
echo "  Data points: $TOTAL_LINES"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Parse and compute stats
# ---------------------------------------------------------------------------
awk -F'\t' '
{
    # Extract numeric values from key=value% format
    split($2, cpu_parts, "="); split(cpu_parts[2], cpu_val, "%");
    split($3, mem_parts, "="); split(mem_parts[2], mem_val, "%");

    # Handle both old format (no swap) and new format (with swap)
    if ($4 ~ /^swap=/) {
        split($4, swap_parts, "="); split(swap_parts[2], swap_val, "%");
        split($5, disk_parts, "="); split(disk_parts[2], disk_val, "%");
        split($6, load_parts, "=");
    } else {
        swap_val[1] = -1;
        split($4, disk_parts, "="); split(disk_parts[2], disk_val, "%");
        split($5, load_parts, "=");
    }

    cpu  = cpu_val[1] + 0;
    mem  = mem_val[1] + 0;
    swap = swap_val[1] + 0;
    disk = disk_val[1] + 0;
    load = load_parts[2] + 0;

    n++;
    cpu_sum  += cpu;  mem_sum  += mem;  disk_sum  += disk;  load_sum  += load;
    if (swap >= 0) { swap_sum += swap; swap_n++; }

    if (n == 1 || cpu  > cpu_max)  { cpu_max  = cpu;  cpu_max_t  = $1; }
    if (n == 1 || mem  > mem_max)  { mem_max  = mem;  mem_max_t  = $1; }
    if (n == 1 || disk > disk_max) { disk_max = disk; disk_max_t = $1; }
    if (n == 1 || load > load_max) { load_max = load; load_max_t = $1; }
    if (swap >= 0 && (swap_n == 1 || swap > swap_max)) { swap_max = swap; swap_max_t = $1; }

    # Hourly aggregation
    split($1, dt, " ");
    hour = substr(dt[2], 1, 2);
    h_cpu[hour] += cpu; h_n[hour]++;
}
END {
    if (n == 0) {
        printf "No data points found.\n";
        exit 0;
    }
    printf "--- Summary ---\n";
    printf "  CPU:    avg=%.1f%%  max=%.1f%% (%s)\n", cpu_sum/n, cpu_max, cpu_max_t;
    printf "  Memory: avg=%.1f%%  max=%.1f%% (%s)\n", mem_sum/n, mem_max, mem_max_t;
    if (swap_n > 0) {
        printf "  Swap:   avg=%.1f%%  max=%.1f%% (%s)\n", swap_sum/swap_n, swap_max, swap_max_t;
    }
    printf "  Disk:   avg=%.1f%%  max=%.1f%% (%s)\n", disk_sum/n, disk_max, disk_max_t;
    printf "  Load:   avg=%.2f   max=%.2f  (%s)\n", load_sum/n, load_max, load_max_t;

    printf "\n--- Hourly CPU average ---\n";
    for (h = 0; h < 24; h++) {
        hh = sprintf("%02d", h);
        if (hh in h_cpu) {
            bar_len = int(h_cpu[hh] / h_n[hh] / 2);
            bar = "";
            for (i = 0; i < bar_len; i++) bar = bar "#";
            printf "  %s:00  %5.1f%%  %s\n", hh, h_cpu[hh]/h_n[hh], bar;
        }
    }
}
' "$LOG_FILE"

echo ""

# ---------------------------------------------------------------------------
# Anomaly highlights
# ---------------------------------------------------------------------------
CPU_T="${CPU_THRESHOLD:-80}"
MEM_T="${MEMORY_THRESHOLD:-80}"

cpu_violations=$(awk -F'\t' '{split($2,a,"=");split(a[2],b,"%");if(b[1]+0>'"$CPU_T"')c++}END{print c+0}' "$LOG_FILE")
mem_violations=$(awk -F'\t' '{split($3,a,"=");split(a[2],b,"%");if(b[1]+0>'"$MEM_T"')c++}END{print c+0}' "$LOG_FILE")

echo "--- Threshold violations ---"
echo "  CPU  > ${CPU_T}%:  ${cpu_violations} times"
echo "  Mem  > ${MEM_T}%:  ${mem_violations} times"

if (( cpu_violations > 0 )); then
    echo ""
    echo "  CPU spike times:"
    awk -F'\t' '{split($2,a,"=");split(a[2],b,"%");if(b[1]+0>'"$CPU_T"')printf "    %s  cpu=%s\n",$1,$2}' "$LOG_FILE" | head -20
    remaining=$(( cpu_violations - 20 ))
    if (( remaining > 0 )); then
        echo "    ... and $remaining more"
    fi
fi

if (( mem_violations > 0 )); then
    echo ""
    echo "  Memory spike times:"
    awk -F'\t' '{split($3,a,"=");split(a[2],b,"%");if(b[1]+0>'"$MEM_T"')printf "    %s  mem=%s\n",$1,$3}' "$LOG_FILE" | head -20
    remaining=$(( mem_violations - 20 ))
    if (( remaining > 0 )); then
        echo "    ... and $remaining more"
    fi
fi
