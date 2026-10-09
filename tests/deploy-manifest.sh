#!/usr/bin/env bash
# Self-check for install.sh's deploy manifest: ~/.claude/.deployed-files lists
# every file install.sh copied; the next install removes what the previous
# manifest listed and the new one does not — install.sh's own leftovers only,
# never the owner's files, never a path outside the deployed directories. The
# two functions are taken out of install.sh by name and run against a scratch
# REPO_DIR and CLAUDE_DIR.
#
#   bash tests/deploy-manifest.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }
# shellcheck disable=SC2034  # read by the functions eval'd in below
export GREEN='' YELLOW='' CYAN='' DIM='' BOLD='' RESET='' VERBOSE=true OK_ITEMS=()
for fn in _detail _deployed_manifest _prune_stale_deployed; do
  body="$(awk -v n="$fn" '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$SRC/install.sh")"
  if [[ -z "$body" ]]; then echo "  FAIL  $fn not found in install.sh"; fail=$((fail + 1)); continue; fi
  eval "$body"
done

REPO_DIR="$T/repo"; CLAUDE_DIR="$T/claude"
mkdir -p "$REPO_DIR/scripts" "$REPO_DIR/templates" "$REPO_DIR/mods/m" "$REPO_DIR/agents" \
         "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/templates" "$CLAUDE_DIR/mods/m" "$CLAUDE_DIR/agents"
printf 'a\n' > "$REPO_DIR/scripts/a.sh"; printf 'b\n' > "$REPO_DIR/scripts/b.sh"
printf 't\n' > "$REPO_DIR/templates/t.md"; printf 'm\n' > "$REPO_DIR/mods/m/x.json"
printf 'c\n' > "$REPO_DIR/CLAUDE.md"; printf '{}\n' > "$REPO_DIR/settings.json"
M="$CLAUDE_DIR/.deployed-files"

deploy() {  # the copy install.sh does, then its manifest step
  cp -r "$REPO_DIR/scripts/." "$CLAUDE_DIR/scripts/"; cp -r "$REPO_DIR/templates/." "$CLAUDE_DIR/templates/"
  cp -r "$REPO_DIR/mods/." "$CLAUDE_DIR/mods/"
  cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"; cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  new="$T/new"; _deployed_manifest > "$new"
  _prune_stale_deployed "$M" "$new" >/dev/null
  mv -f "$new" "$M"
}
listed() { grep -qxF -- "$1" "$M"; }

echo "== 1. first install: the manifest is written, nothing is removed"
printf 'mine\n' > "$CLAUDE_DIR/scripts/mine.sh"   # the owner's own script, never deployed by install.sh
deploy
[[ -f "$M" ]] && ok "manifest written" || ko "manifest written"
listed scripts/b.sh && ok "manifest lists scripts/b.sh" || ko "manifest lists scripts/b.sh"
listed mods/m/x.json && ok "manifest lists mods/m/x.json (directories are walked)" || ko "manifest lists mods/m/x.json"
listed CLAUDE.md && listed settings.json && ok "manifest lists CLAUDE.md and settings.json" || ko "manifest lists CLAUDE.md and settings.json"
[[ -f "$CLAUDE_DIR/scripts/mine.sh" ]] && ok "the owner's own file stays" || ko "the owner's own file stays"

echo "== 2. next install, scripts/b.sh and mods/m/x.json gone from the repo, scripts/c.sh added: the two are pruned, nothing else"
rm "$REPO_DIR/scripts/b.sh" "$REPO_DIR/mods/m/x.json"; printf 'c\n' > "$REPO_DIR/scripts/c.sh"
deploy
[[ ! -e "$CLAUDE_DIR/scripts/b.sh" ]] && ok "scripts/b.sh removed" || ko "scripts/b.sh removed"
[[ ! -e "$CLAUDE_DIR/mods/m/x.json" ]] && ok "mods/m/x.json removed" || ko "mods/m/x.json removed"
[[ -f "$CLAUDE_DIR/scripts/a.sh" && -f "$CLAUDE_DIR/scripts/c.sh" && -f "$CLAUDE_DIR/scripts/mine.sh" && -f "$CLAUDE_DIR/templates/t.md" ]] \
  && ok "a.sh, c.sh, mine.sh and t.md stay" || ko "a.sh, c.sh, mine.sh and t.md stay"
listed scripts/b.sh && ko "manifest no longer lists scripts/b.sh" || ok "manifest no longer lists scripts/b.sh"
listed scripts/c.sh && ok "manifest lists scripts/c.sh" || ko "manifest lists scripts/c.sh"

echo "== 3. the baseline-ratchet case: a deployed leftover an older manifest listed goes away at the next install"
printf 'old\n' > "$CLAUDE_DIR/scripts/baseline-ratchet.js"; printf 'scripts/baseline-ratchet.js\n' >> "$M"
deploy
[[ ! -e "$CLAUDE_DIR/scripts/baseline-ratchet.js" ]] && ok "scripts/baseline-ratchet.js removed" || ko "scripts/baseline-ratchet.js removed"

echo "== 4. install.sh's own paths only: an escaping or foreign manifest line is ignored, a listed file still deployed is kept"
printf '%s\n' '../outside' '/etc/passwd' 'scripts/../../x' 'other/file' 'settings.json' > "$M"
printf 'o\n' > "$T/outside"; mkdir -p "$CLAUDE_DIR/other"; printf 'f\n' > "$CLAUDE_DIR/other/file"
deploy
[[ -f "$T/outside" ]] && ok "../outside untouched" || ko "../outside untouched"
[[ -f "$CLAUDE_DIR/other/file" ]] && ok "other/file untouched (not a deployed directory)" || ko "other/file untouched"
[[ -f "$CLAUDE_DIR/settings.json" ]] && ok "settings.json kept (in the new manifest)" || ko "settings.json kept"

echo "== 5. a CRLF manifest line, and a last line without a newline, are read as paths"
printf 'scripts/crlf.sh\r\nscripts/nonl.sh' >> "$M"; printf 'x\n' > "$CLAUDE_DIR/scripts/crlf.sh"; printf 'y\n' > "$CLAUDE_DIR/scripts/nonl.sh"
deploy
[[ ! -e "$CLAUDE_DIR/scripts/crlf.sh" && ! -e "$CLAUDE_DIR/scripts/nonl.sh" ]] && ok "both removed" || ko "both removed"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
