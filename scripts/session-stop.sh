#!/usr/bin/env bash
# Claude Code Stop hook: updates graphify and syncs the vault if in a graphified repo.
#
# settings.json detaches this script (`nohup ... &`): nothing it prints is read
# back by Claude Code, and its slowest step is a network git fetch/merge/push,
# which used to be paid in full at the end of every single response (~6 s median,
# 40 s worst case of felt latency). Detached, it costs nothing visible.
#
# Detaching means two sessions can now overlap here, and vault-sync.sh commits
# and pushes the SAME repo whatever the cwd — so runs are serialized on a global
# lock. Waiting is free now that no one is watching, so a queued run waits its
# turn instead of skipping (skipping would silently drop that repo's graph sync).
[[ -d "graphify-out" ]] || exit 0

lock="$HOME/.claude/.session-stop.lock"
acquired=""
for ((i = 0; i < 120; i++)); do
  if mkdir "$lock" 2>/dev/null; then acquired=1; break; fi
  # A run killed mid-flight (machine off, session force-quit) would otherwise
  # leave the lock behind and disable the hook forever.
  (( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0) > 600 )) && rmdir "$lock" 2>/dev/null
  sleep 1
done
[[ -n "$acquired" ]] || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

graphify update . 2>/dev/null || true
# Refresh this repo's MemPalace wing so the other machines' sessions see today's
# work. The wing is read from the repo's own mempalace.yaml — this script is
# standalone and cannot source repo-identity.sh.
if command -v mempalace >/dev/null 2>&1 && [ -f mempalace.yaml ]; then
  wing="$(sed -n 's/^wing:[[:space:]]*//p' mempalace.yaml | head -1)"
  # --background is rejected without --daemon (`--background requires --daemon`,
  # exit 2): this call used to fail on every single response with its stderr
  # silenced, which is why no repo wing was ever created. The daemon queue is
  # also what keeps the mine off the lock below — an inline mine of a large repo
  # runs for minutes and would make the next Stop wait for it.
  [ -n "$wing" ] && mempalace mine . --wing "$wing" --daemon --background >/dev/null 2>&1 || true
fi
CLAUDE_CONFIG_DIR="$(cat "$HOME/.claude/claude-config.path" 2>/dev/null)"
[[ -d "$CLAUDE_CONFIG_DIR" ]] || exit 0
bash "$CLAUDE_CONFIG_DIR/scripts/sync-graph-to-vault.sh"
# Commit + reconcile + push via the shared, divergence-safe helper (fetch→merge→push).
bash "$CLAUDE_CONFIG_DIR/scripts/vault-sync.sh"
