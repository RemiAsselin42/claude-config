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
  # Hook writes are routed `require` (install.sh): a hook goes through the
  # daemon or skips its write, and may not start the daemon itself (latency
  # budget, upstream's rule). So the daemon starts here, once per session:
  # ~1 s to ask, ~2 s to start and be ready (measured 2026-10-07).
  timeout 20 mempalace daemon status >/dev/null 2>&1 \
    || timeout 30 mempalace daemon start >/dev/null 2>&1 || true
  # Diary wing: wing_ + directory name, lowercased, '-' and ' ' → '_'. Mirrors
  # _diary_wing_for_repo in install.sh — this script runs standalone from
  # ~/.claude/scripts and cannot source it.
  wing="wing_$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr ' -' '__')"
  # wake-up lists one CHECKPOINT line per saved turn, newest first; keep the
  # newest line of each session and trim the prompt excerpt.
  wake=$(mktemp) && err=$(mktemp)
  timeout 15 mempalace wake-up --wing "$wing" >"$wake" 2>"$err"
  rc=$?
  diary=$(sed -n 's/^  - CHECKPOINT:\([0-9-]*\)|session:\([^|]*\)|msgs:[0-9]*|recent:\(.*\)$/\1\t\2\t\3/p' "$wake" \
    | awk -F'\t' '!seen[$2]++ { printf "- %s — %.160s\n", $1, $3 }' | head -3)
  [ -n "$diary" ] && out+="## Last sessions here (MemPalace $wing)"$'\n'"$diary"$'\n'
  # A mempalace that cannot even start (an import error, the outage of
  # 2026-10-04) stayed invisible for two days: every hook silences it. One
  # capped line, only then; a timeout (124) is slow, not down.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
    why=$(grep -i 'error' "$err" | tail -1 | cut -c1-120)   # Python prints the exception last
    out+="## MemPalace is down on this machine"$'\n'"${why:-exit $rc} — run install.sh (close the other sessions first)"$'\n'
  fi
  rm -f "$wake" "$err"
fi

[ -n "$out" ] && printf '%s' "$out"
exit 0
