#!/usr/bin/env bash
# Claude Code SessionStart hook: what the last sessions in this repo were about
# (MemPalace diary, newest 3), the head of TODO.md, and the integrity of the
# deployed harness (scripts/harness-drift.sh: deployed ≠ clone, clone ≠ origin).
# Stdout is injected into the session context (~200 tokens) — the useful part of
# beads' `bd prime`, without the binary. Also fires after /compact, restoring the
# same anchors. A drift is shown to the human as well: the output then takes the
# hooks' JSON form, additionalContext plus systemMessage (jq needed; without it,
# plain text and the statusline alone). Never blocks a session: every step is
# optional and the exit code is always 0.
out=""
warn=""

if [ -s TODO.md ]; then
  out+="## TODO.md"$'\n'"$(grep -v '^[[:space:]]*$' TODO.md | head -15)"$'\n\n'
fi

if command -v mempalace >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  # Hook writes are routed `require` (install.sh): a hook goes through the
  # daemon or skips its write, and may not start the daemon itself (latency
  # budget, upstream's rule). So the daemon starts here, once per session:
  # `daemon start` is a no-op on a running daemon (1.3 s), 1.9 s otherwise
  # (measured 2026-10-07). Without HF_HUB_OFFLINE, which settings.json sets for
  # the hooks: a daemon that inherits it can never download the embedding
  # model, and every job it takes then fails inside it, out of sight.
  env -u HF_HUB_OFFLINE timeout 30 mempalace daemon start >/dev/null 2>&1 || true
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

# Harness drift: the script beside this one prints one full line per drift and
# writes the short form the statusline reads ($CLAUDE_CONFIG_DIR/.harness-drift).
here=${BASH_SOURCE[0]%/*}; [ "$here" = "${BASH_SOURCE[0]}" ] && here=.
drift=$(bash "$here/harness-drift.sh" 2>/dev/null)
if [ -n "$drift" ]; then
  out+="## Harness drift"$'\n'"$drift"$'\n'
  out+="deployed ≠ clone: run install.sh --only claude from the clone. clone ≠ origin: the clone's working tree is not what the remote holds (branch, fetch, local edits)."$'\n'
  warn="Harness drift — ${drift//$'\n'/ — }. Deployed ≠ clone: install.sh --only claude. Clone ≠ origin: the clone is not what the remote holds."
fi

if [ -n "$warn" ] && command -v jq >/dev/null 2>&1; then
  jq -cn --arg ctx "$out" --arg msg "$warn" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}, systemMessage: $msg}'
else
  [ -n "$out" ] && printf '%s' "$out"
fi
exit 0
