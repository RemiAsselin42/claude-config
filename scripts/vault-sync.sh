#!/usr/bin/env bash
# vault-sync.sh — Commit vault/ changes and reconcile with origin safely.
#
# Permanently prevents the multi-machine divergence that used to require manual
# conflict resolution. The previous logic did `git push ... 2>/dev/null || true`
# with NO fetch/rebase first: when the remote was ahead the push failed silently,
# the machine kept committing locally, and the two histories drifted apart until a
# human hit conflicts on `git pull`.
#
# Here we always fetch + merge origin BEFORE pushing. The only files that ever
# conflict are graphify-generated vault artifacts, so on conflict we keep THIS
# machine's freshly generated copy (`-X ours`): conflict markers are never produced
# and the push is retried if another machine pushed in the meantime.
#
# The branch is auto-detected (works on `main`, `master`, or any current branch),
# overridable via VAULT_SYNC_BRANCH. Safe to call from the Stop hook
# (session-stop.sh) and from install.sh. No-ops cleanly when vault/ is gitignored
# (e.g. the public template) — nothing to commit, nothing to push.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
BRANCH="${VAULT_SYNC_BRANCH:-$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || echo master)}"

git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 1. Commit local vault and graph changes (if any). graphify-out/ is versioned
# in forks (gitignored in the public template — porcelain is then empty and the
# path is skipped), and without committing it every graph rebuild leaves a
# permanent dirty diff behind install.sh / session-stop.sh.
paths=()
for p in vault graphify-out; do
  git -C "$REPO_DIR" status --porcelain "$p/" 2>/dev/null | grep -q . && paths+=("$p/")
done
if [[ ${#paths[@]} -gt 0 ]]; then
  git -C "$REPO_DIR" add "${paths[@]}"
  git -C "$REPO_DIR" commit -q -m "graphify: sync vault + graph — $(date +%Y-%m-%d)" || true
fi

# 2. No remote → local commit is all we can do.
git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1 || exit 0

# 3. Reconcile with origin and push, retrying if another machine raced us.
attempt=0
while [[ $attempt -lt 5 ]]; do
  attempt=$((attempt + 1))

  git -C "$REPO_DIR" fetch -q origin "$BRANCH" 2>/dev/null || exit 0

  local_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)"
  remote_head="$(git -C "$REPO_DIR" rev-parse FETCH_HEAD 2>/dev/null)"
  [[ "$local_head" == "$remote_head" ]] && exit 0   # already in sync

  # Merge remote; this machine's freshly generated vault wins on the
  # (only-ever-generated) conflicts, so no markers are ever written.
  if ! git -C "$REPO_DIR" merge -q -X ours --no-edit FETCH_HEAD 2>/dev/null; then
    git -C "$REPO_DIR" merge --abort 2>/dev/null || true
    echo "vault-sync: merge with origin/$BRANCH failed — commit left unpushed (resolve manually)." >&2
    exit 1
  fi

  git -C "$REPO_DIR" push -q origin "$BRANCH" 2>/dev/null && exit 0
  # push rejected (remote advanced) → loop: fetch + merge + retry
done

echo "vault-sync: could not push after $((attempt)) attempts (remote kept moving)." >&2
exit 1
