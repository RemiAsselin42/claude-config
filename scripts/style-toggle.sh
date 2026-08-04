#!/usr/bin/env bash
# Switch the active terse-mode plugin: ponytail or caveman — never both
# (they both compress Claude's output; running the two together is redundant).
# Usage: style-toggle.sh [ponytail|caveman|off|status] [level]
#   Ponytail levels: lite, full (default), ultra
#   Caveman  levels: lite, full (default), ultra, wenyan-lite, wenyan-full, wenyan-ultra
# Persistent state is each plugin's user config (defaultMode in
# $XDG_CONFIG_HOME|%APPDATA%|~/.config /<plugin>/config.json): their
# SessionStart hooks re-derive the .{ponytail,caveman}-active flag from it on
# EVERY session start (builtin default: full), so writing only the flag gets
# undone at the next session. Flags are still written here so the statusline
# updates immediately without waiting for a restart.
set -euo pipefail

D="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cmd="${1:-status}"
level="${2:-full}"

config_dir() {  # $1 = plugin — mirrors the plugins' own getConfigDir() resolution
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then printf '%s/%s' "$XDG_CONFIG_HOME" "$1"
  elif [[ -n "${APPDATA:-}" ]]; then printf '%s/%s' "$APPDATA" "$1"
  else printf '%s/.config/%s' "$HOME" "$1"
  fi
}

set_default() {  # $1 = plugin, $2 = mode
  local dir; dir="$(config_dir "$1")"
  mkdir -p "$dir"
  printf '{ "defaultMode": "%s" }\n' "$2" > "$dir/config.json"
}

case "$cmd" in
  ponytail)
    set_default ponytail "$level"
    set_default caveman off
    printf '%s\n' "$level" > "$D/.ponytail-active"
    rm -f "$D/.caveman-active"
    echo "ponytail ON [$level] · caveman OFF — restart session to apply"
    ;;
  caveman)
    set_default caveman "$level"
    set_default ponytail off
    printf '%s\n' "$level" > "$D/.caveman-active"
    rm -f "$D/.ponytail-active"
    echo "caveman ON [$level] · ponytail OFF — restart session to apply"
    ;;
  off)
    set_default ponytail off
    set_default caveman off
    rm -f "$D/.ponytail-active" "$D/.caveman-active"
    echo "both OFF — restart session to apply"
    ;;
  status)
    for p in ponytail caveman; do
      def=$(sed -n 's/.*"defaultMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$(config_dir "$p")/config.json" 2>/dev/null)
      flag="$D/.${p}-active"
      cur=$([[ -f "$flag" ]] && head -n1 "$flag" || echo "off")
      echo "$p: session=$cur default=${def:-full (plugin builtin)}"
    done
    ;;
  *)
    echo "Usage: style-toggle.sh [ponytail|caveman|off|status] [level]" >&2
    exit 1
    ;;
esac
