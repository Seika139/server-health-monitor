#!/usr/bin/env bash
# =============================================================================
# install.sh - Set up server-health-monitor on an Ubuntu server
# Run as root: sudo bash install.sh
# =============================================================================
set -euo pipefail

INSTALL_DIR="/opt/health-monitor"
LOG_DIR="/var/log/health-monitor"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: This script is intended for Linux (Ubuntu) only" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo bash install.sh)" >&2
    exit 1
fi

echo "=== server-health-monitor installer ==="

# ---------------------------------------------------------------------------
# 1. Install dependencies
# ---------------------------------------------------------------------------
echo "[1/7] Installing packages (atop, sysstat, curl)..."
apt-get update -qq
apt-get install -y -qq atop sysstat curl > /dev/null

# Enable atop daemon with 10-second interval
if [[ -f /etc/default/atop ]]; then
    sed -i 's/^INTERVAL=.*/INTERVAL=10/' /etc/default/atop
fi
systemctl enable --now atop
echo "  -> atop enabled (10s interval)"

# Enable sysstat (sar) collection
if [[ -f /etc/default/sysstat ]]; then
    sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
fi
systemctl enable --now sysstat
echo "  -> sysstat enabled"

# ---------------------------------------------------------------------------
# 2. Copy files to install directory
# ---------------------------------------------------------------------------
echo "[2/7] Installing to $INSTALL_DIR..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$INSTALL_DIR/scripts"
for script in monitor.sh alert.sh heartbeat.sh status.sh test-alert.sh analyze.sh validate-config.sh; do
    if [[ -f "$SCRIPT_DIR/scripts/$script" ]]; then
        cp "$SCRIPT_DIR/scripts/$script" "$INSTALL_DIR/scripts/"
    fi
done
chmod +x "$INSTALL_DIR/scripts/"*.sh
cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/uninstall.sh"

# Only copy config.env if it doesn't exist yet (preserve existing config)
if [[ ! -f "$INSTALL_DIR/config.env" ]]; then
    cp "$SCRIPT_DIR/config.env" "$INSTALL_DIR/config.env"
    chmod 600 "$INSTALL_DIR/config.env"
    echo "  -> config.env installed (mode 600, EDIT THIS: set DISCORD_WEBHOOK_URL)"
else
    chmod 600 "$INSTALL_DIR/config.env"
    echo "  -> config.env already exists, preserving your settings (ensured mode 600)"
    # Show new config keys that the user may want to add
    new_keys=$(grep -E '^[A-Z_]+=.' "$SCRIPT_DIR/config.env" | sed 's/=.*//' | sort)
    existing_keys=$(grep -E '^[A-Z_]+=.' "$INSTALL_DIR/config.env" | sed 's/=.*//' | sort)
    missing_keys=$(comm -23 <(echo "$new_keys") <(echo "$existing_keys"))
    if [[ -n "$missing_keys" ]]; then
        echo "  -> NEW config keys available (consider adding to your config.env):"
        while IFS= read -r key; do
            default=$(grep -E "^${key}=" "$SCRIPT_DIR/config.env" | head -1)
            echo "       $default"
        done <<< "$missing_keys"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Create log directory
# ---------------------------------------------------------------------------
echo "[3/7] Creating log directory $LOG_DIR..."
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# 4. Set up logrotate
# ---------------------------------------------------------------------------
echo "[4/7] Configuring logrotate..."
# shellcheck source=config.env
source "$INSTALL_DIR/config.env"
RETENTION="${LOG_RETENTION_DAYS:-30}"
cat > /etc/logrotate.d/health-monitor <<LOGROTATE
/var/log/health-monitor/*.log {
    daily
    rotate ${RETENTION}
    compress
    delaycompress
    missingok
    notifempty
}
LOGROTATE
echo "  -> logrotate configured (rotate ${RETENTION} days)"

# ---------------------------------------------------------------------------
# 5. Install systemd units
# ---------------------------------------------------------------------------
echo "[5/7] Installing systemd timer..."
cp "$SCRIPT_DIR/systemd/health-monitor.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/health-monitor.timer"   /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now health-monitor.timer
echo "  -> health-monitor.timer enabled and started"

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------
echo "[6/7] Verifying..."
echo ""
systemctl status health-monitor.timer --no-pager || true

# ---------------------------------------------------------------------------
# 7. Validate config
# ---------------------------------------------------------------------------
echo ""
echo "[7/7] Validating configuration..."
bash "$INSTALL_DIR/scripts/validate-config.sh" "$INSTALL_DIR/config.env" || true
echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit $INSTALL_DIR/config.env and set DISCORD_WEBHOOK_URL"
echo "  2. Validate:       sudo bash $INSTALL_DIR/scripts/validate-config.sh"
echo "  3. Test alert:     sudo bash $INSTALL_DIR/scripts/test-alert.sh"
echo "  4. Check status:   sudo bash $INSTALL_DIR/scripts/status.sh"
echo "  5. Analyze logs:   sudo bash $INSTALL_DIR/scripts/analyze.sh [YYYY-MM-DD]"
echo ""
echo "Post-mortem investigation with atop:"
echo "  atop -r /var/log/atop/atop_$(date +%Y%m%d)"
echo ""
