#!/usr/bin/env bash
# Switch the active terse-mode plugin: ponytail or caveman — never both
# (they both compress Claude's output; running the two together is redundant).
# Usage: style-toggle.sh [ponytail|caveman|off|status] [level]
#   Ponytail levels: lite, full (default), ultra
#   Caveman  levels: lite, full (default), ultra, wenyan-lite, wenyan-full, wenyan-ultra
# State is the plugins' own flag files (.ponytail-active / .caveman-active in
# $CLAUDE_CONFIG_DIR, default ~/.claude): each plugin's hooks and statusline
# badge activate on its flag's presence, so no settings.json change is needed.
set -euo pipefail

D="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cmd="${1:-status}"
level="${2:-full}"

case "$cmd" in
  ponytail)
    printf '%s\n' "$level" > "$D/.ponytail-active"
    rm -f "$D/.caveman-active"
    echo "ponytail ON [$level] · caveman OFF — restart session to apply"
    ;;
  caveman)
    printf '%s\n' "$level" > "$D/.caveman-active"
    rm -f "$D/.ponytail-active"
    echo "caveman ON [$level] · ponytail OFF — restart session to apply"
    ;;
  off)
    rm -f "$D/.ponytail-active" "$D/.caveman-active"
    echo "both OFF — restart session to apply"
    ;;
  status)
    [[ -f "$D/.ponytail-active" ]] && echo "ponytail ON [$(head -n1 "$D/.ponytail-active")]"
    [[ -f "$D/.caveman-active" ]] && echo "caveman ON [$(head -n1 "$D/.caveman-active")]"
    [[ -f "$D/.ponytail-active" || -f "$D/.caveman-active" ]] || echo "both OFF"
    ;;
  *)
    echo "Usage: style-toggle.sh [ponytail|caveman|off|status] [level]" >&2
    exit 1
    ;;
esac
