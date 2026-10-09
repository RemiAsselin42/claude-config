#!/usr/bin/env bash
# Switch the ponytail terse-mode plugin on or off (caveman left on 2026-10-09).
# Usage: style-toggle.sh [ponytail|off|status] [level]
#   Levels: lite, full (default), ultra
# Persistent state is the plugin's user config (defaultMode in
# $XDG_CONFIG_HOME|%APPDATA%|~/.config /ponytail/config.json): its SessionStart
# hook re-derives the .ponytail-active flag from it on EVERY session start
# (builtin default: full), so writing only the flag gets undone at the next
# session. The flag is still written here so the statusline updates immediately
# without waiting for a restart.
set -euo pipefail

D="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cmd="${1:-status}"
level="${2:-full}"

config_dir() {  # mirrors the plugin's own getConfigDir() resolution
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then printf '%s/ponytail' "$XDG_CONFIG_HOME"
  elif [[ -n "${APPDATA:-}" ]]; then printf '%s/ponytail' "$APPDATA"
  else printf '%s/.config/ponytail' "$HOME"
  fi
}

set_default() {  # $1 = mode
  local dir; dir="$(config_dir)"
  mkdir -p "$dir"
  printf '{ "defaultMode": "%s" }\n' "$1" > "$dir/config.json"
}

case "$cmd" in
  ponytail)
    set_default "$level"
    printf '%s\n' "$level" > "$D/.ponytail-active"
    echo "ponytail ON [$level] — restart session to apply"
    ;;
  off)
    set_default off
    rm -f "$D/.ponytail-active"
    echo "ponytail OFF — restart session to apply"
    ;;
  status)
    def=$(sed -n 's/.*"defaultMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$(config_dir)/config.json" 2>/dev/null || true)
    flag="$D/.ponytail-active"
    cur=$([[ -f "$flag" ]] && head -n1 "$flag" || echo "off")
    echo "ponytail: session=$cur default=${def:-full (plugin builtin)}"
    ;;
  *)
    echo "Usage: style-toggle.sh [ponytail|off|status] [level]" >&2
    exit 1
    ;;
esac
