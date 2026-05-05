#!/usr/bin/env bash
# Toggle caveman mode on/off with optional intensity level.
# Usage: caveman-toggle.sh [on|off|toggle|inject|status] [level]
#   Levels: lite, full (default), ultra, wenyan-lite, wenyan-full, wenyan-ultra
#   toggle (default) — flip current state (preserves current level)
#   inject           — idempotent inject if flag exists (called by install.sh)
#   status           — print current state and level without changing it
set -euo pipefail

FLAG="$HOME/.claude/caveman.enabled"
LEVEL_FILE="$HOME/.claude/caveman.level"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

get_level() {
  if [[ -f "$LEVEL_FILE" ]]; then
    cat "$LEVEL_FILE"
  else
    echo "full"
  fi
}

caveman_block() {
  local level="${1:-full}"
  local rules=""

  case "$level" in
    lite)
      rules='No filler or hedging. Keep articles and full sentences. Professional but tight.

- Never say: "I will now", "Let me", "Sure!", "Certainly", "Of course", "Great question", "Happy to help"
- No trailing summaries of what you just did
- No apologies or preamble
- Technical precision mandatory
- Code, paths, commands: always complete and exact'
      ;;
    full)
      rules='Respond terse. Drop filler. No pleasantries. Fragments ok.

- Never say: "I will now", "Let me", "Sure!", "Certainly", "Of course", "Great question", "Happy to help"
- No trailing summaries of what you just did
- No apologies, hedging, or preamble
- Technical precision mandatory — brevity never sacrifices accuracy
- Code, paths, commands: always complete and exact'
      ;;
    ultra)
      rules='Max compression. Abbreviate (DB/auth/config/req/res/fn/impl). Strip conjunctions. Arrows for causality (X → Y). No filler, no pleasantries, no summaries.

- Drop articles, prepositions where unambiguous
- Never say: "I will now", "Let me", "Sure!", "Certainly", "Of course"
- Code, paths, commands: exact'
      ;;
    wenyan-lite)
      rules='Semi-classical register. Drop filler and hedging, keep grammar structure.

- Classical tone, modern grammar
- No pleasantries, no summaries, no apologies
- Technical precision mandatory'
      ;;
    wenyan-full)
      rules='文言文 mode. Maximum classical terseness. 80-90% character reduction. Classical sentence patterns: verb-before-object, omit subject, classical particles.

- No filler, no pleasantries, no summaries
- Technical terms intact'
      ;;
    wenyan-ultra)
      rules='極簡文言。Extreme classical compression. Maximum terseness, minimal characters. Ancient scholar on a budget.

- Every character earns its place
- Technical terms abbreviated where unambiguous'
      ;;
    *)
      echo "Unknown level: $level. Valid: lite, full, ultra, wenyan-lite, wenyan-full, wenyan-ultra" >&2
      exit 1
      ;;
  esac

  printf '\n<!-- caveman:start -->\n\n## Caveman Mode [%s]\n\n%s\n\n<!-- caveman:end -->\n' "$level" "$rules"
}

inject_block() {
  local level="${1:-$(get_level)}"
  [[ -f "$CLAUDE_MD" ]] || return 0
  if grep -qF "<!-- caveman:start -->" "$CLAUDE_MD" 2>/dev/null; then
    # Replace existing block
    local block
    block="$(caveman_block "$level")"
    awk -v block="$block" '
      /<!-- caveman:start -->/ { skip=1; printf "%s\n", block; next }
      /<!-- caveman:end -->/ && skip { skip=0; next }
      skip { next }
      { print }
    ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
  else
    # Prepend so caveman rules appear before all other instructions
    { caveman_block "$level"; echo; cat "$CLAUDE_MD"; } > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
  fi
}

remove_block() {
  [[ -f "$CLAUDE_MD" ]] || return 0
  grep -qF "<!-- caveman:start -->" "$CLAUDE_MD" 2>/dev/null || return 0
  awk '
    /<!-- caveman:end -->/ && skip { skip=0; next }
    skip { next }
    /<!-- caveman:start -->/ { skip=1; next }
    { print }
  ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
}

cmd="${1:-toggle}"
level_arg="${2:-}"

case "$cmd" in
  on)
    level="${level_arg:-full}"
    echo "$level" > "$LEVEL_FILE"
    touch "$FLAG"
    inject_block "$level"
    echo "caveman ON [$level] — restart session to apply"
    ;;
  off)
    rm -f "$FLAG"
    remove_block
    echo "caveman OFF — restart session to apply"
    ;;
  inject)
    if [[ -f "$FLAG" ]]; then
      inject_block "$(get_level)"
    fi
    ;;
  status)
    if [[ -f "$FLAG" ]]; then
      echo "caveman ON [$(get_level)]"
    else
      echo "caveman OFF"
    fi
    ;;
  toggle)
    if [[ -f "$FLAG" ]]; then
      rm -f "$FLAG"
      remove_block
      echo "caveman OFF — restart session to apply"
    else
      level="${level_arg:-full}"
      echo "$level" > "$LEVEL_FILE"
      touch "$FLAG"
      inject_block "$level"
      echo "caveman ON [$level] — restart session to apply"
    fi
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Usage: caveman-toggle.sh [on|off|toggle|inject|status] [level]" >&2
    exit 1
    ;;
esac
