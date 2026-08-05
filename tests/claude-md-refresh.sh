#!/usr/bin/env bash
# Self-check for install.sh's per-repo CLAUDE.md refresh.
#
# The refresh has to do several things at once and it is easy to break one of
# them silently: bring an old machine's stale file up to the current template,
# name both MemPalace wings correctly, keep whatever notes the user wrote under
# it, and never touch a CLAUDE.md install.sh did not generate. Run it after
# touching _refresh_project_claude_md, _wing_for_repo, _diary_wing_for_repo,
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

# Functions under test, taken straight out of install.sh (array + 4 functions).
eval "$(awk '/^CLAUDE_MD_BOUNDARIES=\(/{f=1} f{print} f&&/^}/{n++; if(n==4) exit}' "$REPO_DIR/install.sh")"

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }
has() { grep -qF -e "$2" "$1/CLAUDE.md"; }   # -e: patterns can start with --
run() { _refresh_project_claude_md "$1" demo-repo; }

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
[[ "$(run "$T/absent")" == generated ]] && has "$T/absent" '--wing demo-repo' \
  && ok "generated, mine wing from the repo name" || ko "generated"

echo "2. stale file from an older machine → brought up to date"
legacy_file "$T/legacy"
state="$(run "$T/legacy")"
[[ "$state" == refreshed ]] || ko "state was '$state', want 'refreshed'"
has "$T/legacy" 'This project has a graphify' && ko "legacy body survived" || ok "legacy body dropped"
has "$T/legacy" '.claude/memory'              && ko "dead memory path survived" || ok "dead memory path gone"

echo "3. idempotence"
[[ "$(run "$T/legacy")" == "up to date" ]] && ok "second run changes nothing" || ko "not idempotent"

echo "4. both wings, named the way mempalace stores them"
# mempalace.yaml is what `mempalace mine --wing` is given, so it wins over the
# repo name; the diary wing comes from the directory, lowercased.
mkdir -p "$T/My-Repo"
printf 'wing: Canonical-Name\n' > "$T/My-Repo/mempalace.yaml"
run "$T/My-Repo" >/dev/null
has "$T/My-Repo" '--wing Canonical-Name' && ok "mine wing taken from mempalace.yaml" || ko "mempalace.yaml ignored"
has "$T/My-Repo" '--wing wing_my_repo'   && ok "diary wing lowercased from the directory" || ko "diary wing wrong"

echo "5. user notes below the boundary are kept"
mkdir -p "$T/notes"
{ _render_project_claude_md "$T/notes" demo-repo; printf '\n## Build\n\n`npm run weird-thing`\n'; } > "$T/notes/CLAUDE.md"
run "$T/notes" >/dev/null
has "$T/notes" 'npm run weird-thing' && ok "kept under a current file" || ko "notes lost"
legacy_file "$T/notes2"
printf '\n## Build\n\n`npm run weird-thing`\n' >> "$T/notes2/CLAUDE.md"
run "$T/notes2" >/dev/null
has "$T/notes2" 'npm run weird-thing' && ok "kept while replacing a legacy file" || ko "notes lost on legacy"

echo "6. a CLAUDE.md we never generated is left alone"
mkdir -p "$T/mine"
printf '# my repo\n\nDo not touch this.\n' > "$T/mine/CLAUDE.md"
before="$(cat "$T/mine/CLAUDE.md")"
[[ "$(run "$T/mine")" == "kept (hand-written)" && "$before" == "$(cat "$T/mine/CLAUDE.md")" ]] \
  && ok "untouched" || ko "a hand-written file was rewritten"

echo
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
