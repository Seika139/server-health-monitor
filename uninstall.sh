#!/usr/bin/env bash
# =============================================================================
# uninstall.sh - Remove server-health-monitor from the system
# Run as root: sudo bash uninstall.sh
# =============================================================================
set -euo pipefail

INSTALL_DIR="/opt/health-monitor"
LOG_DIR="/var/log/health-monitor"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo bash uninstall.sh)" >&2
    exit 1
fi

echo "=== server-health-monitor uninstaller ==="
echo ""

# ---------------------------------------------------------------------------
# Choose mode
# ---------------------------------------------------------------------------
echo "Select uninstall mode:"
echo "  1) Stop only     - disable timer, keep files and logs"
echo "  2) Uninstall      - remove health-monitor files and systemd units"
echo "  3) Full cleanup  - also remove atop, sysstat, and all logs"
echo ""
read -rp "Choice [1/2/3]: " choice

case "$choice" in
    1)
        echo ""
        echo "[1/1] Stopping health-monitor timer..."
        systemctl disable --now health-monitor.timer 2>/dev/null || true
        echo "  -> timer stopped and disabled"
        echo ""
        echo "Done. Files and logs are preserved."
        echo "To restart: sudo systemctl enable --now health-monitor.timer"
        ;;
    2)
        echo ""
        echo "[1/3] Stopping health-monitor timer..."
        systemctl disable --now health-monitor.timer 2>/dev/null || true
        systemctl stop health-monitor.service 2>/dev/null || true

        echo "[2/3] Removing systemd units and install directory..."
        rm -f /etc/systemd/system/health-monitor.service
        rm -f /etc/systemd/system/health-monitor.timer
        systemctl daemon-reload
        rm -f /etc/logrotate.d/health-monitor
        rm -rf "$INSTALL_DIR"

        echo "[3/3] Cleaning up state files..."
        rm -rf /var/log/health-monitor/.cooldown
        rm -rf /var/log/health-monitor/.alert

        echo ""
        echo "Done. health-monitor has been removed."
        echo "Logs are preserved at: $LOG_DIR"
        echo "atop and sysstat are still running (use option 3 to remove them too)."
        ;;
    3)
        echo ""
        read -rp "This will remove atop, sysstat, and ALL logs. Continue? [y/N]: " confirm
        if [[ "$confirm" != [yY] ]]; then
            echo "Aborted."
            exit 0
        fi

        echo "[1/5] Stopping health-monitor timer..."
        systemctl disable --now health-monitor.timer 2>/dev/null || true
        systemctl stop health-monitor.service 2>/dev/null || true

        echo "[2/5] Removing systemd units and install directory..."
        rm -f /etc/systemd/system/health-monitor.service
        rm -f /etc/systemd/system/health-monitor.timer
        systemctl daemon-reload
        rm -f /etc/logrotate.d/health-monitor
        rm -rf "$INSTALL_DIR"

        echo "[3/5] Stopping and removing atop and sysstat..."
        systemctl disable --now atop 2>/dev/null || true
        systemctl disable --now sysstat 2>/dev/null || true
        apt-get remove --purge -y atop sysstat 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true

        echo "[4/5] Removing all logs..."
        rm -rf "$LOG_DIR"

        echo "[5/5] Done."
        echo ""
        echo "Full cleanup complete. All components have been removed."
        ;;
    *)
        echo "Invalid choice. Exited."
        exit 1
        ;;
esac
