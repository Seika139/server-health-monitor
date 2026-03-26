#!/usr/bin/env bats
# =============================================================================
# Tests for validate-config.sh
# =============================================================================

VALIDATE_SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-config.sh"

setup() {
    TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMPDIR"
}

write_config() {
    cat > "$TMPDIR/config.env" <<'BASE'
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/test"
SERVER_NAME="test-server"
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
SWAP_THRESHOLD=50
DISK_THRESHOLD=90
LOAD_THRESHOLD_MULTIPLIER=2
LOG_RETENTION_DAYS=30
ALERT_COOLDOWN=300
TOP_PROCESSES=5
HEARTBEAT_URL=""
HEARTBEAT_METHOD="GET"
WATCH_PROCESSES=""
BASE
}

@test "validate: valid config passes" {
    write_config
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"PASSED"* ]]
}

@test "validate: missing webhook URL is warning (not error)" {
    write_config
    sed -i.bak 's|DISCORD_WEBHOOK_URL=.*|DISCORD_WEBHOOK_URL=""|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"WARNING"* ]]
}

@test "validate: non-https webhook URL is error" {
    write_config
    sed -i.bak 's|DISCORD_WEBHOOK_URL=.*|DISCORD_WEBHOOK_URL="http://example.com"|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must start with https"* ]]
}

@test "validate: CPU threshold out of range is error" {
    write_config
    sed -i.bak 's|CPU_THRESHOLD=.*|CPU_THRESHOLD=150|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must be between 1 and 100"* ]]
}

@test "validate: non-integer threshold is error" {
    write_config
    sed -i.bak 's|MEMORY_THRESHOLD=.*|MEMORY_THRESHOLD=abc|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must be an integer"* ]]
}

@test "validate: WATCH_PROCESSES with spaces in name is error" {
    write_config
    sed -i.bak 's|WATCH_PROCESSES=.*|WATCH_PROCESSES="my process"|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"contains spaces"* ]]
}

@test "validate: valid HEARTBEAT_URL passes" {
    write_config
    sed -i.bak 's|HEARTBEAT_URL=.*|HEARTBEAT_URL="https://hc-ping.com/abc"|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 0 ]]
}

@test "validate: invalid HEARTBEAT_URL is error" {
    write_config
    sed -i.bak 's|HEARTBEAT_URL=.*|HEARTBEAT_URL="ftp://example.com"|' "$TMPDIR/config.env"
    run bash "$VALIDATE_SCRIPT" "$TMPDIR/config.env"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must start with http"* ]]
}
