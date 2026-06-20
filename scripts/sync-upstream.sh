#!/usr/bin/env bash
# Auto-sync shared files from upstream — debounced to once per 8h
# Usage: sync-upstream.sh [--force]

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

STAMP="$HOME/.claude/.upstream-sync-stamp"
REPO_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"

[[ -z "$REPO_DIR" ]] && exit 0
git -C "$REPO_DIR" remote get-url upstream &>/dev/null || exit 0

NOW=$(date +%s)
if [[ "$FORCE" == "false" && -f "$STAMP" ]]; then
  LAST=$(cat "$STAMP")
  (( NOW - LAST < 28800 )) && exit 0
fi

git -C "$REPO_DIR" fetch upstream --quiet 2>/dev/null || exit 0

# Checkout shared files from upstream (leaves vault/, env.local, .claude/ untouched).
# .gitignore is intentionally NOT synced: a fork's ignore rules are local policy —
# e.g. a fork that versions vault/ must not have `vault/` re-added by upstream
# (that regression is exactly how the multi-machine vault bug was first introduced).
# Each path individually so a missing path doesn't abort the entire checkout.
_UPSTREAM_PATHS=(
  agents/ commands/ scripts/ templates/ defaults/ hooks/
  install.sh settings.json CLAUDE.md .gitattributes
  mempalace.yaml claude.json.template env.local.template
)
for _p in "${_UPSTREAM_PATHS[@]}"; do
  git -C "$REPO_DIR" checkout upstream/main -- "$_p" 2>/dev/null || true
done
unset _UPSTREAM_PATHS _p

git -C "$REPO_DIR" diff --cached --quiet || \
  git -C "$REPO_DIR" commit -m "chore: sync from upstream" --quiet

echo "$NOW" > "$STAMP"
