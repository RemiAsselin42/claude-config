#!/usr/bin/env bash
# Turn the vibe-wise plugin's learning mode on or off for one project, and say
# which it is. Unlike the terse modes of style-toggle.sh, nothing here is global:
# the plugin keeps the mode per project, as the "Learning mode:" line of
# <project>/.vibe-wise/profile.md, which its SessionStart hook reads at every
# session start, /clear and compaction.
# Usage: vibe-toggle.sh [on|off|status] [dir]      no command = status, dir = cwd
#   status → "vibe-wise: on [normal]" | "vibe-wise: on" | "vibe-wise: off" | "vibe-wise: none …"
# The first activation in a project is not done here: it is /vibe-wise:learn, the
# plugin's onboarding, which asks its questions through pickers.
# scripts/statusline.sh calls `status` on every render, so reading a profile
# spawns no process: bash builtins only.
# Check: bash tests/vibe-toggle.sh
set -uo pipefail
shopt -s nocasematch   # the plugin reads its marker whatever the case

cmd="${1:-status}"
dir="${2:-.}"

case "$cmd" in
  on|off|status) ;;
  *) echo "Usage: vibe-toggle.sh [on|off|status] [dir]" >&2; exit 1 ;;
esac

PAUSED_RE='^learning mode:[[:space:]]*paused[[:space:]]*$'
FREQ_RE='^checkpoint frequency:[[:space:]]*(light|normal|frequent)[[:space:]]*$'

# Mirrors state_directory() of the plugin's hooks/session_start.py (read at
# 1135f4a), so that `status` says what the hook will do: from the physical dir
# upward, .vibe-wise before the legacy .sensible-vibes; the first one that exists
# in any form decides, and a file or a symlink there means no notes, with no
# fallback to the other name or to a parent; never past the level holding .git.
profile=""
find_profile() {
  local d s
  cd -P -- "$dir" 2>/dev/null || return 0
  d=$PWD
  while :; do
    # ${d%/}: at the root this gives "/.vibe-wise"; "//.vibe-wise" is a network
    # path for MSYS, which then waits on a host of that name.
    for s in "${d%/}/.vibe-wise" "${d%/}/.sensible-vibes"; do
      [ -e "$s" ] || [ -L "$s" ] || continue
      if [ -d "$s" ] && [ ! -L "$s" ] && [ -f "$s/profile.md" ] && [ ! -L "$s/profile.md" ]; then
        profile="$s/profile.md"
      fi
      return 0
    done
    [ -e "${d%/}/.git" ] && return 0
    [ "$d" = / ] && return 0
    d=${d%/*}; d=${d:-/}
  done
}

# Mirrors profile_is_active(): active = at least one non-blank line and no line
# that is, whole, "Learning mode: paused". A blank profile is no notes at all.
state=none
freq=""
read_state() {
  local line content=0 paused=0
  [ -n "$profile" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ [^[:space:]] ]] && content=1
    [[ $line =~ $PAUSED_RE ]] && paused=1
    [ -z "$freq" ] && [[ $line =~ $FREQ_RE ]] && freq=${BASH_REMATCH[1]}
  done < "$profile"
  # nocasematch applies to case too: this is the lowercasing, without ${var,,}
  # (bash 4) or a tr process.
  case "$freq" in light) freq=light ;; normal) freq=normal ;; frequent) freq=frequent ;; esac
  if   (( ! content )); then state=none
  elif (( paused ));    then state=off
  else                       state=on
  fi
}

# Rewrites every "Learning mode:" line and nothing else; a CR at the end of a
# line stays where it is (BINMODE: gawk on Windows must not touch them either).
set_mode() {  # $1 = active | paused
  local tmp rc
  tmp=$(mktemp) || return 1
  # ponytail: a profile with no mode line gets "paused" appended at the end, not
  # near the top where the plugin's template keeps it; the hook scans the whole file.
  awk -v BINMODE=3 -v v="$1" '
    tolower($0) ~ /^learning mode:/ { sub(/^[^\r]*/, "Learning mode: " v); seen = 1 }
    { print }
    END { if (!seen && v == "paused") print "Learning mode: paused" }
  ' "$profile" > "$tmp" && cat "$tmp" > "$profile"
  rc=$?
  rm -f "$tmp"
  return $rc
}

find_profile
read_state

if [ "$state" = none ]; then
  echo "vibe-wise: none — no learning notes for this project; type /vibe-wise:learn to start"
  exit 0
fi

case "$cmd" in
  status)
    if [ "$state" = on ]; then echo "vibe-wise: on${freq:+ [$freq]}"; else echo "vibe-wise: off"; fi
    ;;
  on)
    set_mode active || exit 1
    echo "vibe-wise ON — restored at the next session start, /clear or compaction; /vibe-wise:learn starts it now"
    ;;
  off)
    set_mode paused || exit 1
    echo "vibe-wise OFF — paused in ${profile%/*}"
    ;;
esac
