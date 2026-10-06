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
ACTIVE_RE='^learning mode:[[:space:]]*active[[:space:]]*$'
FREQ_RE='^checkpoint frequency:[[:space:]]*(light|normal|frequent)[[:space:]]*$'

# Mirrors state_directory() of the plugin's hooks/session_start.py (read at
# 1135f4a), so that `status` says what the hook will do: from the physical dir
# upward, .vibe-wise before the legacy .sensible-vibes; the first one that exists
# in any form decides, and a file or a symlink there means no notes, with no
# fallback to the other name or to a parent; never past the level holding .git.
# One known difference, on Windows: an NTFS junction is a link for bash's -L and
# a plain directory for Python's is_symlink(). The hook restores through it; this
# script answers "none" and never writes through it (checked 2026-10-06).
profile=""
find_profile() {
  local d s
  [ "$dir" = - ] && dir=./-   # cd reads a lone "-" as $OLDPWD, even after --
  # CDPATH: cd looks there first for a relative name, and would answer for a
  # same-named directory of another project.
  CDPATH='' cd -P -- "$dir" >/dev/null 2>&1 || return 0
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

# Flips the plugin's markers and nothing else. A marker is a whole line, the
# form the hook matches: a learner's sentence that starts with "Learning mode:"
# is not one and comes out as written, like every other line, its CR and a
# missing final newline included. `on` turns the paused markers active; `off`
# turns the active ones paused and adds a marker when the profile has none.
# The new content is written beside the profile and renamed over it: a write
# that fails leaves the notes as they were (the first version emptied the file
# before writing it, review of 2026-10-06).
set_mode() {  # $1 = active | paused
  local from=$ACTIVE_RE tmp="$profile.tmp.$$" line nl cr="" eol="" paused=0
  [ "$1" = active ] && from=$PAUSED_RE
  cp -p "$profile" "$tmp" 2>/dev/null || return 1   # the copy carries the file's mode
  {
    while :; do
      nl=$'\n'
      IFS= read -r line || { [ -n "$line" ] || break; nl=""; }   # "": no newline after the last line
      cr=""; [[ $line == *$'\r' ]] && cr=$'\r' && eol=$'\r'
      [[ $line =~ $from ]] && line="Learning mode: $1$cr"
      [[ $line =~ $PAUSED_RE ]] && paused=1
      printf '%s%s' "$line" "$nl"
      [ -n "$nl" ] || break
    done
    if [ "$1" = paused ] && (( ! paused )); then
      # ponytail: the marker is appended at the end, not near the top where the
      # plugin's template keeps it; the hook scans the whole file.
      [ -n "$nl" ] || printf '%s\n' "$eol"
      printf 'Learning mode: paused%s\n' "$eol"
    fi
  } < "$profile" > "$tmp" && mv -f "$tmp" "$profile" && return 0
  rm -f "$tmp"
  return 1
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
  on|off)
    mode=active; [ "$cmd" = off ] && mode=paused
    if ! set_mode "$mode"; then
      echo "vibe-toggle: could not rewrite $profile, left as it was" >&2
      exit 1
    fi
    if [ "$cmd" = on ]; then
      echo "vibe-wise ON — restored at the next session start, /clear or compaction; /vibe-wise:learn starts it now"
    else
      echo "vibe-wise OFF — paused in ${profile%/*}"
    fi
    ;;
esac
