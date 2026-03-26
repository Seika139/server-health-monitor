#!/usr/bin/env bats
# =============================================================================
# Tests for recovery state management (simulated from monitor.sh patterns)
# =============================================================================

setup() {
    ALERT_STATE_DIR="$(mktemp -d)/alert"
    mkdir -p "$ALERT_STATE_DIR"
    RECOVERY_SENT=""
}

teardown() {
    rm -rf "$(dirname "$ALERT_STATE_DIR")"
}

# Simulate fire_alert: marks type as alerting
fire_alert() {
    local type="$1"
    touch "$ALERT_STATE_DIR/$type"
}

# Simulate check_recovery: returns 0 and sets RECOVERY_SENT if recovery needed
check_recovery() {
    local type="$1"
    if [[ -f "$ALERT_STATE_DIR/$type" ]]; then
        RECOVERY_SENT="$type"
        rm -f "$ALERT_STATE_DIR/$type"
        return 0
    fi
    return 1
}

@test "recovery: no alert state means no recovery" {
    run check_recovery "cpu"
    [[ "$status" -eq 1 ]]
}

@test "recovery: after alert, recovery is triggered" {
    fire_alert "cpu"
    [[ -f "$ALERT_STATE_DIR/cpu" ]]
    check_recovery "cpu"
    [[ "$RECOVERY_SENT" == "cpu" ]]
    [[ ! -f "$ALERT_STATE_DIR/cpu" ]]
}

@test "recovery: double recovery does not fire twice" {
    fire_alert "memory"
    check_recovery "memory"
    run check_recovery "memory"
    [[ "$status" -eq 1 ]]
}

@test "recovery: different types are independent" {
    fire_alert "cpu"
    fire_alert "disk"
    check_recovery "cpu"
    [[ "$RECOVERY_SENT" == "cpu" ]]
    [[ -f "$ALERT_STATE_DIR/disk" ]]
}

@test "recovery: process-specific state tracking" {
    fire_alert "process_nginx"
    fire_alert "process_mysqld"
    check_recovery "process_nginx"
    [[ "$RECOVERY_SENT" == "process_nginx" ]]
    [[ -f "$ALERT_STATE_DIR/process_mysqld" ]]
}
