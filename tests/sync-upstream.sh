#!/usr/bin/env bash
# Self-check for scripts/sync-upstream.sh on two throwaway repos (an upstream and a
# fork that pulls from it): a dirty synced path or an unreachable upstream makes the
# script skip with exit 3, so install.sh can say so instead of "synced (no changes)";
# a clean fork pulls and commits upstream's change; nothing new is a quiet exit 0.
# Run after touching the script or install.sh's sync block:
#
#   bash tests/sync-upstream.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/sync-upstream.sh"

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"   # the stamp file lands here, never in the real ~/.claude
mkdir -p "$HOME"
# ~/.gitconfig is out of reach with that HOME: the commits below and the one the
# script makes in the fork need an identity from the environment
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_NOSYSTEM=1   # Git for Windows' system autocrlf=true only adds CRLF warnings here
UP="$T/upstream"
FORK="$T/fork"

# upstream: the script under test (tracked, so the fork has it too) and one synced file
git init -q -b main "$UP"
mkdir -p "$UP/scripts"
cp "$SCRIPT" "$UP/scripts/sync-upstream.sh"
echo "v1" > "$UP/CLAUDE.md"
git -C "$UP" add -A && git -C "$UP" commit -q -m "v1"
git clone -q "$UP" "$FORK" && git -C "$FORK" remote rename origin upstream

sync() { bash "$FORK/scripts/sync-upstream.sh" --force 2>"$T/err"; }

# 1. a dirty synced path: skipped, exit 3, the reason on stderr
echo "local edit" >> "$FORK/CLAUDE.md"
sync; rc=$?
if [[ $rc -eq 3 && "$(cat "$T/err")" == *"sync skipped"* ]]; then
  ok "dirty synced path: exit 3 with the reason on stderr"
else
  ko "dirty synced path: exit $rc, stderr: $(cat "$T/err")"
fi
git -C "$FORK" checkout -q -- CLAUDE.md

# 2. upstream moved, fork clean: pulled and committed
echo "v2" > "$UP/CLAUDE.md" && git -C "$UP" commit -q -am "v2"
before="$(git -C "$FORK" rev-parse HEAD)"
sync; rc=$?
if [[ $rc -eq 0 && "$(git -C "$FORK" rev-parse HEAD)" != "$before" && "$(cat "$FORK/CLAUDE.md")" == "v2" ]]; then
  ok "upstream change: pulled and committed, exit 0"
else
  ko "upstream change: exit $rc, CLAUDE.md=$(cat "$FORK/CLAUDE.md"), stderr: $(cat "$T/err")"
fi

# 3. nothing new: exit 0, HEAD untouched
before="$(git -C "$FORK" rev-parse HEAD)"
sync; rc=$?
if [[ $rc -eq 0 && "$(git -C "$FORK" rev-parse HEAD)" == "$before" ]]; then
  ok "nothing new: exit 0, no commit"
else
  ko "nothing new: exit $rc, HEAD moved=$([[ "$(git -C "$FORK" rev-parse HEAD)" != "$before" ]] && echo yes || echo no)"
fi

# 4. upstream unreachable: skipped, exit 3, said on stderr
git -C "$FORK" remote set-url upstream "$T/no-such-repo"
sync; rc=$?
if [[ $rc -eq 3 && "$(cat "$T/err")" == *"sync skipped"* ]]; then
  ok "unreachable upstream: exit 3 with the reason on stderr"
else
  ko "unreachable upstream: exit $rc, stderr: $(cat "$T/err")"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
