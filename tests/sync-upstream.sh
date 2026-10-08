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

# 5. install.sh's status -> message mapping, taken straight out of install.sh by name
# (the same way tests/install-scope.sh takes _in_scope): a regression that mapped
# exit 3 back to the green line would leave the four cases above green.
body="$(awk '$0 == "_report_upstream_sync() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
if [[ -z "$body" ]]; then
  ko "_report_upstream_sync not found in install.sh"
else
  # shellcheck disable=SC2034  # the colour variables the eval'd function expands
  GREEN="" YELLOW="" RESET=""
  eval "$body"
  for spec in "0:✓ upstream synced" "3:⚠ upstream sync skipped" "7:⚠ upstream sync failed (exit 7)"; do
    rc="${spec%%:*}"
    want="${spec#*:}"
    line="$(_report_upstream_sync "$rc")"
    if [[ "$line" == *"$want"* ]]; then
      ok "install.sh maps exit $rc to '$want'"
    else
      ko "install.sh maps exit $rc to: $line"
    fi
  done
fi

# 6. upstream adds a path to the list and the path itself in one change. The fork's
# first pass runs the script it had before, whose list does not name that path: the
# new script arrives, the path does not. install.sh, restarted by that pass, has to
# make a second one. mods/ arrived this way (2026-10): the fork got the settings.json
# naming ~/.claude/mods/paste-view and not the folder. _sync_pass_due is taken out of
# install.sh by name and run against the fork.
git -C "$FORK" remote set-url upstream "$UP"
mkdir -p "$UP/newdir" && echo "new" > "$UP/newdir/file"
sed -i.bak 's|^_UPSTREAM_PATHS=(|_UPSTREAM_PATHS=( newdir/|' "$UP/scripts/sync-upstream.sh" && rm -f "$UP/scripts/sync-upstream.sh.bak"
git -C "$UP" add -A && git -C "$UP" commit -q -m "newdir, and its place in the list"
body="$(awk '$0 == "_sync_pass_due() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
if [[ -z "$body" ]]; then
  ko "_sync_pass_due not found in install.sh"
else
  eval "$body"
  real_repo="$REPO_DIR"
  REPO_DIR="$FORK"   # the function reads the repo install.sh runs in

  unset CLAUDE_CONFIG_SYNCED
  if _sync_pass_due; then ok "first run: a pass is due"; else ko "first run: no pass due"; fi
  sync
  if [[ ! -e "$FORK/newdir/file" ]] && grep -q 'newdir/' "$FORK/scripts/sync-upstream.sh"; then
    ok "first pass: the new script arrives, the path it adds does not"
  else
    ko "first pass: newdir/file present=$([[ -e "$FORK/newdir/file" ]] && echo yes || echo no), stderr: $(cat "$T/err")"
  fi

  export CLAUDE_CONFIG_SYNCED=1   # what the first pass leaves for the restarted install.sh
  if _sync_pass_due; then sync; fi
  if [[ "$(cat "$FORK/newdir/file" 2>/dev/null)" == "new" ]]; then
    ok "restarted after a pass that changed the sync script: a second pass brings the new path"
  else
    ko "restarted after a pass that changed the sync script: newdir/file still missing"
  fi

  export CLAUDE_CONFIG_SYNCED=2
  if _sync_pass_due; then ko "two passes made: a third is due"; else ok "two passes made: no third"; fi

  # a pass that changed anything but the sync script calls for no second one
  echo "v3" > "$UP/CLAUDE.md" && git -C "$UP" commit -q -am "v3"
  unset CLAUDE_CONFIG_SYNCED
  sync
  export CLAUDE_CONFIG_SYNCED=1
  if [[ "$(cat "$FORK/CLAUDE.md")" == "v3" ]] && ! _sync_pass_due; then
    ok "restarted after a pass that left the sync script alone: no second pass"
  else
    ko "restarted after a pass that left the sync script alone: CLAUDE.md=$(cat "$FORK/CLAUDE.md"), second pass due"
  fi
  unset CLAUDE_CONFIG_SYNCED
  REPO_DIR="$real_repo"
fi

# 7. install.sh adds the upstream remote to any fork that lacks it, pointing at the
# public repo, and never to a checkout of the public repo itself: syncing a repo
# from itself would check main's files out over whatever branch is checked out.
# Until 2026-10-08 only a fork whose origin was named claude-config-private got the
# remote; any other fork was never synced and nothing said so. The two functions
# and the URL are taken out of install.sh by name. Code review of PR #29: the
# function answers whether an upstream remote exists afterwards, an origin over ssh
# gets its upstream over ssh too, and a refused `remote add` is said, not swallowed.
body="$(awk '$0 == "_ensure_upstream_remote() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
slug="$(awk '$0 == "_repo_slug() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
url="$(sed -n 's/^CLAUDE_CONFIG_UPSTREAM_URL="\(.*\)"$/\1/p' "$REPO_DIR/install.sh" | tr -d '\r')"
if [[ -z "$body" || -z "$slug" || -z "$url" ]]; then
  ko "_ensure_upstream_remote, _repo_slug or CLAUDE_CONFIG_UPSTREAM_URL not found in install.sh"
else
  eval "$slug"; eval "$body"
  export CLAUDE_CONFIG_UPSTREAM_URL="$url"   # read by the eval'd function
  # shellcheck disable=SC2034  # the colour variables the eval'd function expands
  GREEN="" YELLOW="" RESET=""
  real_repo="$REPO_DIR"
  public="$(_repo_slug "$url")"                 # owner/repo of the public repo, lowercased
  ssh_url="git@github.com:${url#*github.com/}"   # the public repo over ssh
  remote_case() {  # remote_case <name> <origin url> <expected upstream url, or absent>
    local r="$T/remote-$1" got rc
    git init -q -b main "$r" && git -C "$r" remote add origin "$2" || { ko "$1: the throwaway repo could not be made"; return; }
    REPO_DIR="$r"; _ensure_upstream_remote >/dev/null; rc=$?
    got="$(git -C "$r" remote get-url upstream 2>/dev/null || echo absent)"
    if [[ "$got" == "$3" && ( ( "$3" != absent && $rc -eq 0 ) || ( "$3" == absent && $rc -ne 0 ) ) ]]; then
      ok "origin $2: upstream=$got, returns $rc"
    else
      ko "origin $2: expected upstream=$3, got $got, returned $rc"
    fi
  }
  remote_case other   "https://github.com/someone/my-claude-config.git"      "$url"
  remote_case private "https://github.com/someone/claude-config-private.git" "$url"
  remote_case local   "$UP"                                                  "$url"
  remote_case sshfork "git@github.com:someone/claude-config-private.git"     "$ssh_url"
  remote_case self    "$url"                                                 absent
  remote_case nogit   "${url%.git}"                                          absent
  remote_case ssh     "$ssh_url"                                             absent
  remote_case port    "ssh://git@ssh.github.com:443/$public.git"             absent
  remote_case upper   "https://github.com/${public^^}.GIT"                   absent
  r="$T/remote-kept"; git init -q -b main "$r"
  git -C "$r" remote add origin "https://github.com/someone/x.git"
  git -C "$r" remote add upstream "https://example.invalid/custom.git"
  REPO_DIR="$r"; _ensure_upstream_remote >/dev/null; rc=$?
  if [[ $rc -eq 0 && "$(git -C "$r" remote get-url upstream)" == "https://example.invalid/custom.git" ]]; then
    ok "an upstream remote already set is left alone, returns 0"
  else
    ko "an upstream remote already set: rc=$rc, upstream=$(git -C "$r" remote get-url upstream)"
  fi
  # git refuses the remote add (a stub in front of the real git): said, answered with 1
  r="$T/remote-refused"; git init -q -b main "$r"; git -C "$r" remote add origin "https://github.com/someone/y.git"
  real_git="$(command -v git)"; mkdir -p "$T/stubbin"
  printf '#!/usr/bin/env bash\ncase " $* " in *" remote add "*) echo "stub: refused" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$real_git" > "$T/stubbin/git"
  chmod +x "$T/stubbin/git"
  REPO_DIR="$r"; out="$(PATH="$T/stubbin:$PATH" _ensure_upstream_remote 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"⚠"* && "$out" == *upstream* ]] && ! git -C "$r" remote get-url upstream &>/dev/null; then
    ok "a refused remote add is said and answered with 1"
  else
    ko "a refused remote add: rc=$rc, out: $out"
  fi
  REPO_DIR="$real_repo"
fi

# 8. the fork on a branch other than main: skipped, exit 3, nothing committed. The
# sync checks upstream's files out into the current branch and commits them there,
# which would bury a branch's own work under main's (code review of PR #29, 2026-10-08).
git -C "$FORK" switch -q -c topic
echo "v4" > "$UP/CLAUDE.md" && git -C "$UP" commit -q -am "v4"
before="$(git -C "$FORK" rev-parse HEAD)"
sync; rc=$?
if [[ $rc -eq 3 && "$(cat "$T/err")" == *"not main"* && "$(git -C "$FORK" rev-parse HEAD)" == "$before" && "$(cat "$FORK/CLAUDE.md")" == "v3" ]]; then
  ok "on a branch other than main: exit 3 with the reason, nothing committed"
else
  ko "on a branch other than main: exit $rc, stderr: $(cat "$T/err"), CLAUDE.md=$(cat "$FORK/CLAUDE.md")"
fi
git -C "$FORK" switch -q main
sync; rc=$?
if [[ $rc -eq 0 && "$(cat "$FORK/CLAUDE.md")" == "v4" ]]; then
  ok "back on main: pulled"
else
  ko "back on main: exit $rc, CLAUDE.md=$(cat "$FORK/CLAUDE.md"), stderr: $(cat "$T/err")"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
