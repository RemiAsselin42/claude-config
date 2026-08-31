#!/usr/bin/env bash
# Claude Code SessionStart hook: what the last sessions in this repo were about
# (MemPalace diary, newest 3) plus the head of TODO.md. Stdout is injected into
# the session context (~200 tokens) — the useful part of beads' `bd prime`,
# without the binary. Also fires after /compact, restoring the same anchors.
# Never blocks a session: every step is optional and the exit code is always 0.
out=""

if [ -s TODO.md ]; then
  out+="## TODO.md"$'\n'"$(grep -v '^[[:space:]]*$' TODO.md | head -15)"$'\n\n'
fi

if command -v mempalace >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  # Diary wing: wing_ + directory name, lowercased, '-' and ' ' → '_'. Mirrors
  # _diary_wing_for_repo in install.sh — this script runs standalone from
  # ~/.claude/scripts and cannot source it.
  wing="wing_$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr ' -' '__')"
  # wake-up lists one CHECKPOINT line per saved turn, newest first; keep the
  # newest line of each session and trim the prompt excerpt.
  diary=$(timeout 5 mempalace wake-up --wing "$wing" 2>/dev/null \
    | sed -n 's/^  - CHECKPOINT:\([0-9-]*\)|session:\([^|]*\)|msgs:[0-9]*|recent:\(.*\)$/\1\t\2\t\3/p' \
    | awk -F'\t' '!seen[$2]++ { printf "- %s — %.160s\n", $1, $3 }' | head -3)
  [ -n "$diary" ] && out+="## Last sessions here (MemPalace $wing)"$'\n'"$diary"$'\n'
fi

[ -n "$out" ] && printf '%s' "$out"
exit 0
