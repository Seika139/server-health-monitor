#!/usr/bin/env bats
# =============================================================================
# Tests for json_escape function from alert.sh
# =============================================================================

setup() {
    # Extract json_escape as a standalone function for testing
    json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\r'/}"
        s="${s//$'\t'/\\t}"
        printf '%s' "$s"
    }
}

@test "json_escape: plain text passes through unchanged" {
    result=$(json_escape "hello world")
    [[ "$result" == "hello world" ]]
}

@test "json_escape: escapes double quotes" {
    result=$(json_escape 'say "hello"')
    [[ "$result" == 'say \"hello\"' ]]
}

@test "json_escape: escapes backslashes" {
    result=$(json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "json_escape: escapes newlines" {
    result=$(json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

@test "json_escape: escapes tabs" {
    result=$(json_escape $'col1\tcol2')
    [[ "$result" == 'col1\tcol2' ]]
}

@test "json_escape: strips carriage returns" {
    result=$(json_escape $'windows\r\nline')
    [[ "$result" == 'windows\nline' ]]
}

@test "json_escape: result is valid inside JSON string" {
    # Verify that escaped output can be embedded in a JSON string
    input=$'line1\nline2\ttab'
    result=$(json_escape "$input")
    json="{\"msg\": \"${result}\"}"
    # Basic check: no raw newlines or tabs in the JSON
    [[ "$json" != *$'\n'* ]]
    [[ "$json" != *$'\t'* ]]
}

@test "json_escape: empty string" {
    result=$(json_escape "")
    [[ "$result" == "" ]]
}
