#!/usr/bin/env bash
# Auto-sync shared files from upstream — debounced to once per 8h
# Usage: sync-upstream.sh [--force]
# Exit 0: synced, or nothing to do (no upstream remote, debounce). Exit 3: skipped —
# a branch other than the fork's default one checked out, uncommitted changes on a
# synced path, or upstream unreachable — with the reason on stderr, so install.sh
# can warn instead of claiming "synced (no changes)".

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

STAMP="$HOME/.claude/.upstream-sync-stamp"
# The script's own repo, never the caller's cwd: install.sh runs this without
# a cd, so from another checkout with an `upstream` remote it used to rm,
# checkout and commit inside THAT repo.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

[[ -n "$REPO_DIR" ]] && git -C "$REPO_DIR" rev-parse --git-dir &>/dev/null || exit 0
git -C "$REPO_DIR" remote get-url upstream &>/dev/null || exit 0

NOW=$(date +%s)
if [[ "$FORCE" == "false" && -f "$STAMP" ]]; then
  LAST=$(cat "$STAMP")
  (( NOW - LAST < 28800 )) && exit 0
fi

# The sync checks upstream's files out into the checked-out branch and commits
# them there: anywhere but the fork's default branch, that would bury the branch's
# own work under upstream's files. The default branch is what origin/HEAD names
# when the clone recorded it, else main or master: the first version allowed main
# alone and skipped every install of a fork born on master (2026-10-08). Checked
# before the fetch; also what keeps a checkout of the public repo that was handed
# an upstream remote by mistake from overwriting its branches (review of PR #29).
_branch="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)"
_default="$(git -C "$REPO_DIR" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
_default="${_default#origin/}"
if [[ -n "$_default" ]]; then
  # Recorded: that branch alone. One merely named main or master is not it
  # (review of PR #30: the first version took the union).
  [[ "$_branch" == "$_default" ]]; _on_default=$?
  _expected="$_default"
else
  [[ "$_branch" == main || "$_branch" == master ]]; _on_default=$?
  _expected="main or master; origin/HEAD not set: git remote set-head origin -a"
fi
if [[ $_on_default -ne 0 ]]; then
  echo "sync-upstream: on branch '${_branch:-detached HEAD}', not the default branch ($_expected) — sync skipped." >&2
  exit 3
fi
unset _branch _default _on_default _expected

git -C "$REPO_DIR" fetch upstream --quiet 2>/dev/null || {
  echo "sync-upstream: upstream unreachable — sync skipped." >&2
  exit 3
}

# Checkout shared files from upstream (leaves vault/, env.local, .claude/ untouched).
# .gitignore is intentionally NOT synced: a fork's ignore rules are local policy —
# e.g. a fork that versions vault/ must not have `vault/` re-added by upstream
# (that regression is exactly how the multi-machine vault bug was first introduced).
# Each path individually so a missing path doesn't abort the entire checkout.
_UPSTREAM_PATHS=(
  agents/ commands/ scripts/ templates/ defaults/ hooks/ gates/ mods/
  install.sh settings.json CLAUDE.md .gitattributes
  mempalace.yaml env.local.template
)

# Never touch a dirty tree: `checkout upstream/main -- <path>` overwrites edits
# without asking, and the commit below would sweep whatever is already staged.
if ! git -C "$REPO_DIR" diff --cached --quiet || ! git -C "$REPO_DIR" diff --quiet -- "${_UPSTREAM_PATHS[@]}"; then
  echo "sync-upstream: uncommitted changes in $REPO_DIR — commit or stash them, sync skipped." >&2
  exit 3
fi

# Apply upstream deletions first: `checkout upstream/main -- <dir>` only adds or
# overwrites files, it never removes what upstream deleted, so retired files
# (renamed commands, dropped agents) would survive in forks forever. A file the
# fork tracks on a synced path that upstream/main no longer holds goes when
# upstream's history knows the path: upstream had it and dropped or renamed it.
# A path upstream never had is the fork's own and stays. No baseline: the first
# version diffed the last synced commit against upstream/main with
# --diff-filter=D, which misses a rename (git reports R, not D) and anything
# older than a baseline recorded past it. scripts/baseline-ratchet.js, renamed
# to .cjs upstream on 2026-10-05, stayed in the private fork that way (2026-10-09).
# ponytail: a path upstream once had and dropped, re-added by the fork for its
# own use, goes at every sync; keep such a file off the synced paths.
_upstream_tree="$(git -C "$REPO_DIR" -c core.quotePath=false ls-tree -r --name-only upstream/main -- "${_UPSTREAM_PATHS[@]}" 2>/dev/null | LC_ALL=C sort)"
if [[ -n "$_upstream_tree" ]]; then
  while IFS= read -r _f; do
    [[ -n "$_f" ]] || continue
    [[ -n "$(git -C "$REPO_DIR" rev-list -n 1 upstream/main -- "$_f" 2>/dev/null)" ]] || continue
    git -C "$REPO_DIR" rm --quiet -f -- "$_f" 2>/dev/null || true
  done < <(comm -23 <(git -C "$REPO_DIR" -c core.quotePath=false ls-files -- "${_UPSTREAM_PATHS[@]}" | LC_ALL=C sort) <(printf '%s\n' "$_upstream_tree"))
fi
unset _upstream_tree _f

for _p in "${_UPSTREAM_PATHS[@]}"; do
  git -C "$REPO_DIR" checkout upstream/main -- "$_p" 2>/dev/null || true
done
unset _UPSTREAM_PATHS _p

git -C "$REPO_DIR" diff --cached --quiet || \
  git -C "$REPO_DIR" commit -m "chore: sync from upstream" --quiet

mkdir -p "$(dirname "$STAMP")"
echo "$NOW" > "$STAMP"
