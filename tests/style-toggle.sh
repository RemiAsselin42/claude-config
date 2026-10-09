#!/usr/bin/env bash
# Self-check for scripts/style-toggle.sh: ponytail on (plugin config + session
# flag), off (config off, flag gone), status, and the refusal of any other
# plugin name — caveman left the harness on 2026-10-09.
#
#   bash tests/style-toggle.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
ST="$REPO_DIR/scripts/style-toggle.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CLAUDE_CONFIG_DIR="$tmp/claude" XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$CLAUDE_CONFIG_DIR"

fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; shift; local l; for l in "$@"; do printf '     %s\n' "$l"; done; fails=$((fails + 1)); }
is_eq() {   # is_eq <description> <expected> <got>
  if [ "$3" = "$2" ]; then ok "$1"; else ko "$1" "expected: $2" "got:      $3"; fi
}
exists() { [ -e "$1" ] && echo true || echo false; }

echo "== 1. ponytail ultra: plugin config and session flag"
out=$(bash "$ST" ponytail ultra)
is_eq "1 config.json holds defaultMode ultra" '{ "defaultMode": "ultra" }' "$(cat "$tmp/xdg/ponytail/config.json")"
is_eq "1 .ponytail-active holds ultra" ultra "$(cat "$CLAUDE_CONFIG_DIR/.ponytail-active")"
is_eq "1 says ponytail ON [ultra]" "ponytail ON [ultra] — restart session to apply" "$out"

echo "== 2. status: one line, session and default"
is_eq "2 status" "ponytail: session=ultra default=ultra" "$(bash "$ST" status)"
is_eq "2 no argument = status" "ponytail: session=ultra default=ultra" "$(bash "$ST")"

echo "== 3. ponytail without a level = full"
bash "$ST" ponytail >/dev/null
is_eq "3 flag full" full "$(cat "$CLAUDE_CONFIG_DIR/.ponytail-active")"

echo "== 4. off: config off, flag removed"
out=$(bash "$ST" off)
is_eq "4 config.json holds defaultMode off" '{ "defaultMode": "off" }' "$(cat "$tmp/xdg/ponytail/config.json")"
is_eq "4 no flag" false "$(exists "$CLAUDE_CONFIG_DIR/.ponytail-active")"
is_eq "4 says ponytail OFF" "ponytail OFF — restart session to apply" "$out"
is_eq "4 status after off" "ponytail: session=off default=off" "$(bash "$ST" status)"

echo "== 5. caveman is refused: exit 1, usage, nothing written"
out=$(bash "$ST" caveman full 2>&1); rc=$?
is_eq "5 exit code 1" 1 "$rc"
is_eq "5 usage names ponytail, off, status only" "Usage: style-toggle.sh [ponytail|off|status] [level]" "$out"
is_eq "5 no caveman config written" false "$(exists "$tmp/xdg/caveman")"
is_eq "5 ponytail config untouched" '{ "defaultMode": "off" }' "$(cat "$tmp/xdg/ponytail/config.json")"

echo "== 6. status with no config: the plugin's builtin default"
rm -rf "$tmp/xdg/ponytail"
is_eq "6 status" "ponytail: session=off default=full (plugin builtin)" "$(bash "$ST" status)"

echo
if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all style-toggle checks passed"
