#!/usr/bin/env bash
# Self-check for install.sh's per-repo CLAUDE.md refresh.
#
# The refresh has to do three things at once and it is easy to break one of them
# silently: bring an old machine's stale file up to the current template, keep
# whatever notes the user wrote under it, and never touch a CLAUDE.md install.sh
# did not generate. Run it after touching _refresh_project_claude_md,
# CLAUDE_MD_BOUNDARIES or templates/CLAUDE.project.md:
#
#   bash tests/claude-md-refresh.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# Read by the functions eval'd in below, which shellcheck cannot see.
# shellcheck disable=SC2034
VAULT_DIR="/tmp/vault"   # only ever substituted into the template text
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Functions under test, taken straight from install.sh (array + two functions).
eval "$(awk '/^CLAUDE_MD_BOUNDARIES=\(/{f=1} f{print} f&&/^}/{n++; if(n==2) exit}' "$REPO_DIR/install.sh")"

pass=0
fail=0
ok()   { echo "  PASS  $1"; pass=$((pass + 1)); }
ko()   { echo "  FAIL  $1"; fail=$((fail + 1)); }
has()  { grep -qF -e "$2" "$1/CLAUDE.md"; }   # -e: patterns can start with --
run()  { _refresh_project_claude_md "$1" demo-repo; }

# A CLAUDE.md as the oldest generation of the template produced it: three
# sections of tooling prose, ending on the boundary line of that generation.
legacy_file() {
  mkdir -p "$1"
  cat > "$1/CLAUDE.md" <<'LEGACY'
## Graphify (Knowledge Graph)

This project has a graphify knowledge graph at graphify-out/.

- fall back to `~/.claude/memory/../vault/Projets/demo-repo/GRAPH_REPORT.md`

## Persistent Memory (MemPalace)

```bash
mempalace search "topic" --wing demo-repo
```

## Obsidian Vault

The vault is committed automatically after each `./install.sh` run and after each `graphify update`.
LEGACY
}

echo "1. absent → rendered from the template"
mkdir -p "$T/absent"
[[ "$(run "$T/absent")" == generated ]] && has "$T/absent" '--wing wing_demo_repo' \
  && ok "generated with the wing in its stored form" || ko "generated"

echo "2. stale file from an older machine → brought up to date"
legacy_file "$T/legacy"
state="$(run "$T/legacy")"
[[ "$state" == refreshed ]] || ko "state was '$state', want 'refreshed'"
has "$T/legacy" '--wing wing_demo_repo'            && ok "wrong --wing form replaced"  || ko "wing not fixed"
has "$T/legacy" 'This project has a graphify'      && ko "legacy body survived"        || ok "legacy body dropped"
has "$T/legacy" '.claude/memory'                   && ko "dead memory path survived"   || ok "dead memory path gone"

echo "3. idempotence"
[[ "$(run "$T/legacy")" == "up to date" ]] && ok "second run changes nothing" || ko "not idempotent"

echo "4. user notes below the boundary are kept"
mkdir -p "$T/notes"
{ _render_project_claude_md demo-repo; printf '\n## Build\n\n`npm run weird-thing`\n'; } > "$T/notes/CLAUDE.md"
run "$T/notes" >/dev/null
has "$T/notes" 'npm run weird-thing' && ok "kept under a current file" || ko "notes lost"
legacy_file "$T/notes2"
printf '\n## Build\n\n`npm run weird-thing`\n' >> "$T/notes2/CLAUDE.md"
run "$T/notes2" >/dev/null
has "$T/notes2" 'npm run weird-thing' && ok "kept while replacing a legacy file" || ko "notes lost on legacy"

echo "5. a CLAUDE.md we never generated is left alone"
mkdir -p "$T/mine"
printf '# my repo\n\nDo not touch this.\n' > "$T/mine/CLAUDE.md"
before="$(cat "$T/mine/CLAUDE.md")"
[[ "$(run "$T/mine")" == "kept (hand-written)" && "$before" == "$(cat "$T/mine/CLAUDE.md")" ]] \
  && ok "untouched" || ko "a hand-written file was rewritten"

echo
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
