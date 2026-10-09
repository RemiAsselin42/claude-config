#!/usr/bin/env bash
# Self-check for scripts/harness-drift.sh, the integrity check session-start.sh
# runs at every session start: the deployed harness against the clone
# install.sh deployed from (deployed ≠ clone), and the clone against its last
# fetched origin/<default branch> (clone ≠ origin). Everything lives in a temp
# dir: a throwaway clone with a fake origin ref, a throwaway CLAUDE_CONFIG_DIR
# deployed from it the way install.sh does, stubs on PATH for jq and mempalace.
#
#   bash tests/harness-drift.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
HD="$REPO_DIR/scripts/harness-drift.sh"
SS="$REPO_DIR/scripts/session-start.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fails=0
ok() { echo "ok   $1"; }
ko() {  # ko <description> [detail lines...]
  echo "FAIL $1"; shift
  [ -f "$HD" ] || echo "     (scripts/harness-drift.sh does not exist)"
  local l; for l in "$@"; do printf '%s\n' "$l" | sed 's/^/     /'; done
  fails=$((fails + 1))
}
is_eq() {    # is_eq <description> <expected> <got>
  if [ "$3" = "$2" ]; then ok "$1"; else ko "$1" "expected: $2" "got:      $3"; fi
}
has_line() { # has_line <description> <exact line> <got>
  if printf '%s\n' "$3" | grep -qxF -- "$2"; then ok "$1"; else ko "$1" "expected line: $2" "got:" "$3"; fi
}
exists() { [ -e "$1" ] && echo true || echo false; }

# ── Fixtures: a clone on main with origin/main = HEAD, deployed into $D ───────
C="$tmp/clone"; D="$tmp/cfg"
mkdir -p "$C/hooks" "$C/agents" "$C/commands" "$C/scripts" "$C/mods/p/.claude-plugin" "$C/vault"
printf '# Global\nVault: ${VAULT_DIR}/Projets\n' > "$C/CLAUDE.md"
cat > "$C/settings.json" <<'EOF'
{ "model": "fable", "effortLevel": "xhigh",
  "permissions": { "allow": ["Bash(git status*)"], "deny": ["Bash(gh pr merge*)"] },
  "extraKnownMarketplaces": { "hono": { "source": { "source": "github", "repo": "honojs/skills" } } },
  "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "node ~/.claude/hooks/g.js" } ] } ] } }
EOF
printf 'module.exports = 1;\n' > "$C/hooks/g.js"
printf -- '---\nname: r\n---\nreview\n' > "$C/agents/r.md"
printf 'cmd\n' > "$C/commands/c.md"
printf '#!/usr/bin/env bash\necho s\n' > "$C/scripts/s.sh"
printf '{ "name": "p", "version": "1.0.0" }\n' > "$C/mods/p/.claude-plugin/plugin.json"
git -C "$C" init -q -b main
git -C "$C" -c user.email=t@t -c user.name=t add -A
git -C "$C" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$C" update-ref refs/remotes/origin/main HEAD
git -C "$C" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# What install.sh does: copy, substitute ${VAULT_DIR}, then what a machine writes
# into its own settings.json (the tolerated keys: /model, effort, the local marketplace).
deploy() {
  rm -rf "$D"; mkdir -p "$D"
  printf '%s\n' "$C" > "$D/claude-config.path"
  cp -r "$C/hooks" "$C/agents" "$C/commands" "$C/scripts" "$C/mods" "$D/"
  sed "s|\${VAULT_DIR}|$C/vault|g" "$C/CLAUDE.md" > "$D/CLAUDE.md"
  jq '.model = "opus" | .effortLevel = "high"
      | .extraKnownMarketplaces["claude-config"] = {source: {source: "directory", path: "/x/mods"}}' \
    "$C/settings.json" > "$D/settings.json"
}
edit_settings() { jq "$1" "$D/settings.json" > "$D/s.tmp" && mv "$D/s.tmp" "$D/settings.json"; }
run() { CLAUDE_CONFIG_DIR="$D" bash "$HD" 2>&1; }

echo "== 1. deployed as install.sh left it: silent, no marker, exit 0"
deploy
is_eq "1 no output" "" "$(run)"
is_eq "1 no marker" false "$(exists "$D/.harness-drift")"
is_eq "1 exit 0" 0 "$(run >/dev/null 2>&1; echo $?)"

echo "== 2. the three tolerated keys differ further: still silent"
edit_settings '.model = "sonnet" | .effortLevel = "low" | .extraKnownMarketplaces["claude-config"].source.path = "/y"'
is_eq "2 silent" "" "$(run)"

echo "== 3. settings.json: a permission added on the machine is named with its key"
edit_settings '.permissions.allow += ["Bash(rm -rf *)"]'
has_line "3 settings.json (permissions.allow)" "deployed ≠ clone: settings.json (permissions.allow)" "$(run)"
deploy

echo "== 4. settings.json: a hook command changed is named with its key"
edit_settings '.hooks.PreToolUse[0].hooks[0].command = "true"'
has_line "4 settings.json (hooks.PreToolUse)" "deployed ≠ clone: settings.json (hooks.PreToolUse)" "$(run)"
deploy

echo "== 5. a deployed hook edited, an agent missing, a command added by hand: all three named"
printf 'module.exports = 2;\n' > "$D/hooks/g.js"; rm "$D/agents/r.md"; printf 'x\n' > "$D/commands/extra.md"
has_line "5 three items" "deployed ≠ clone: hooks/g.js, agents/r.md (not deployed), commands/extra.md (no source in the clone)" "$(run)"
deploy

echo "== 6. a leftover in scripts/ and a file Claude Code lays into mods/ are not drift; an edited mods file is"
printf 'old\n' > "$D/scripts/old.sh"; mkdir -p "$D/mods/p/.claude-plugin/types"; printf '{}\n' > "$D/mods/p/.claude-plugin/types/x.d.ts"
is_eq "6 extras in scripts/ and mods/: silent" "" "$(run)"
printf '{ "name": "p", "version": "1.0.1" }\n' > "$D/mods/p/.claude-plugin/plugin.json"
has_line "6 edited mods file named" "deployed ≠ clone: mods/p/.claude-plugin/plugin.json" "$(run)"
deploy

echo "== 7. CLAUDE.md: the substituted copy is not drift, an edit is"
is_eq "7 substituted copy: silent" "" "$(run)"
printf '\nextra\n' >> "$D/CLAUDE.md"
has_line "7 edited CLAUDE.md named" "deployed ≠ clone: CLAUDE.md" "$(run)"
deploy

echo "== 8. level 2: a clone file modified and deployed identically is a clone drift, not a deployed one"
printf '#!/usr/bin/env bash\necho s2\n' > "$C/scripts/s.sh"; deploy
out=$(run)
has_line "8 clone ≠ origin/main: scripts/s.sh" "clone ≠ origin/main: scripts/s.sh" "$out"
is_eq "8 no deployed line" "" "$(printf '%s\n' "$out" | grep '^deployed' || true)"
printf 'new\n' > "$C/hooks/new.sh"; deploy   # untracked in the clone, deployed all the same
has_line "8 an untracked clone file is listed too" "clone ≠ origin/main: scripts/s.sh, hooks/new.sh" "$(run)"
git -C "$C" checkout -q -- scripts/s.sh; rm -f "$C/hooks/new.sh"; deploy
is_eq "8 back in sync: silent" "" "$(run)"

echo "== 9. the marker for the statusline: first three items then a count, removed once clean"
printf 'module.exports = 2;\n' > "$D/hooks/g.js"
for i in 1 2 3 4 5; do printf 'x\n' > "$D/commands/x$i.md"; done
run >/dev/null
is_eq "9 marker short form" "deployed ≠ clone: hooks/g.js, commands/x1.md (no source in the clone), commands/x2.md (no source in the clone) +3 more" "$(cat "$D/.harness-drift" 2>/dev/null)"
deploy; run >/dev/null
is_eq "9 marker removed once clean" false "$(exists "$D/.harness-drift")"

echo "== 10. no pointer, a pointer to nothing, no origin ref"
rm "$D/claude-config.path"
has_line "10 missing claude-config.path" "harness clone unknown: $D/claude-config.path → missing — run install.sh" "$(run)"
is_eq "10 marker written" true "$(exists "$D/.harness-drift")"
deploy; printf '%s\n' "$tmp/nowhere" > "$D/claude-config.path"
has_line "10 pointer to a missing directory" "harness clone unknown: $D/claude-config.path → $tmp/nowhere — run install.sh" "$(run)"
deploy; git -C "$C" symbolic-ref --delete refs/remotes/origin/HEAD; git -C "$C" update-ref -d refs/remotes/origin/main
has_line "10 no origin ref fetched" "clone: no origin/main or origin/master fetched" "$(run)"
git -C "$C" update-ref refs/remotes/origin/main HEAD
is_eq "10 origin/main found without origin/HEAD: silent" "" "$(run)"
git -C "$C" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

echo "== 11. jq unusable: settings.json reported unchecked, the rest still compared"
stubs="$tmp/stubs"; mkdir -p "$stubs"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/jq"; chmod +x "$stubs/jq"
printf 'module.exports = 2;\n' > "$D/hooks/g.js"
has_line "11 settings.json unchecked, hooks/g.js named" "deployed ≠ clone: settings.json (not checked: jq failed), hooks/g.js" "$(CLAUDE_CONFIG_DIR="$D" PATH="$stubs:$PATH" bash "$HD" 2>&1)"
rm -f "$stubs/jq"; deploy

echo "== 12. session-start.sh: drift → JSON with a systemMessage and the context; clean → plain text as before"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/mempalace"; chmod +x "$stubs/mempalace"   # no daemon, no diary
printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$stubs/timeout"; chmod +x "$stubs/timeout"
proj="$tmp/proj"; mkdir -p "$proj"; printf -- '- todo one\n' > "$proj/TODO.md"
printf 'module.exports = 2;\n' > "$D/hooks/g.js"
out=$(cd "$proj" && CLAUDE_CONFIG_DIR="$D" PATH="$stubs:$PATH" bash "$SS" 2>/dev/null)
msg=$(printf '%s' "$out" | jq -r '.systemMessage' 2>/dev/null)
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
is_eq "12 hookEventName SessionStart" SessionStart "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
is_eq "12 systemMessage names the drift" true "$(printf '%s' "$msg" | grep -q 'Harness drift.*deployed ≠ clone: hooks/g.js' && echo true || echo false)"
has_line "12 context keeps TODO.md" "- todo one" "$ctx"
has_line "12 context carries the harness section" "## Harness check" "$ctx"
has_line "12 context carries the drift line" "deployed ≠ clone: hooks/g.js" "$ctx"
deploy
out=$(cd "$proj" && CLAUDE_CONFIG_DIR="$D" PATH="$stubs:$PATH" bash "$SS" 2>/dev/null)
has_line "12 clean: plain text, TODO.md heading" "## TODO.md" "$out"
is_eq "12 clean: not JSON" false "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo true || echo false)"
is_eq "12 clean: no harness section" "" "$(printf '%s\n' "$out" | grep -i 'harness' || true)"

echo "== 13. an upstream remote: the alert compares to upstream/<default>, origin becomes an information line"
printf '#!/usr/bin/env bash\necho s3\n' > "$C/scripts/s.sh"
git -C "$C" -c user.email=t@t -c user.name=t commit -q -am "shared change"
git -C "$C" remote add upstream "$tmp/nowhere.git"
git -C "$C" update-ref refs/remotes/upstream/main HEAD   # upstream holds the change (no upstream/HEAD: the main fallback), origin/main does not
deploy
out=$(run)
is_eq "13 no alert line" "" "$(printf '%s\n' "$out" | grep -v '^info: ' || true)"
has_line "13 origin as information" "info: clone ≠ origin/main: scripts/s.sh" "$out"
is_eq "13 no marker for an information line" false "$(exists "$D/.harness-drift")"

echo "== 14. a shared file modified in the clone: the alert names upstream/main, origin stays informational"
printf '#!/usr/bin/env bash\necho s4\n' > "$C/scripts/s.sh"; deploy
out=$(run)
has_line "14 clone ≠ upstream/main: scripts/s.sh" "clone ≠ upstream/main: scripts/s.sh" "$out"
has_line "14 information line against origin" "info: clone ≠ origin/main: scripts/s.sh" "$out"
is_eq "14 the marker holds the alert only" "clone ≠ upstream/main: scripts/s.sh" "$(cat "$D/.harness-drift" 2>/dev/null)"
git -C "$C" checkout -q -- scripts/s.sh; deploy

echo "== 15. an upstream remote with nothing fetched: an alert, not silence"
git -C "$C" update-ref -d refs/remotes/upstream/main
has_line "15 no upstream ref" "clone: no upstream/main or upstream/master fetched" "$(run)"
git -C "$C" update-ref refs/remotes/upstream/main HEAD
is_eq "15 fetched again: no alert" "" "$(run | grep -v '^info: ' || true)"

echo "== 16. session-start.sh with an information line only: plain text that carries it, no systemMessage, no marker"
out=$(cd "$proj" && CLAUDE_CONFIG_DIR="$D" PATH="$stubs:$PATH" bash "$SS" 2>/dev/null)
is_eq "16 not JSON" false "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo true || echo false)"
has_line "16 the information line is in the context" "info: clone ≠ origin/main: scripts/s.sh" "$out"
has_line "16 under the harness heading" "## Harness check" "$out"
is_eq "16 no marker" false "$(exists "$D/.harness-drift")"

echo
if (( fails )); then echo "$fails failure(s)"; exit 1; fi
echo "all harness-drift checks passed"
