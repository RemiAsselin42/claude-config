#!/usr/bin/env bash
# Integrity of the deployed harness, two drifts named apart:
#   deployed ≠ clone   ~/.claude/{settings.json,CLAUDE.md,hooks,agents,commands,scripts,mods}
#                      against the clone install.sh deployed from (~/.claude/claude-config.path):
#                      CLAUDE.md after install.sh's ${VAULT_DIR} substitution, settings.json as
#                      normalized JSON without the three keys a machine sets itself (TOLERATED,
#                      the only exceptions), every other file byte for byte. A deployed hook,
#                      agent or command with no source in the clone counts (hooks run, agents/
#                      and commands/ are mirrored); a leftover in scripts/ or a file Claude Code
#                      lays into mods/ does not (both additive).
#   clone ≠ remote     the same paths in the clone's working tree against the last fetched
#                      default branch of `upstream` (the public repo a fork syncs from) when
#                      that remote exists, else of `origin`. No network, the ref as it is. With
#                      an upstream, the distance to origin (the fork's own remote) is printed
#                      as an "info:" line: not an alert, never in the statusline.
# Prints one full line per drift (session-start.sh puts them in the session and, the alerts,
# in front of the human), writes the alerts' short form to $CLAUDE_DIR/.harness-drift for the
# statusline (removed when there is none), always exits 0.
#   bash tests/harness-drift.sh
set -uo pipefail

D="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MARK="$D/.harness-drift"
# model and effortLevel: /model and /effort are per machine. The claude-config marketplace:
# the CLI writes its absolute, machine-specific path there when install.sh registers ~/.claude/mods.
TOLERATED='del(.extraKnownMarketplaces["claude-config"], .model, .effortLevel)'
FILES=(settings.json CLAUDE.md)
DIRS=(hooks agents commands scripts mods)
MIRRORED=(hooks agents commands)

join() { local out="" x; for x in "$@"; do out+="${out:+, }$x"; done; printf '%s' "$out"; }
brief() {  # brief <n> <items…>: the first n, then "+k more"
  local n=$1; shift
  if (( $# > n )); then printf '%s +%d more' "$(join "${@:1:n}")" $(( $# - n )); else join "$@"; fi
}

clone=$(tr -d '\r\n' < "$D/claude-config.path" 2>/dev/null || true)
if [ -z "$clone" ] || [ ! -d "$clone" ]; then
  printf '%s\n' "harness clone unknown — run install.sh" > "$MARK"
  printf '%s\n' "harness clone unknown: $D/claude-config.path → ${clone:-missing} — run install.sh"
  exit 0
fi

tmp=$(mktemp -d) || exit 0
trap 'rm -rf "$tmp"' EXIT
l1=(); l2=(); info=()

# ── deployed ≠ clone ─────────────────────────────────────────────────────────
if [ -f "$clone/settings.json" ]; then
  if [ ! -f "$D/settings.json" ]; then l1+=("settings.json (not deployed)")
  elif ! command -v jq >/dev/null 2>&1; then l1+=("settings.json (not checked: jq missing)")
  elif ! jq -S "$TOLERATED" "$clone/settings.json" > "$tmp/a" 2>/dev/null \
    || ! jq -S "$TOLERATED" "$D/settings.json" > "$tmp/b" 2>/dev/null; then
    l1+=("settings.json (not checked: jq failed)")
  elif ! cmp -s "$tmp/a" "$tmp/b"; then
    # the keys that differ, two levels deep (permissions.allow, hooks.PreToolUse…)
    keys=$(jq -rn --slurpfile a "$tmp/a" --slurpfile b "$tmp/b" '
      def tops: [paths(scalars)] | map(.[0:2] | map(tostring) | join("."));
      def at($p): getpath($p | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      ((($a[0] | tops) + ($b[0] | tops)) | unique) as $ps
      | [ $ps[] | . as $p | select(($a[0] | at($p)) != ($b[0] | at($p))) ] | join(", ")' 2>/dev/null)
    l1+=("settings.json (${keys:-content})")
  fi
fi
if [ -f "$clone/CLAUDE.md" ]; then
  if [ ! -f "$D/CLAUDE.md" ]; then l1+=("CLAUDE.md (not deployed)")
  elif ! sed "s|\${VAULT_DIR}|$clone/vault|g" "$clone/CLAUDE.md" | cmp -s - "$D/CLAUDE.md"; then l1+=("CLAUDE.md")
  fi
fi
for d in "${DIRS[@]}"; do
  [ -d "$clone/$d" ] || continue
  while IFS= read -r -d '' f; do
    rel=${f#"$clone/"}
    if [ ! -f "$D/$rel" ]; then l1+=("$rel (not deployed)")
    elif ! cmp -s "$f" "$D/$rel"; then l1+=("$rel")
    fi
  done < <(find "$clone/$d" -type f -print0 | sort -z)
done
for d in "${MIRRORED[@]}"; do
  for f in "$D/$d"/*; do
    [ -f "$f" ] || continue
    [ -e "$clone/$d/${f##*/}" ] || l1+=("$d/${f##*/} (no source in the clone)")
  done
done

# ── clone ≠ upstream/<default>, else origin/<default> ───────────────────────
default_of() {  # default_of <remote>: what <remote>/HEAD names, else main, else master — as sync-upstream.sh resolves it
  local b
  git -C "$clone" symbolic-ref -q --short "refs/remotes/$1/HEAD" 2>/dev/null && return 0
  for b in main master; do
    git -C "$clone" rev-parse -q --verify "$1/$b" >/dev/null 2>&1 && { printf '%s\n' "$1/$b"; return 0; }
  done
  return 1
}
against() {  # against <ref>: the scoped files whose working-tree state differs from <ref>, untracked ones included
  git -C "$clone" diff --name-only "$1" -- "${FILES[@]}" "${DIRS[@]}" 2>/dev/null
  git -C "$clone" ls-files --others --exclude-standard -- "${DIRS[@]}" 2>/dev/null
}
lbl="clone"; infoline=""
if ! git -C "$clone" rev-parse --git-dir >/dev/null 2>&1; then
  l2=("the clone is not a git repository")
elif git -C "$clone" remote get-url upstream >/dev/null 2>&1; then
  if def=$(default_of upstream); then
    lbl="clone ≠ $def"
    while IFS= read -r f; do [ -n "$f" ] && l2+=("$f"); done < <(against "$def")
  else
    l2=("no upstream/main or upstream/master fetched")
  fi
  if odef=$(default_of origin); then
    while IFS= read -r f; do [ -n "$f" ] && info+=("$f"); done < <(against "$odef")
    (( ${#info[@]} )) && infoline="info: clone ≠ $odef: $(join "${info[@]}")"
  fi
elif def=$(default_of origin); then
  lbl="clone ≠ $def"
  while IFS= read -r f; do [ -n "$f" ] && l2+=("$f"); done < <(against "$def")
else
  l2=("no origin/main or origin/master fetched")
fi

lines=(); short=()
if (( ${#l1[@]} )); then lines+=("deployed ≠ clone: $(join "${l1[@]}")"); short+=("deployed ≠ clone: $(brief 3 "${l1[@]}")"); fi
if (( ${#l2[@]} )); then lines+=("$lbl: $(join "${l2[@]}")"); short+=("$lbl: $(brief 3 "${l2[@]}")"); fi
if (( ${#short[@]} )); then printf '%s\n' "${short[@]}" > "$MARK"; else rm -f "$MARK"; fi
[ -n "$infoline" ] && lines+=("$infoline")
(( ${#lines[@]} )) && printf '%s\n' "${lines[@]}"
exit 0
