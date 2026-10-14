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
check "VibeWise line without notes"   "VibeWise │ Off · No notes"                                                "$full"
check "git branch and live diff"      "Github   │ ⎇ main · +1 -0"                                               "$full"
[ "$(printf '%s\n' "$full" | wc -l)" -eq 5 ] && echo "ok   exactly 5 lines" || { echo "FAIL line count: $(printf '%s\n' "$full" | wc -l)"; fails=$((fails + 1)); }

# No rate limits (API-key accounts) and no git dir: only Model + Cache.
sparse=$(render '{"model": {"display_name": "Opus"}, "workspace": {"current_dir": "/nonexistent-dir"},
  "context_window": {"context_window_size": 200000, "used_percentage": 80, "current_usage": null}}')
check "no effort, no suffix"          "Model    │ Opus"                                                          "$sparse"
check "null current_usage → 0 tokens" "Cache    │ 0/200k [████████░░] 80%"                                       "$sparse"
printf '%s\n' "$sparse" | grep -q "Usage"  && { echo "FAIL Usage line printed without rate_limits"; fails=$((fails + 1)); } || echo "ok   no Usage line without rate_limits"
printf '%s\n' "$sparse" | grep -q "Github" && { echo "FAIL Github line printed outside a repo"; fails=$((fails + 1)); }  || echo "ok   no Github line outside a repo"
printf '%s\n' "$sparse" | grep -q "VibeWise" && { echo "FAIL VibeWise line printed for a missing current_dir"; fails=$((fails + 1)); } || echo "ok   no VibeWise line for a missing current_dir"

# Harness drift found by the SessionStart hook (scripts/harness-drift.sh writes
# $CLAUDE_CONFIG_DIR/.harness-drift, one short line per level): one Harness line
# each, between VibeWise and Github; nothing without the marker (the renders above).
mkdir -p "$tmp/drift"
printf 'deployed ≠ clone: settings.json (permissions.allow), hooks/g.js\nclone ≠ origin/main: scripts/s.sh +2 more\n' > "$tmp/drift/.harness-drift"
drift=$(render_with "$tmp/drift" "$payload")
check "harness line, deployed level"  "Harness  │ ⚠ deployed ≠ clone: settings.json (permissions.allow), hooks/g.js" "$drift"
check "harness line, clone level"     "Harness  │ ⚠ clone ≠ origin/main: scripts/s.sh +2 more"                      "$drift"
[ "$(printf '%s\n' "$drift" | wc -l)" -eq 7 ] && echo "ok   exactly 7 lines with the two Harness lines" || { echo "FAIL line count with drift: $(printf '%s\n' "$drift" | wc -l)"; fails=$((fails + 1)); }
hn=$(printf '%s\n' "$drift" | grep -n '^Harness' | tail -1 | cut -d: -f1); gn=$(printf '%s\n' "$drift" | grep -n '^Github' | cut -d: -f1)
[ -n "$hn" ] && [ -n "$gn" ] && [ "$hn" -lt "$gn" ] && echo "ok   Harness lines come before Github" || { echo "FAIL Harness lines must come before Github"; fails=$((fails + 1)); }

# Weekly scoped limits the usage-scoped mod fetched (mods/usage-scoped writes
# $CLAUDE_CONFIG_DIR/.usage-scoped, one label<TAB>percent<TAB>resets_at line per
# window): one "Week <label>" segment each, after Week on the Usage line.
raw_with() {  # raw_with <CLAUDE_CONFIG_DIR> <payload>: the render, ANSI kept
  printf '%s' "$2" | CLAUDE_CONFIG_DIR="$1" TMPDIR="$tmp" bash "$SCRIPT"
}
has_line() {  # has_line <description> <exact line> <output>
  if printf '%s\n' "$3" | grep -qxF -- "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "     expected line: $2"; printf '%s\n' "$3" | sed 's/^/     got:      /'
    fails=$((fails + 1))
  fi
}
usage_now="Usage    │ Session · [████░░░░░░] 37% · 2h 12m | Week · [█░░░░░░░░░] 12% · 3d 4h"
fable="Week Fable · [█░░░░░░░░░] 12% · 3d 14h"
opus="Week Opus · [████░░░░░░] 40% · 1d 2h"
r_fable=$((now + 3 * 86400 + 14 * 3600 + 30)); r_opus=$((now + 86400 + 2 * 3600 + 30))

mkdir -p "$tmp/us1"
printf 'Fable\t12\t%s\n' "$r_fable" > "$tmp/us1/.usage-scoped"
us1=$(render_with "$tmp/us1" "$payload")
has_line "scoped segment after Week on the Usage line" "$usage_now | $fable" "$us1"
[ "$(printf '%s\n' "$us1" | wc -l)" -eq 5 ] && echo "ok   still exactly 5 lines with the scoped segment" || { echo "FAIL line count with .usage-scoped: $(printf '%s\n' "$us1" | wc -l)"; fails=$((fails + 1)); }

mkdir -p "$tmp/us-empty"
: > "$tmp/us-empty/.usage-scoped"
if [ "$(raw_with "$tmp/us-empty" "$payload")" = "$(raw_with "$tmp/nocfg" "$payload")" ]; then echo "ok   empty .usage-scoped: render byte-identical to no file"
else echo "FAIL empty .usage-scoped: render differs from no file"; fails=$((fails + 1)); fi

mkdir -p "$tmp/us-many"
{
  printf 'Fable\t12\t%s\n' "$r_fable"
  printf 'Bad\tx1\t%s\n' "$r_fable"
  printf 'Two\t5\n'
  printf 'Gap\t\t5\n'
  printf 'Opus\t40\t%s\n' "$r_opus"
} > "$tmp/us-many/.usage-scoped"
many=$(render_with "$tmp/us-many" "$payload")
has_line "two scoped segments in file order, malformed lines skipped" "$usage_now | $fable | $opus" "$many"

mkdir -p "$tmp/us-crlf"
while IFS= read -r l; do printf '%s\r\n' "$l"; done < "$tmp/us-many/.usage-scoped" > "$tmp/us-crlf/.usage-scoped"
has_line "CRLF .usage-scoped renders the same segments as LF" "$usage_now | $fable | $opus" "$(render_with "$tmp/us-crlf" "$payload")"

mkdir -p "$tmp/us-big"
printf 'Fable\t150\t%s\n' "$r_fable" > "$tmp/us-big/.usage-scoped"
has_line "scoped percent above 100 shown as 100" "$usage_now | Week Fable · [██████████] 100% · 3d 14h" "$(render_with "$tmp/us-big" "$payload")"

mkdir -p "$tmp/us-esc"
printf 'Fable\033[31m\t12\t%s\n' "$r_fable" > "$tmp/us-esc/.usage-scoped"
check "label escape dropped, segment still shown" "Week Fable" "$(render_with "$tmp/us-esc" "$payload")"
if raw_with "$tmp/us-esc" "$payload" | grep -qF -- "$(printf '\033[31m')"; then echo "FAIL raw render holds the label's \\x1b[31m"; fails=$((fails + 1))
else echo "ok   raw render holds no \\x1b[31m from the label"; fi

mkdir -p "$tmp/us-torn"
printf 'Fable\t12\t17' > "$tmp/us-torn/.usage-scoped"   # no line end: what a reader sees mid-write
if [ "$(raw_with "$tmp/us-torn" "$payload")" = "$(raw_with "$tmp/nocfg" "$payload")" ]; then echo "ok   unterminated last line skipped: render identical to no file"
else echo "FAIL unterminated last line rendered as a segment"; fails=$((fails + 1)); fi

nolimits='{"model": {"display_name": "Opus"}, "workspace": {"current_dir": "/nonexistent-dir"},
  "context_window": {"context_window_size": 200000, "used_percentage": 80, "current_usage": null}}'
has_line "Usage line holds the scoped segment alone without rate_limits" "Usage    │ $fable" "$(render_with "$tmp/us1" "$nolimits")"

if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all statusline checks passed"
