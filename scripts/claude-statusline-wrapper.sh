#!/usr/bin/env bash
set -u

raw_input="$(cat)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
capture_dir="$claude_dir/token-widget"
capture_file="$capture_dir/claude-rate-limits.json"

mkdir -p "$capture_dir"

if [ -n "$raw_input" ] && command -v python3 >/dev/null 2>&1; then
  TOKEN_WIDGET_STATUSLINE_RAW="$raw_input" python3 - "$capture_file" <<'PY'
import json
import os
import sys
import time

capture_file = sys.argv[1]
raw = os.environ.get("TOKEN_WIDGET_STATUSLINE_RAW", "")

try:
    payload = json.loads(raw)
except Exception:
    sys.exit(0)

rate_limits = payload.get("rate_limits")
if not isinstance(rate_limits, dict):
    sys.exit(0)

def compact_window(name):
    window = rate_limits.get(name)
    if not isinstance(window, dict):
        return None

    used = window.get("used_percentage")
    reset = window.get("resets_at")

    if not isinstance(used, (int, float)):
        return None

    result = {"used_percentage": float(used)}
    if isinstance(reset, (int, float)) and reset > 0:
        result["resets_at"] = float(reset)
    return result

compact = {
    "five_hour": compact_window("five_hour"),
    "seven_day": compact_window("seven_day"),
}
compact = {key: value for key, value in compact.items() if value is not None}

if not compact:
    sys.exit(0)

document = {
    "captured_at": time.time(),
    "source": "Claude Code statusLine stdin",
    "rate_limits": compact,
}

tmp_path = f"{capture_file}.tmp"
with open(tmp_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, separators=(",", ":"))
os.replace(tmp_path, capture_file)
PY
fi

if [ -n "${TOKEN_WIDGET_STATUSLINE_FORWARD_COMMAND:-}" ]; then
  printf '%s' "$raw_input" | bash -lc "$TOKEN_WIDGET_STATUSLINE_FORWARD_COMMAND"
else
  printf 'Claude'
fi

