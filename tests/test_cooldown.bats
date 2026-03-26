#!/usr/bin/env bats
# =============================================================================
# Tests for cooldown logic (simulated from alert.sh patterns)
# =============================================================================

setup() {
    COOLDOWN_DIR="$(mktemp -d)/cooldown"
    mkdir -p "$COOLDOWN_DIR"
}

teardown() {
    rm -rf "$(dirname "$COOLDOWN_DIR")"
}

# Simulate cooldown check as done in alert.sh
should_send() {
    local alert_type="$1"
    local cooldown_seconds="$2"
    local cooldown_file="$COOLDOWN_DIR/$alert_type"

    if [[ -f "$cooldown_file" ]]; then
        local last_alert now elapsed
        last_alert=$(cat "$cooldown_file")
        now=$(date +%s)
        elapsed=$(( now - last_alert ))
        if (( elapsed < cooldown_seconds )); then
            return 1  # suppressed
        fi
    fi
    return 0  # should send
}

record_cooldown() {
    local alert_type="$1"
    date +%s > "$COOLDOWN_DIR/$alert_type"
}

@test "cooldown: first alert always sends" {
    run should_send "cpu" 300
    [[ "$status" -eq 0 ]]
}

@test "cooldown: duplicate alert within cooldown is suppressed" {
    record_cooldown "cpu"
    run should_send "cpu" 300
    [[ "$status" -eq 1 ]]
}

@test "cooldown: different alert types are independent" {
    record_cooldown "cpu"
    run should_send "memory" 300
    [[ "$status" -eq 0 ]]
}

@test "cooldown: expired cooldown allows send" {
    # Write a timestamp 400 seconds in the past
    echo $(( $(date +%s) - 400 )) > "$COOLDOWN_DIR/cpu"
    run should_send "cpu" 300
    [[ "$status" -eq 0 ]]
}

@test "cooldown: zero cooldown always allows send" {
    record_cooldown "cpu"
    sleep 1
    run should_send "cpu" 0
    [[ "$status" -eq 0 ]]
}
