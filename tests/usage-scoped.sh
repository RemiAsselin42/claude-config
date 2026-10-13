#!/usr/bin/env bash
# Self-check for the wiring of the usage-scoped mod (mods/usage-scoped): its
# entry in the mods marketplace, MODS_PLUGINS in install.sh, the enabled id in
# settings.json, and the mod's own manifest and hooks modules. The mod itself is
# checked by `claude plugin test mods/usage-scoped`, the Usage segment it feeds
# by tests/statusline.sh.
#
#   bash tests/usage-scoped.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
MOD="$REPO_DIR/mods/usage-scoped"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

fails=0
ok() { echo "ok   $1"; }
ko() {  # ko <description> [detail lines...]
  echo "FAIL $1"; shift
  local l; for l in "$@"; do printf '%s\n' "$l" | sed 's/^/     /'; done
  fails=$((fails + 1))
}
is_eq() {   # is_eq <description> <expected> <got>
  if [ "$3" = "$2" ]; then ok "$1"; else ko "$1" "expected: $2" "got:      $3"; fi
}

echo "== 17. the mods marketplace lists usage-scoped"
M="$REPO_DIR/mods/.claude-plugin/marketplace.json"
is_eq "17 marketplace claude-config lists usage-scoped from ./usage-scoped" "claude-config ./usage-scoped" \
  "$(jq -r '.name + " " + (.plugins[] | select(.name == "usage-scoped") | .source)' "$M" 2>/dev/null | tr -d '\r')"

echo "== 18. install.sh installs it from mods/"
mods=$(tr -d '\r' < "$REPO_DIR/install.sh" | sed -n 's/^MODS_PLUGINS=(\(.*\))$/\1/p')
for p in usage-scoped ponytail vibe-wise; do
  if printf ' %s ' "$mods" | grep -q " $p "; then ok "18 MODS_PLUGINS holds $p"
  else ko "18 MODS_PLUGINS holds $p" "MODS_PLUGINS=($mods)"; fi
done

echo "== 19. settings.json enables it"
is_eq "19 enabledPlugins[usage-scoped@claude-config] is true" true \
  "$(jq -r '.enabledPlugins["usage-scoped@claude-config"]' "$REPO_DIR/settings.json" | tr -d '\r')"

echo "== 20. the mod's manifest and hooks modules"
is_eq "20 .claude-plugin/plugin.json names usage-scoped" usage-scoped \
  "$(jq -r '.name' "$MOD/.claude-plugin/plugin.json" 2>/dev/null | tr -d '\r')"
H="$MOD/hooks/hooks.json"
modules=$(jq -r '.modules[]' "$H" 2>/dev/null | tr -d '\r')
if [ -z "$modules" ]; then ko "20 hooks/hooks.json names at least one module" "no module read from $H"
else
  ok "20 hooks/hooks.json names at least one module"
  while IFS= read -r m; do
    if [ -f "$MOD/hooks/$m" ]; then ok "20 module $m exists"
    else ko "20 module $m exists" "missing: $MOD/hooks/$m"; fi
  done <<< "$modules"
fi

echo
if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all usage-scoped checks passed"
