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

# Checkout shared files from upstream (leaves vault/, env.local, .claude/ untouched)
git -C "$REPO_DIR" checkout upstream/main -- \
  agents/ commands/ scripts/ templates/ defaults/ hooks/ \
  install.sh settings.json CLAUDE.md .gitignore .gitattributes \
  mempalace.yaml claude.json.template env.local.template 2>/dev/null

git -C "$REPO_DIR" diff --cached --quiet || \
  git -C "$REPO_DIR" commit -m "chore: sync from upstream" --quiet

echo "$NOW" > "$STAMP"
