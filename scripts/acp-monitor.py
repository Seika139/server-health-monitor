#!/usr/bin/env python3
"""ACP セッションのコンテキスト使用状況を監視する。

sessions.json と Claude Code トランスクリプトを読み取り、
閾値を超えたセッションがあれば Discord Webhook で通知する。

Environment Variables:
    DISCORD_WEBHOOK_URL      Discord Webhook URL (必須)
    ACP_MONITOR_WARN         警告閾値 (default: 0.7)
    ACP_MONITOR_DANGER       危険閾値 (default: 0.85)
    ACP_MONITOR_SESSIONS     sessions.json のパス (default: ~/.openclaw/agents/claude/sessions)
    ACP_MONITOR_PROJECTS     Claude projects ディレクトリ (default: ~/.claude/projects)
    ALERT_COOLDOWN           同一アラート抑制秒数 (default: 300)
    SERVER_NAME              通知に表示するサーバー名
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

SESSIONS_DIR = Path(
    os.environ.get("ACP_MONITOR_SESSIONS")
    or str(Path.home() / ".openclaw/agents/claude/sessions")
)
PROJECTS_DIR = Path(
    os.environ.get("ACP_MONITOR_PROJECTS")
    or str(Path.home() / ".claude/projects")
)

CONTEXT_WINDOW = 200_000
WARN_THRESHOLD = float(os.environ.get("ACP_MONITOR_WARN", "0.7"))
DANGER_THRESHOLD = float(os.environ.get("ACP_MONITOR_DANGER", "0.85"))
COOLDOWN_SECONDS = int(os.environ.get("ALERT_COOLDOWN", "300"))
SERVER_NAME = os.environ.get("SERVER_NAME", "")

COOLDOWN_DIR = Path("/var/log/health-monitor/.cooldown")

COLOR_GREEN = 3066993
COLOR_YELLOW = 15844367
COLOR_RED = 16711680


def load_sessions() -> dict:
    sessions_file = SESSIONS_DIR / "sessions.json"
    if not sessions_file.exists():
        print(f"Error: {sessions_file} not found", file=sys.stderr)
        sys.exit(1)
    with open(sessions_file) as f:
        return json.load(f)


def find_transcript(acpx_session_id: str) -> Path | None:
    if not PROJECTS_DIR.exists():
        return None
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        transcript = project_dir / f"{acpx_session_id}.jsonl"
        if transcript.exists():
            return transcript
    return None


def resolve_label(session: dict, transcript_path: Path | None) -> str:
    label = session.get("label")
    if label:
        return label
    group_channel = session.get("groupChannel")
    if group_channel:
        return group_channel
    if transcript_path:
        dir_name = transcript_path.parent.name
        parts = dir_name.split("-")
        if "programs" in parts:
            idx = parts.index("programs")
            return "-".join(parts[idx + 1 :])
        if "dotfiles" in parts:
            return "dotfiles"
        return dir_name
    acp = session.get("acp", {})
    cwd = acp.get("cwd") or acp.get("runtimeOptions", {}).get("cwd")
    if cwd:
        return Path(cwd).name
    return "(unknown)"


def analyze_transcript(transcript_path: Path) -> dict:
    last_context = 0
    total_output = 0
    last_assistant_msg = ""
    assistant_count = 0

    with open(transcript_path) as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type", "")
            message = obj.get("message", {})

            if msg_type == "assistant":
                usage = message.get("usage", {})
                if usage:
                    context = (
                        usage.get("input_tokens", 0)
                        + usage.get("cache_creation_input_tokens", 0)
                        + usage.get("cache_read_input_tokens", 0)
                    )
                    if context > 0:
                        last_context = context
                    total_output += usage.get("output_tokens", 0)
                    assistant_count += 1

                content = message.get("content", "")
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text = block.get("text", "").strip()
                            if text:
                                last_assistant_msg = text[:200]
                                break
                elif isinstance(content, str) and content.strip():
                    last_assistant_msg = content.strip()[:200]

    return {
        "last_context": last_context,
        "total_output": total_output,
        "turns": assistant_count,
        "last_assistant_msg": last_assistant_msg,
    }


def collect_session_data() -> list[dict]:
    sessions = load_sessions()
    results = []

    for key, session in sessions.items():
        acp = session.get("acp", {})
        acpx_id = acp.get("identity", {}).get("acpxSessionId")
        if not acpx_id:
            continue

        transcript = find_transcript(acpx_id)
        label = resolve_label(session, transcript)
        state = acp.get("state") or "unknown"
        mode = acp.get("mode") or "unknown"
        ratio = 0.0

        entry = {
            "key": key,
            "label": label,
            "state": state,
            "mode": mode,
            "last_context": 0,
            "total_output": 0,
            "turns": 0,
            "last_assistant_msg": "",
            "ratio": 0.0,
        }

        if transcript:
            stats = analyze_transcript(transcript)
            entry.update(stats)
            entry["ratio"] = min(stats["last_context"] / CONTEXT_WINDOW, 1.0)

        results.append(entry)

    return results


# --- Cooldown ---


def check_cooldown(alert_key: str) -> bool:
    """True if alert should be suppressed."""
    cooldown_file = COOLDOWN_DIR / f"acp_{alert_key}"
    if not cooldown_file.exists():
        return False
    try:
        last_alert = int(cooldown_file.read_text().strip())
        return (int(time.time()) - last_alert) < COOLDOWN_SECONDS
    except (ValueError, OSError):
        return False


def record_cooldown(alert_key: str):
    try:
        COOLDOWN_DIR.mkdir(parents=True, exist_ok=True)
        (COOLDOWN_DIR / f"acp_{alert_key}").write_text(str(int(time.time())))
    except OSError:
        pass


# --- Terminal output ---


def context_bar(tokens: int, width: int = 30) -> str:
    ratio = min(tokens / CONTEXT_WINDOW, 1.0)
    filled = int(ratio * width)
    empty = width - filled
    if ratio >= DANGER_THRESHOLD:
        color = "\033[31m"
    elif ratio >= WARN_THRESHOLD:
        color = "\033[33m"
    else:
        color = "\033[32m"
    reset = "\033[0m"
    bar = f"{color}{'█' * filled}{'░' * empty}{reset}"
    return f"[{bar}] {ratio:.0%} ({tokens:,} / {CONTEXT_WINDOW:,})"


def format_last_activity(session_data: dict, sessions: dict) -> str:
    for key, session in sessions.items():
        acp = session.get("acp", {})
        if acp.get("identity", {}).get("acpxSessionId") and key == session_data["key"]:
            ts = acp.get("lastActivityAt")
            if not ts:
                return "N/A"
            dt = datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
            now = datetime.now(tz=timezone.utc)
            delta = now - dt
            if delta.days > 0:
                return f"{delta.days}d ago ({dt.strftime('%m/%d %H:%M')} UTC)"
            hours = delta.seconds // 3600
            if hours > 0:
                return f"{hours}h ago ({dt.strftime('%H:%M')} UTC)"
            return f"{delta.seconds // 60}m ago"
    return "N/A"


def print_terminal(entries: list[dict]):
    sessions = load_sessions()
    print("=" * 80)
    print("  ACP Session Status")
    print("=" * 80)
    print()

    for e in entries:
        icon = "🟢" if e["state"] == "idle" else "🔴" if e["state"] == "running" else "⚪"
        activity = format_last_activity(e, sessions)
        print(f"{icon} {e['label']}")
        print(f"  State: {e['state']}  |  Mode: {e['mode']}  |  Last: {activity}")

        if e["last_context"] > 0 or e["turns"] > 0:
            print(f"  Context: {context_bar(e['last_context'])}")
            print(f"  Output: {e['total_output']:,} tokens  |  Turns: {e['turns']}")
            if e["last_assistant_msg"]:
                print(f"  Last: {e['last_assistant_msg'].replace(chr(10), ' ')}")
        else:
            print("  Transcript: not found")
        print()

    print("=" * 80)
    print(f"  Context window: {CONTEXT_WINDOW:,} tokens")
    print(f"  Warn: {WARN_THRESHOLD:.0%}  |  Danger: {DANGER_THRESHOLD:.0%}")
    print("=" * 80)


# --- Discord alert ---


def text_bar(ratio: float, width: int = 20) -> str:
    filled = int(ratio * width)
    empty = width - filled
    return f"`{'█' * filled}{'░' * empty}`"


def send_discord_alert(webhook_url: str, entries: list[dict]):
    alerts = [e for e in entries if e["ratio"] >= WARN_THRESHOLD]
    if not alerts:
        return

    server = SERVER_NAME or "(unknown)"
    embeds = []

    for e in alerts:
        alert_key = e["key"].split(":")[-1][:12]
        if check_cooldown(alert_key):
            continue

        ratio = e["ratio"]
        tokens = e["last_context"]
        if ratio >= DANGER_THRESHOLD:
            color = COLOR_RED
            level = "DANGER"
        else:
            color = COLOR_YELLOW
            level = "WARNING"

        desc_lines = [
            f"**Context**: {text_bar(ratio)} {ratio:.0%} ({tokens:,} / {CONTEXT_WINDOW:,})",
            f"**State**: {e['state']} | **Mode**: {e['mode']}",
            f"**Turns**: {e['turns']} | **Output**: {e['total_output']:,} tokens",
        ]
        if e["last_assistant_msg"]:
            summary = e["last_assistant_msg"].replace("\n", " ")[:150]
            desc_lines.append(f"**Last**: {summary}")

        embeds.append(
            {
                "title": f"[{level}] {e['label']} - {server}",
                "description": "\n".join(desc_lines),
                "color": color,
                "timestamp": datetime.now(tz=timezone.utc).isoformat(),
            }
        )
        record_cooldown(alert_key)

    if not embeds:
        return

    payload = json.dumps({"embeds": embeds}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "ACP-Session-Monitor/1.0",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in (200, 204):
                print(f"Discord alert sent ({len(embeds)} session(s))")
    except urllib.error.HTTPError as err:
        if err.code == 429:
            print("Discord rate limited, skipping", file=sys.stderr)
        else:
            print(f"Discord error: {err.code} {err.reason}", file=sys.stderr)
    except urllib.error.URLError as err:
        print(f"Discord connection error: {err.reason}", file=sys.stderr)


# --- JSON output ---


def print_json(entries: list[dict]):
    output = [
        {
            "label": e["label"],
            "state": e["state"],
            "mode": e["mode"],
            "last_context": e["last_context"],
            "context_ratio": round(e["ratio"], 3),
            "total_output": e["total_output"],
            "turns": e["turns"],
            "last_assistant_msg": e["last_assistant_msg"],
        }
        for e in entries
    ]
    print(json.dumps(output, ensure_ascii=False, indent=2))


# --- main ---


def main():
    parser = argparse.ArgumentParser(description="ACP Session Context Monitor")
    parser.add_argument("--alert", action="store_true", help="Send Discord alerts")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--quiet", action="store_true", help="Suppress terminal output")
    args = parser.parse_args()

    entries = collect_session_data()

    if args.json:
        print_json(entries)
    elif not args.quiet:
        print_terminal(entries)

    if args.alert:
        webhook_url = os.environ.get("DISCORD_WEBHOOK_URL")
        if not webhook_url:
            print("Error: DISCORD_WEBHOOK_URL is not set", file=sys.stderr)
            sys.exit(1)
        send_discord_alert(webhook_url, entries)


if __name__ == "__main__":
    main()
