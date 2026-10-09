#!/usr/bin/env bash
# Self-check for the vibe-wise integration: scripts/vibe-toggle.sh (the toggle
# and the per-project lookup), the VibeWise line of scripts/statusline.sh, and
# the wiring in settings.json, install.sh, mods/ and commands/vibe-toggle.md. Every
# fixture project is a throwaway `git init`ed directory, so the upward lookup
# stops there and never reaches notes above the temp directory.
#
#   bash tests/vibe-toggle.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
VT="$REPO_DIR/scripts/vibe-toggle.sh"
SL="$REPO_DIR/scripts/statusline.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/nocfg" "$tmp/p"   # empty CLAUDE_CONFIG_DIR: no terse-mode badge

fails=0
ok() { echo "ok   $1"; }
ko() {  # ko <description> [detail lines...]
  echo "FAIL $1"; shift
  [ -f "$VT" ] || echo "     (scripts/vibe-toggle.sh does not exist)"
  local l; for l in "$@"; do printf '%s\n' "$l" | sed 's/^/     /'; done
  fails=$((fails + 1))
}
is_eq() {   # is_eq <description> <expected> <got>
  if [ "$3" = "$2" ]; then ok "$1"; else ko "$1" "expected: $2" "got:      $3"; fi
}
starts() {  # starts <description> <prefix> <got>: some line of <got> starts with <prefix>
  if [[ $'\n'"$3" == *$'\n'"$2"* ]]; then ok "$1"; else ko "$1" "expected a line starting: $2" "got:      $3"; fi
}
has_line() {  # has_line <description> <exact line> <got>
  if printf '%s\n' "$3" | grep -qxF -- "$2"; then ok "$1"; else ko "$1" "expected line: $2" "got:" "$3"; fi
}

# ── Fixtures ──────────────────────────────────────────────────────────────────
newproj() {  # newproj <name> → prints the path of a fresh git-initialised dir
  local d="$tmp/p/$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  printf '%s\n' "$d"
}
# A profile.md in the shape the plugin writes (skills/learn/state-templates.md).
write_profile() {  # write_profile <file> <mode line|""> <frequency|"">
  mkdir -p "$(dirname "$1")"
  {
    printf '# Learner Profile\n\n'
    if [ -n "$2" ]; then printf '%s\n' "$2"; fi
    printf 'Onboarding: complete\n\n## Project\nSituation: New\nBuilding: a todo app\n'
    printf 'Codebase familiarity: none\nLearning scope: entire system\n\n'
    printf '## Experience\nOverall programming: Beginner\nStack familiarity: Not specified\n\n'
    printf '## Goals\nPrimary: ship it\nCapability goal: Not specified\n\n## Preferences\n'
    if [ -n "$3" ]; then printf 'Checkpoint frequency: %s\n' "$3"; fi
    printf 'Question style: Open-ended\nImplementation style: AI writes code\n\n'
    printf '## Strong Concepts\nNo demonstrated understanding recorded yet.\n\n'
    printf '## Developing Concepts\nNone recorded yet.\n\n## Revisit\nNone recorded yet.\n'
  } > "$1"
}
to_crlf() {  # to_crlf <file>: rewrite in place with CRLF line endings
  local l
  while IFS= read -r l; do printf '%s\r\n' "$l"; done < "$1" > "$1.crlf" && mv "$1.crlf" "$1"
}

# ── Probes ────────────────────────────────────────────────────────────────────
vt_in() {  # vt_in <cwd> <args...>: stdout of the toggle, CR stripped; stderr → $tmp/err
  local d=$1; shift
  ( cd "$d" && bash "$VT" "$@" ) 2>"$tmp/err" | tr -d '\r'
}
paused_in() { tr -d '\r' < "$1" | grep -Eiq '^learning mode:[[:space:]]*paused[[:space:]]*$'; }
active_in() { tr -d '\r' < "$1" | grep -Eiq '^learning mode:[[:space:]]*active[[:space:]]*$'; }
# Every line other than a `Learning mode:` line is byte-identical, CR included
# (-U: Git Bash's grep strips CR without it).
same_but_mode() { cmp -s <(grep -Uvi '^learning mode:' "$1") <(grep -Uvi '^learning mode:' "$2"); }
snap() {  # snap <dir>: names and checksums of everything under <dir>
  ( cd "$1" && find . | LC_ALL=C sort && find . -type f | LC_ALL=C sort | while IFS= read -r f; do cksum < "$f"; done )
}

payload() {  # payload <current_dir>
  jq -n --arg d "$1" '{model: {display_name: "Fable 5"}, workspace: {current_dir: $d},
    context_window: {context_window_size: 1000000, used_percentage: 0}}'
}
render_with() {  # render_with <config dir> <payload>
  printf '%s' "$2" | CLAUDE_CONFIG_DIR="$1" TMPDIR="$tmp" bash "$SL" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r'
}
render() { render_with "$tmp/nocfg" "$(payload "$1")"; }
no_vibe() { ! printf '%s\n' "$1" | grep -q VibeWise; }

# ══ Toggle script ═════════════════════════════════════════════════════════════

echo "== 1. status on an active profile (R2)"
p=$(newproj t1a); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' ''
out=$(vt_in "$p" status); rc=$?
starts "1 status, active profile with no frequency: line starts 'vibe-wise: on'" 'vibe-wise: on' "$out"
is_eq  "1 status exits 0" 0 "$rc"
p=$(newproj t1b); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' Normal
is_eq  "1 status, Checkpoint frequency: Normal: exactly 'vibe-wise: on [normal]'" 'vibe-wise: on [normal]' "$(vt_in "$p" status)"

echo "== 2. off pauses an active profile (R2)"
p=$(newproj t2); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: active' Normal; cp "$f" "$tmp/t2.orig"
out=$(vt_in "$p" off); rc=$?
starts "2 off prints a line starting 'vibe-wise OFF'" 'vibe-wise OFF' "$out"
is_eq  "2 off exits 0" 0 "$rc"
if tr -d '\r' < "$f" | grep -qxF 'Learning mode: paused'; then ok "2 profile holds 'Learning mode: paused'"; else ko "2 profile holds 'Learning mode: paused'" "$(cat "$f")"; fi
if paused_in "$f" && ! active_in "$f"; then ok "2 no 'Learning mode: active' line left"; else ko "2 no 'Learning mode: active' line left" "$(grep -i '^learning mode' "$f")"; fi
if paused_in "$f" && same_but_mode "$tmp/t2.orig" "$f"; then ok "2 every other line unchanged"; else ko "2 every other line unchanged (or not paused)" "$(diff "$tmp/t2.orig" "$f")"; fi
is_eq  "2 status after off: 'vibe-wise: off'" 'vibe-wise: off' "$(vt_in "$p" status)"

echo "== 3. on activates a paused profile (R2)"
p=$(newproj t3); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: paused' Normal; cp "$f" "$tmp/t3.orig"
out=$(vt_in "$p" on); rc=$?
starts "3 on prints a line starting 'vibe-wise ON'" 'vibe-wise ON' "$out"
is_eq  "3 on exits 0 on a paused project" 0 "$rc"
if tr -d '\r' < "$f" | grep -qxF 'Learning mode: active'; then ok "3 profile holds 'Learning mode: active'"; else ko "3 profile holds 'Learning mode: active'" "$(cat "$f")"; fi
if ! paused_in "$f"; then ok "3 no paused line anywhere"; else ko "3 no paused line anywhere" "$(grep -i '^learning mode' "$f")"; fi
if active_in "$f" && same_but_mode "$tmp/t3.orig" "$f"; then ok "3 every other line unchanged"; else ko "3 every other line unchanged (or not active)" "$(diff "$tmp/t3.orig" "$f")"; fi
starts "3 status after on starts 'vibe-wise: on'" 'vibe-wise: on' "$(vt_in "$p" status)"

echo "== 4. off and on are idempotent (R2)"
p=$(newproj t4); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: active' Normal
vt_in "$p" off >/dev/null; cp "$f" "$tmp/t4.off1"; vt_in "$p" off >/dev/null
if [ -f "$VT" ] && paused_in "$tmp/t4.off1" && cmp -s "$tmp/t4.off1" "$f"; then ok "4 off twice = off once"; else ko "4 off twice = off once (first off must pause)" "$(diff "$tmp/t4.off1" "$f")"; fi
vt_in "$p" on >/dev/null; cp "$f" "$tmp/t4.on1"; vt_in "$p" on >/dev/null
if [ -f "$VT" ] && ! paused_in "$tmp/t4.on1" && cmp -s "$tmp/t4.on1" "$f"; then ok "4 on twice = on once"; else ko "4 on twice = on once" "$(diff "$tmp/t4.on1" "$f")"; fi

echo "== 5. off on a profile with no Learning mode line (R2)"
p=$(newproj t5); f="$p/.vibe-wise/profile.md"
write_profile "$f" '' Normal; cp "$f" "$tmp/t5.orig"
vt_in "$p" off >/dev/null
modes=$(tr -d '\r' < "$f" | grep -i '^learning mode:')
is_eq "5 exactly one mode line, 'Learning mode: paused'" 'Learning mode: paused' "$modes"
if [ -n "$modes" ] && same_but_mode "$tmp/t5.orig" "$f"; then ok "5 every existing line kept"; else ko "5 every existing line kept (or no line added)" "$(diff "$tmp/t5.orig" "$f")"; fi

echo "== 6. paused marker far down, odd case and spacing (R2)"
p=$(newproj t6); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: active' Normal
printf '\n## Notes\nSome note.\nlearning mode:   PAUSED  \n' >> "$f"
is_eq "6 status reads 'vibe-wise: off'" 'vibe-wise: off' "$(vt_in "$p" status)"
vt_in "$p" on >/dev/null
if [ -f "$VT" ] && ! paused_in "$f"; then ok "6 after on no line matches the paused form in any case"; else ko "6 after on no line matches the paused form in any case" "$(grep -i 'learning mode' "$f")"; fi

echo "== 7. no notes (R2)"
p=$(newproj t7)
for cmd in status on off; do
  out=$(vt_in "$p" "$cmd"); rc=$?
  if [[ $out == "vibe-wise: none"* && $out == *"/vibe-wise:learn"* ]]; then ok "7 $cmd: 'vibe-wise: none' naming /vibe-wise:learn"
  else ko "7 $cmd: 'vibe-wise: none' naming /vibe-wise:learn" "got: $out"; fi
  [ "$cmd" = on ] || is_eq "7 $cmd exits 0 in state none" 0 "$rc"
done
if [ -f "$VT" ] && [ ! -e "$p/.vibe-wise" ]; then ok "7 no .vibe-wise created"; else ko "7 no .vibe-wise created"; fi

echo "== 8. default command and unknown command (R2)"
p=$(newproj t8); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' Normal
is_eq "8 no argument behaves as status" 'vibe-wise: on [normal]' "$(vt_in "$p")"
vt_in "$p" frobnicate >/dev/null; rc=$?
is_eq "8 unknown command exits 1" 1 "$rc"
if grep -qi usage "$tmp/err"; then ok "8 unknown command prints a usage line on stderr"; else ko "8 unknown command prints a usage line on stderr" "stderr: $(cat "$tmp/err")"; fi

echo "== 9. from a subdirectory (R2)"
p=$(newproj t9); f="$p/.vibe-wise/profile.md"; mkdir -p "$p/src/deep"
write_profile "$f" 'Learning mode: active' Normal
vt_in "$p/src/deep" off >/dev/null
if paused_in "$f"; then ok "9 off run from a subdirectory pauses the project's profile"; else ko "9 off run from a subdirectory pauses the project's profile"; fi
write_profile "$f" 'Learning mode: active' Normal
vt_in "$tmp" off "$p/src/deep" >/dev/null
if paused_in "$f"; then ok "9 off with the subdirectory as dir pauses the project's profile"; else ko "9 off with the subdirectory as dir pauses the project's profile"; fi

echo "== 10. nested repository stops the lookup (R2)"
p=$(newproj t10); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: active' Normal; cp "$f" "$tmp/t10.orig"
mkdir -p "$p/libdir"; git -C "$p/libdir" init -q -b main
mkdir -p "$p/libfile"; printf 'gitdir: ../.git/modules/libfile\n' > "$p/libfile/.git"
for sub in libdir libfile; do
  out=$(vt_in "$p/$sub" status)
  starts "10 $sub (.git ${sub#lib}): status 'vibe-wise: none'" 'vibe-wise: none' "$out"
  vt_in "$p/$sub" off >/dev/null
  if [ -f "$VT" ] && cmp -s "$tmp/t10.orig" "$f"; then ok "10 $sub: off leaves the outer profile unchanged"; else ko "10 $sub: off leaves the outer profile unchanged"; fi
done

echo "== 11. legacy .sensible-vibes (R2)"
p=$(newproj t11a); write_profile "$p/.sensible-vibes/profile.md" 'Learning mode: active' Normal
is_eq "11 .sensible-vibes alone is used" 'vibe-wise: on [normal]' "$(vt_in "$p" status)"
p=$(newproj t11b)
write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' Normal
write_profile "$p/.sensible-vibes/profile.md" 'Learning mode: active' Normal
cp "$p/.sensible-vibes/profile.md" "$tmp/t11.legacy"
vt_in "$p" off >/dev/null
if paused_in "$p/.vibe-wise/profile.md"; then ok "11 both present: off pauses .vibe-wise/profile.md"; else ko "11 both present: off pauses .vibe-wise/profile.md"; fi
if paused_in "$p/.vibe-wise/profile.md" && cmp -s "$tmp/t11.legacy" "$p/.sensible-vibes/profile.md"; then ok "11 both present: legacy profile unchanged"; else ko "11 both present: legacy profile unchanged (and .vibe-wise paused)"; fi

echo "== 12. CRLF profiles (R2)"
p=$(newproj t12); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: paused' Normal; to_crlf "$f"; cp "$f" "$tmp/t12.orig"
is_eq "12 CRLF 'Learning mode: paused' reads as off" 'vibe-wise: off' "$(vt_in "$p" status)"
vt_in "$p" on >/dev/null
starts "12 CRLF after on: status on" 'vibe-wise: on' "$(vt_in "$p" status)"
if active_in "$f" && same_but_mode "$tmp/t12.orig" "$f"; then ok "12 CRLF after on: other lines byte-identical, CR included"; else ko "12 CRLF after on: other lines byte-identical, CR included" "$(od -c "$f" | head -4)"; fi
vt_in "$p" off >/dev/null
is_eq "12 CRLF after off: status off" 'vibe-wise: off' "$(vt_in "$p" status)"
if [ -f "$VT" ] && paused_in "$f" && same_but_mode "$tmp/t12.orig" "$f"; then ok "12 CRLF after off: other lines byte-identical, CR included"; else ko "12 CRLF after off: other lines byte-identical, CR included" "$(od -c "$f" | head -4)"; fi

echo "== 13. .vibe-wise as a symlink (R2)"
p=$(newproj t13); target="$tmp/t13-target"
write_profile "$target/profile.md" 'Learning mode: active' Normal; cp "$target/profile.md" "$tmp/t13.orig"
MSYS=winsymlinks:nativestrict ln -s "$target" "$p/.vibe-wise" 2>/dev/null
if [ -L "$p/.vibe-wise" ]; then
  starts "13 symlinked .vibe-wise: status 'vibe-wise: none'" 'vibe-wise: none' "$(vt_in "$p" status)"
  vt_in "$p" off >/dev/null
  if [ -f "$VT" ] && cmp -s "$tmp/t13.orig" "$target/profile.md"; then ok "13 off leaves the linked profile unchanged"; else ko "13 off leaves the linked profile unchanged"; fi
else
  echo "skip 13 this host cannot make a real symlink"
fi

echo "== 14. a regular file named .vibe-wise ends the lookup (R2)"
p=$(newproj t14a); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' Normal
mkdir -p "$p/sub"; printf 'not notes\n' > "$p/sub/.vibe-wise"
starts "14 root has notes: status on" 'vibe-wise: on' "$(vt_in "$p" status)"
starts "14 file .vibe-wise in subdir hides the root notes: 'vibe-wise: none'" 'vibe-wise: none' "$(vt_in "$p/sub" status)"
p=$(newproj t14b); printf 'not notes\n' > "$p/.vibe-wise"
write_profile "$p/.sensible-vibes/profile.md" 'Learning mode: active' Normal
starts "14 file .vibe-wise beside an active .sensible-vibes: 'vibe-wise: none'" 'vibe-wise: none' "$(vt_in "$p" status)"

echo "== 15. notes directory without a usable profile (R2)"
p=$(newproj t15a); mkdir -p "$p/.vibe-wise"; printf '# Learning Progress\n' > "$p/.vibe-wise/progress.md"
p2=$(newproj t15b); mkdir -p "$p2/.vibe-wise"; printf '  \n\t\n\n' > "$p2/.vibe-wise/profile.md"
for d in "$p" "$p2"; do
  name=${d##*/}; [ "$name" = t15a ] && what="no profile.md" || what="blank profile.md"
  starts "15 $what: status 'vibe-wise: none'" 'vibe-wise: none' "$(vt_in "$d" status)"
  before=$(snap "$d/.vibe-wise"); vt_in "$d" on >/dev/null; vt_in "$d" off >/dev/null
  if [ -f "$VT" ] && [ "$before" = "$(snap "$d/.vibe-wise")" ]; then ok "15 $what: on and off leave the directory byte-identical"; else ko "15 $what: on and off leave the directory byte-identical"; fi
done

echo "== 16. dir argument that does not exist (R2)"
p=$(newproj t16); f="$p/.vibe-wise/profile.md"
write_profile "$f" 'Learning mode: active' Normal; cp "$f" "$tmp/t16.orig"
missing="$tmp/p/t16-missing/sub"
starts "16 missing dir: 'vibe-wise: none' (even from a cwd with notes)" 'vibe-wise: none' "$(vt_in "$p" status "$missing")"
vt_in "$p" on "$missing" >/dev/null; vt_in "$p" off "$missing" >/dev/null
if [ -f "$VT" ] && [ ! -e "$tmp/p/t16-missing" ] && cmp -s "$tmp/t16.orig" "$f"; then ok "16 nothing created, cwd profile untouched"; else ko "16 nothing created, cwd profile untouched"; fi

echo "== 17. frequency outside Light/Normal/Frequent (R2)"
p=$(newproj t17); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' 'Not specified'
is_eq "17 'Not specified': exactly 'vibe-wise: on'" 'vibe-wise: on' "$(vt_in "$p" status)"

# ══ Statusline ════════════════════════════════════════════════════════════════

echo "== 18. statusline, active with frequency (R3)"
p18=$(newproj t18); write_profile "$p18/.vibe-wise/profile.md" 'Learning mode: active' Normal
has_line "18 'VibeWise │ On · Normal'" 'VibeWise │ On · Normal' "$(render "$p18")"

echo "== 19. statusline, active without a usable frequency (R3)"
p=$(newproj t19a); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' ''
has_line "19 no frequency line: exactly 'VibeWise │ On'" 'VibeWise │ On' "$(render "$p")"
p=$(newproj t19b); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' 'Not specified'
has_line "19 'Not specified': exactly 'VibeWise │ On'" 'VibeWise │ On' "$(render "$p")"

echo "== 20. statusline, paused (R3)"
p=$(newproj t20); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: paused' Normal
has_line "20 'VibeWise │ Off'" 'VibeWise │ Off' "$(render "$p")"

echo "== 21. statusline, no notes (R3)"
p=$(newproj t21); out=$(render "$p"); sib=$(render "$p18")
if no_vibe "$out" && printf '%s\n' "$out" | grep -q '^Github' && printf '%s\n' "$sib" | grep -q '^VibeWise'; then
  ok "21 no VibeWise line without notes (sibling with notes has one)"
else ko "21 no VibeWise line without notes (sibling with notes has one)" "no notes:" "$out" "sibling:" "$sib"; fi

echo "== 22. line order with a terse-mode badge (R3)"
stub="$tmp/cfg22/mods/ponytail/hooks/ponytail-statusline.sh"
mkdir -p "$(dirname "$stub")"; printf '#!/usr/bin/env bash\nprintf "[PONYTAIL]"\n' > "$stub"
out=$(render_with "$tmp/cfg22" "$(payload "$p18")")
pn=$(printf '%s\n' "$out" | grep -n '^Ponytail' | head -1 | cut -d: -f1)
vn=$(printf '%s\n' "$out" | grep -n '^VibeWise' | head -1 | cut -d: -f1)
gn=$(printf '%s\n' "$out" | grep -n '^Github' | head -1 | cut -d: -f1)
if [ -n "$pn" ] && [ -n "$vn" ] && [ -n "$gn" ] && [ "$pn" -lt "$vn" ] && [ "$vn" -lt "$gn" ]; then ok "22 order Ponytail, VibeWise, Github"
else ko "22 order Ponytail, VibeWise, Github" "$out"; fi

echo "== 23. command and display agree (R2, R3)"
p=$(newproj t23); write_profile "$p/.vibe-wise/profile.md" 'Learning mode: active' Normal
vt_in "$p" off >/dev/null
has_line "23 after off: 'VibeWise │ Off'" 'VibeWise │ Off' "$(render "$p")"
vt_in "$p" on >/dev/null
out=$(render "$p")
if printf '%s\n' "$out" | grep -qE '^VibeWise │ On( · Normal)?$'; then ok "23 after on: 'VibeWise │ On'"; else ko "23 after on: 'VibeWise │ On'" "$out"; fi

echo "== 24. statusline from a subdirectory (R3)"
mkdir -p "$p18/sub" "$p18/hid"; printf 'not notes\n' > "$p18/hid/.vibe-wise"
has_line "24 current_dir in a subdirectory: same VibeWise line" 'VibeWise │ On · Normal' "$(render "$p18/sub")"
out=$(render "$p18/hid")
if no_vibe "$out" && printf '%s\n' "$(render "$p18")" | grep -q '^VibeWise'; then ok "24 subdirectory with a file .vibe-wise: no VibeWise line (root has one)"
else ko "24 subdirectory with a file .vibe-wise: no VibeWise line (root has one)" "$out"; fi

echo "== 25. native Windows current_dir (R3)"
if command -v cygpath >/dev/null 2>&1; then
  has_line "25 'C:\\…' current_dir: same VibeWise line" 'VibeWise │ On · Normal' "$(render "$(cygpath -w "$p18")")"
else
  echo "skip 25 not on Windows (no cygpath)"
fi

echo "== 26. payload without workspace.current_dir (R3)"
out=$( cd "$p18" && render_with "$tmp/nocfg" '{"model": {"display_name": "Fable 5"}, "context_window": {"context_window_size": 1000000, "used_percentage": 0}}' )
if no_vibe "$out" && printf '%s\n' "$(render "$p18")" | grep -q '^VibeWise'; then ok "26 no current_dir: no VibeWise line from the process cwd (with current_dir: one)"
else ko "26 no current_dir: no VibeWise line from the process cwd (with current_dir: one)" "$out"; fi

# ══ Wiring ════════════════════════════════════════════════════════════════════

echo "== 27. settings.json and the mods marketplace (R1, R2)"
S="$REPO_DIR/settings.json"
is_eq "27 enabledPlugins[vibe-wise@claude-config] is true" true "$(jq -r '.enabledPlugins["vibe-wise@claude-config"]' "$S" | tr -d '\r')"
is_eq "27 no enabledPlugins[vibe-wise@vibe-wise], no extraKnownMarketplaces[vibe-wise]: the upstream copy is gone" "null null"   "$(jq -r '[.enabledPlugins["vibe-wise@vibe-wise"], .extraKnownMarketplaces["vibe-wise"]] | map(tostring) | join(" ")' "$S" | tr -d '\r')"
M="$REPO_DIR/mods/.claude-plugin/marketplace.json"
is_eq "27 marketplace claude-config lists vibe-wise from ./vibe-wise" "claude-config ./vibe-wise"   "$(jq -r '.name + " " + (.plugins[] | select(.name == "vibe-wise") | .source)' "$M" 2>/dev/null | tr -d '\r')"
is_eq "27 mods/vibe-wise holds the plugin's SessionStart hook" true "$([ -f "$REPO_DIR/mods/vibe-wise/hooks/session_start.py" ] && echo true || echo false)"
is_eq "27 permissions.allow holds Bash(bash *vibe-toggle*)" true   "$(jq -r '.permissions.allow | index("Bash(bash *vibe-toggle*)") != null' "$S" | tr -d '\r')"

echo "== 28. install.sh: vibe-wise comes from mods/, not from PINNED_PLUGINS (R1)"
arr=$(awk '/^PINNED_PLUGINS=\(/{f=1} f{print} f&&/^\)/{exit}' "$REPO_DIR/install.sh")
mods=$(sed -n 's/^MODS_PLUGINS=(\(.*\))$/\1/p' "$REPO_DIR/install.sh")
if [ -z "$arr" ]; then ko "28 PINNED_PLUGINS array not found in install.sh"
elif printf '%s
' "$arr" | grep -q 'vibe-wise'; then ko "28 PINNED_PLUGINS no longer names vibe-wise" "$arr"
else ok "28 PINNED_PLUGINS no longer names vibe-wise"; fi
if printf ' %s ' "$mods" | grep -q ' vibe-wise '; then ok "28 MODS_PLUGINS holds vibe-wise (installed as vibe-wise@claude-config)"
else ko "28 MODS_PLUGINS holds vibe-wise (installed as vibe-wise@claude-config)" "MODS_PLUGINS=($mods)"; fi

echo "== 29. commands/vibe-toggle.md (R2)"
C="$REPO_DIR/commands/vibe-toggle.md"
if [ ! -f "$C" ]; then
  ko "29 commands/vibe-toggle.md frontmatter" "commands/vibe-toggle.md does not exist"
  ko "29 commands/vibe-toggle.md body passes \$ARGUMENTS to the script" "commands/vibe-toggle.md does not exist"
else
  fm=$(tr -d '\r' < "$C" | awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f')
  body=$(tr -d '\r' < "$C" | awk 'NR==1 && /^---$/ {f=1; next} f==1 && /^---$/ {f=2; next} f!=1')
  if printf '%s\n' "$fm" | grep -q '^description:' && printf '%s\n' "$fm" | grep -q '^argument-hint:' \
     && printf '%s\n' "$fm" | grep '^allowed-tools:' | grep -qF 'Bash(bash *vibe-toggle*)'; then
    ok "29 frontmatter has description, argument-hint, allowed-tools Bash(bash *vibe-toggle*)"
  else ko "29 frontmatter has description, argument-hint, allowed-tools Bash(bash *vibe-toggle*)" "$fm"; fi
  if printf '%s\n' "$body" | grep -qE '[~]/\.claude/scripts/vibe-toggle\.sh[[:space:]]+"?\$ARGUMENTS'; then
    ok "29 body runs ~/.claude/scripts/vibe-toggle.sh \$ARGUMENTS"
  else ko "29 body runs ~/.claude/scripts/vibe-toggle.sh \$ARGUMENTS" "$body"; fi
fi

echo "== 30. install.sh warns when python3 does not run (R1)"
# Read by the functions eval'd in below, which shellcheck cannot see.
# shellcheck disable=SC2034
{ GREEN=""; YELLOW=""; CYAN=""; RED=""; BOLD=""; DIM=""; RESET=""; VERBOSE=false; OK_ITEMS=(); }
for fn in _step _detail _ok _ok_flush; do   # install.sh's own output helpers
  eval "$(awk -v n="$fn" '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
done
body="$(awk -v n=_warn_vibe_wise_python3 '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
if [ -z "$body" ]; then
  ko "30 python3 failing: one warning line naming vibe-wise and python3" "_warn_vibe_wise_python3 not found in install.sh"
  ko "30 python3 working: no output, return 0" "_warn_vibe_wise_python3 not found in install.sh"
else
  eval "$body"
  for code in 1 0; do
    bin="$tmp/bin$code"; mkdir -p "$bin"
    printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$bin/python3"; chmod +x "$bin/python3"
    out=$( export PATH="$bin:$PATH"; hash -r; _warn_vibe_wise_python3 2>&1 ); rc=$?
    out=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | grep -v '^[[:space:]]*$')
    if [ "$code" = 1 ]; then
      if [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] \
         && printf '%s' "$out" | grep -qi vibe-wise && printf '%s' "$out" | grep -q python3; then
        ok "30 python3 failing: one warning line naming vibe-wise and python3, return 0"
      else ko "30 python3 failing: one warning line naming vibe-wise and python3, return 0" "rc=$rc" "out: $out"; fi
    else
      if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "30 python3 working: no output, return 0"
      else ko "30 python3 working: no output, return 0" "rc=$rc" "out: $out"; fi
    fi
  done
fi

echo
if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all vibe-toggle checks passed"
