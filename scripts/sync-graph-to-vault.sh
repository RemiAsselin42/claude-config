#!/usr/bin/env bash
# Copies GRAPH_REPORT, FILE_TREE and canvas to the Obsidian vault after each graphify update.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$SCRIPT_DIR" ]] && { echo "sync-graph-to-vault.sh: could not determine SCRIPT_DIR" >&2; exit 1; }
source "$SCRIPT_DIR/repo-identity.sh"
VAULT_BASE="$SCRIPT_DIR/../vault/Projets"
repo_name="$(canonical_repo_name "$PWD")"
local_name="$(basename "$PWD")"
dest="$VAULT_BASE/$repo_name"

[[ -f graphify-out/GRAPH_REPORT.md ]] || exit 0
if [[ "$local_name" != "$repo_name" && "${local_name,,}" != "${repo_name,,}" && -d "$VAULT_BASE/$local_name" ]]; then
  if [[ ! -d "$dest" ]]; then
    mv "$VAULT_BASE/$local_name" "$dest"
  else
    archive="$dest/_local-name-archives"
    mkdir -p "$archive"
    mv "$VAULT_BASE/$local_name" "$archive/$local_name-$(date +%s)"
  fi
fi
mkdir -p "$dest"

# A repo whose canonical name changed (wing: renamed, remote moved) leaves its old
# artifacts behind: the rename above moves the FOLDER, never the files inside it,
# which stay named after the previous repo. Every file matching these patterns is
# generated below, so anything not named after the current repo is a leftover.
find "$dest" -maxdepth 1 -type f \
  \( -name '*.canvas' -o -name '* - GRAPH_REPORT.md' -o -name '* - FILE_TREE.md' \) \
  ! -name "$repo_name.canvas" \
  ! -name "$repo_name - GRAPH_REPORT.md" \
  ! -name "$repo_name - FILE_TREE.md" \
  -delete

# GRAPH_REPORT
cp graphify-out/GRAPH_REPORT.md "$dest/$repo_name - GRAPH_REPORT.md"

# FILE_TREE
# `obsidian` is in the ignore lists below for the config repo's own tree: the vault
# lives inside it, so the walk would otherwise list every generated note — 44k
# lines of file names, rewritten on every sync.
{
  echo "# File Tree — $repo_name"
  echo ""
  echo "See also: [[$repo_name - GRAPH_REPORT]]"
  echo ""
  echo '```'
  if command -v tree &>/dev/null; then
    tree -I "node_modules|.git|dist|build|graphify-out|obsidian|.next|__pycache__|.venv|coverage" --dirsfirst -a
  elif command -v pwsh &>/dev/null || command -v powershell &>/dev/null; then
    PS=$(command -v pwsh || command -v powershell)
    TMPPS=$(mktemp --suffix=.ps1)
    cat > "$TMPPS" << 'PSEOF'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ignore = @('node_modules','.git','dist','build','graphify-out','obsidian','.next','__pycache__','.venv','coverage')
function Show-Tree($path, $indent='') {
  $items = Get-ChildItem -LiteralPath $path -Force |
    Where-Object { $ignore -notcontains $_.Name } |
    Sort-Object { -not $_.PSIsContainer }, Name
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item  = $items[$i]
    $last  = $i -eq $items.Count - 1
    $branch = if ($last) { [char]0x2514 + [char]0x2500 + [char]0x2500 + ' ' } else { [char]0x251C + [char]0x2500 + [char]0x2500 + ' ' }
    $ext    = if ($last) { '    ' } else { ([char]0x2502).ToString() + '   ' }
    Write-Output "$indent$branch$($item.Name)"
    if ($item.PSIsContainer) { Show-Tree $item.FullName "$indent$ext" }
  }
}
Write-Output '.'
Show-Tree (Get-Location).Path
PSEOF
    "$PS" -NoProfile -File "$TMPPS"
    rm -f "$TMPPS"
  else
    find . | sort | sed 's|[^/]*/|  |g'
  fi
  echo '```'
} > "$dest/$repo_name - FILE_TREE.md"

# Notes + canvas
# `graphify export obsidian` writes one .md per node AND graph.canvas whose cards
# are file links to those notes. The two must ship together: exporting the canvas
# alone (the previous behaviour here) left every card pointing at a note that was
# never written, so Obsidian offered "create a new file" on each one.
if [[ -f graphify-out/graph.json ]]; then
  notes_dir="$dest/obsidian"
  rm -rf "$notes_dir"   # drop notes for nodes that no longer exist

  # A node label carrying a control char (docstrings with a literal TAB) becomes an
  # invalid Windows filename: graphify's export dies mid-loop on OSError [Errno 22],
  # having written part of the notes and no canvas — and still exits 0. Export from
  # a sanitized copy of the graph instead. Read-only: the repo's graph.json is left
  # alone, and the sidecars (labels, analysis) still resolve from ./graphify-out/.
  graph_arg=()
  # `command -v python3` resolves to the Microsoft Store stub on Windows, which
  # prints an ad and exits nonzero — probe each candidate for a working interpreter.
  PY=""
  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "pass" >/dev/null 2>&1; then
      PY="$candidate"
      break
    fi
  done
  if [[ -n "$PY" ]]; then
    clean_graph="$(mktemp -t vault-graph-XXXXXX.json)"
    if "$PY" - "$clean_graph" << 'PYEOF'
import json, re, sys
from pathlib import Path
raw = json.loads(Path('graphify-out/graph.json').read_text(encoding='utf-8'))
for node in raw.get('nodes', []):
    label = node.get('label')
    if isinstance(label, str):
        node['label'] = re.sub(r'[\x00-\x1f]+', ' ', label).strip()
Path(sys.argv[1]).write_text(json.dumps(raw), encoding='utf-8')
PYEOF
    then
      graph_arg=(--graph "$clean_graph")
      # An explicit --graph re-bases the labels sidecar to the graph's own folder
      # (cli.py: `if graph_path_explicit: labels_path = graph_out_dir / ...`), so
      # the temp copy would silently lose every community name and the canvas
      # groups would read "Community 12" again. Point it back at the repo's file.
      [[ -f graphify-out/.graphify_labels.json ]] && \
        graph_arg+=(--labels graphify-out/.graphify_labels.json)
    else
      rm -f "$clean_graph"
      echo "label sanitize skip: falling back to the raw graph" >&2
    fi
  fi

  if graphify export obsidian "${graph_arg[@]}" --dir "$notes_dir" >/dev/null 2>&1; then
    # graphify drops a vault config inside --dir; it is meant for opening that dir
    # as a standalone vault, and a nested .obsidian/ inside the real vault is junk.
    rm -rf "$notes_dir/.obsidian"

    # Nodes labelled ".method()" (a bare method, no class prefix) produce dotfile
    # notes, which Obsidian hides entirely — the note exists on disk but no link
    # to it ever resolves. Un-hide them with a "_" prefix and fix the wikilinks
    # that point at them ("[[.foo()]]" -> "[[_.foo()]]"). Canvas refs are fixed in
    # the same pass below. A pre-existing "_.name" would be a graphify label
    # starting with "_." — not a thing in practice.
    dotfiles=0
    for f in "$notes_dir"/.*.md; do
      [[ -e "$f" ]] || continue
      mv -- "$f" "$notes_dir/_$(basename "$f")" && dotfiles=$((dotfiles + 1))
    done
    if (( dotfiles > 0 )); then
      find "$notes_dir" -name '*.md' -exec sed -i 's|\[\[\.|[[_.|g' {} +
    fi

    # Canvas file links are resolved from the VAULT ROOT, not from the canvas's own
    # folder, so the bare "Foo.md" graphify emits only resolves when the notes sit
    # at the root. Rewrite to the notes' real vault-relative location.
    # Safe as a literal substitution: safe_name() strips / \ " from note names.
    if [[ -f "$notes_dir/graph.canvas" ]]; then
      sed -e "s|\"file\": \"|\"file\": \"Projets/$repo_name/obsidian/|g" \
        -e "s|/obsidian/\.|/obsidian/_.|g" \
        "$notes_dir/graph.canvas" > "$dest/$repo_name.canvas"
      rm -f "$notes_dir/graph.canvas"
    else
      # graphify exits 0 even when the export dies partway through, so a missing
      # canvas is the only signal that the notes are incomplete. Say so instead of
      # leaving a stale canvas in the vault pointing at notes that were never written.
      echo "canvas missing after export in $PWD — notes are likely incomplete" >&2
    fi
  else
    echo "obsidian export skip: graphify export obsidian failed" >&2
  fi
  [[ -n "${clean_graph:-}" ]] && rm -f "$clean_graph"
fi
