#!/usr/bin/env bash
# Self-check for scripts/statusline.sh: feed a fixture payload, strip ANSI,
# assert each line. Run after touching the script:
#
#   bash tests/statusline.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/statusline.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/nocfg"   # empty CLAUDE_CONFIG_DIR: no plugin badge, no effort fallback

# A repo on branch main with one modified tracked file (+1 -0).
git -C "$tmp" init -q -b main
printf 'x\n' > "$tmp/f"
git -C "$tmp" add f
git -C "$tmp" -c user.email=t@t -c user.name=t commit -q -m init
printf 'x\ny\n' > "$tmp/f"

now=$(date +%s)
render_with() {  # render_with <CLAUDE_CONFIG_DIR> <payload>
  printf '%s' "$2" | CLAUDE_CONFIG_DIR="$1" TMPDIR="$tmp" bash "$SCRIPT" | sed 's/\x1b\[[0-9;]*m//g'
}
render() { render_with "$tmp/nocfg" "$1"; }

fails=0
check() {  # check <description> <expected-line> <output>
  if printf '%s\n' "$3" | grep -qF -- "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "     expected: $2"; printf '%s\n' "$3" | sed 's/^/     got:      /'
    fails=$((fails + 1))
  fi
}

payload="{
  \"model\": {\"display_name\": \"Fable 5\"}, \"effort\": {\"level\": \"xhigh\"},
  \"workspace\": {\"current_dir\": \"$tmp\"},
  \"context_window\": {\"context_window_size\": 1000000, \"used_percentage\": 22,
    \"current_usage\": {\"input_tokens\": 200000, \"cache_creation_input_tokens\": 10000, \"cache_read_input_tokens\": 10000}},
  \"rate_limits\": {\"five_hour\": {\"used_percentage\": 37.4, \"resets_at\": $((now + 7920 + 30))},
                    \"seven_day\": {\"used_percentage\": 12, \"resets_at\": $((now + 3 * 86400 + 4 * 3600 + 30))}}
}"
full=$(render "$payload")
check "model line with effort"        "Model    │ Fable 5 · xhigh"                                              "$full"
check "context tokens, bar, percent"  "Cache    │ 220k/1M [██░░░░░░░░] 22%"                                     "$full"
check "5h and 7d rate limits"         "Usage    │ Session · [████░░░░░░] 37% · 2h 12m | Week · [█░░░░░░░░░] 12% · 3d 4h" "$full"
check "git branch and live diff"      "Github   │ ⎇ main · +1 -0"                                               "$full"
[ "$(printf '%s\n' "$full" | wc -l)" -eq 4 ] && echo "ok   exactly 4 lines" || { echo "FAIL line count: $(printf '%s\n' "$full" | wc -l)"; fails=$((fails + 1)); }

# No rate limits (API-key accounts) and no git dir: only Model + Cache.
sparse=$(render '{"model": {"display_name": "Opus"}, "workspace": {"current_dir": "/nonexistent-dir"},
  "context_window": {"context_window_size": 200000, "used_percentage": 80, "current_usage": null}}')
check "no effort, no suffix"          "Model    │ Opus"                                                          "$sparse"
check "null current_usage → 0 tokens" "Cache    │ 0/200k [████████░░] 80%"                                       "$sparse"
printf '%s\n' "$sparse" | grep -q "Usage"  && { echo "FAIL Usage line printed without rate_limits"; fails=$((fails + 1)); } || echo "ok   no Usage line without rate_limits"
printf '%s\n' "$sparse" | grep -q "Github" && { echo "FAIL Github line printed outside a repo"; fails=$((fails + 1)); }  || echo "ok   no Github line outside a repo"

# Harness drift found by the SessionStart hook (scripts/harness-drift.sh writes
# $CLAUDE_CONFIG_DIR/.harness-drift, one short line per level): one Harness line
# each, between VibeWise and Github; nothing without the marker (the renders above).
mkdir -p "$tmp/drift"
printf 'deployed ≠ clone: settings.json (permissions.allow), hooks/g.js\nclone ≠ origin/main: scripts/s.sh +2 more\n' > "$tmp/drift/.harness-drift"
drift=$(render_with "$tmp/drift" "$payload")
check "harness line, deployed level"  "Harness  │ ⚠ deployed ≠ clone: settings.json (permissions.allow), hooks/g.js" "$drift"
check "harness line, clone level"     "Harness  │ ⚠ clone ≠ origin/main: scripts/s.sh +2 more"                      "$drift"
[ "$(printf '%s\n' "$drift" | wc -l)" -eq 6 ] && echo "ok   exactly 6 lines with the two Harness lines" || { echo "FAIL line count with drift: $(printf '%s\n' "$drift" | wc -l)"; fails=$((fails + 1)); }
hn=$(printf '%s\n' "$drift" | grep -n '^Harness' | tail -1 | cut -d: -f1); gn=$(printf '%s\n' "$drift" | grep -n '^Github' | cut -d: -f1)
[ -n "$hn" ] && [ -n "$gn" ] && [ "$hn" -lt "$gn" ] && echo "ok   Harness lines come before Github" || { echo "FAIL Harness lines must come before Github"; fails=$((fails + 1)); }

if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all statusline checks passed"
