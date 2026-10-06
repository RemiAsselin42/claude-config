#!/usr/bin/env bash
# Self-check for what scripts/vibe-toggle.sh writes, beyond tests/vibe-toggle.sh:
# the cases the review of the first version found (2026-10-06). A profile.md
# holds a learner's notes, so a toggle must leave every byte it does not own
# alone, and a write that fails must leave the file as it was.
#
#   bash tests/vibe-toggle-write.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
VT="$REPO_DIR/scripts/vibe-toggle.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; shift; local l; for l in "$@"; do printf '%s\n' "$l" | sed 's/^/     /'; done; fails=$((fails + 1)); }
same() {  # same <description> <expected file> <got file>
  if cmp -s "$2" "$3"; then ok "$1"; else ko "$1" "expected:" "$(od -c "$2" | tail -4)" "got:" "$(od -c "$3" | tail -4)"; fi
}
proj() {  # proj <name> → a git-initialised dir with an empty .vibe-wise/
  mkdir -p "$tmp/$1/.vibe-wise"; git -C "$tmp/$1" init -q -b main; printf '%s\n' "$tmp/$1"
}
status_of() { bash "$VT" status "$1" 2>/dev/null | tr -d '\r'; }

echo "== a profile with no final newline keeps none"
p=$(proj nonl); f="$p/.vibe-wise/profile.md"
printf '# Learner Profile\nLearning mode: active\nlast line' > "$f"
printf '# Learner Profile\nLearning mode: paused\nlast line' > "$tmp/nonl.want"
bash "$VT" off "$p" >/dev/null
same "off rewrites the mode line and adds no newline after the last line" "$tmp/nonl.want" "$f"

echo "== a mode line added to a CRLF profile ends with CRLF"
p=$(proj crlfadd); f="$p/.vibe-wise/profile.md"
printf '# Learner Profile\r\nOnboarding: complete\r\n' > "$f"
printf '# Learner Profile\r\nOnboarding: complete\r\nLearning mode: paused\r\n' > "$tmp/crlfadd.want"
bash "$VT" off "$p" >/dev/null
same "off appends 'Learning mode: paused' with the file's own line ending" "$tmp/crlfadd.want" "$f"

echo "== a mode line added after an unterminated last line"
p=$(proj nonladd); f="$p/.vibe-wise/profile.md"
printf '# Learner Profile\nOnboarding: complete' > "$f"
printf '# Learner Profile\nOnboarding: complete\nLearning mode: paused\n' > "$tmp/nonladd.want"
bash "$VT" off "$p" >/dev/null
same "off ends the last line, then adds the mode line" "$tmp/nonladd.want" "$f"

echo "== a learner's sentence that starts with 'Learning mode:' is not a marker"
p=$(proj prose); f="$p/.vibe-wise/profile.md"
note='Learning mode: paused on 2026-09-01 after the exam, resumed a week later'
printf '# Learner Profile\n\nLearning mode: active\n\n## Notes\n%s\n' "$note" > "$f"
bash "$VT" off "$p" >/dev/null
if grep -qxF "$note" "$f"; then ok "off leaves the sentence as written"; else ko "off leaves the sentence as written" "$(cat "$f")"; fi
[ "$(status_of "$p")" = "vibe-wise: off" ] && ok "status after off: off" || ko "status after off: off" "$(status_of "$p")"
bash "$VT" on "$p" >/dev/null
if grep -qxF "$note" "$f"; then ok "on leaves the sentence as written"; else ko "on leaves the sentence as written" "$(cat "$f")"; fi
[ "$(status_of "$p")" = "vibe-wise: on" ] && ok "status after on: on" || ko "status after on: on" "$(status_of "$p")"

echo "== a write that fails leaves the profile as it was"
# mv and cat fail: whichever the script uses to put the new content in place,
# the notes must come out whole. The stubs sit first on PATH for that call only.
p=$(proj failing); f="$p/.vibe-wise/profile.md"
printf '# Learner Profile\n\nLearning mode: active\nOnboarding: complete\n' > "$f"; cp "$f" "$tmp/failing.orig"
mkdir -p "$tmp/bin"
for tool in mv cat; do printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/bin/$tool"; chmod +x "$tmp/bin/$tool"; done
( export PATH="$tmp/bin:$PATH"; bash "$VT" off "$p" >/dev/null 2>"$tmp/failing.err" ); rc=$?
same "the profile is byte-identical after the failed off" "$tmp/failing.orig" "$f"
[ "$rc" -ne 0 ] && ok "the failed off exits non-zero" || ko "the failed off exits non-zero" "exit $rc"
[ -s "$tmp/failing.err" ] && ok "the failure is said on stderr" || ko "the failure is said on stderr"
left=""
for e in "$p/.vibe-wise"/* "$p/.vibe-wise"/.[!.]*; do
  [ -e "$e" ] || continue
  [ "${e##*/}" = profile.md ] || left+="${e##*/} "
done
[ -z "$left" ] && ok "no temporary file is left in the notes directory" || ko "no temporary file is left in the notes directory" "$left"

echo "== CDPATH does not send a relative dir elsewhere"
# ./sub belongs to a project that is on; CDPATH offers another sub, in a project
# that is paused. cd searches CDPATH first for a relative name.
a=$(proj cd-a); printf 'Learning mode: active\n' > "$a/.vibe-wise/profile.md"; mkdir -p "$a/sub"
b=$(proj cd-b); printf 'Learning mode: paused\n' > "$b/.vibe-wise/profile.md"; mkdir -p "$b/sub"
out=$( cd "$a" && CDPATH="$b" bash "$VT" status sub 2>/dev/null | tr -d '\r' )
[ "$out" = "vibe-wise: on" ] && ok "status sub answers for ./sub, on one line" || ko "status sub answers for ./sub, on one line" "$out"

echo
if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all vibe-toggle write checks passed"
