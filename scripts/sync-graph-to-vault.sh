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

# GRAPH_REPORT
cp graphify-out/GRAPH_REPORT.md "$dest/$repo_name - GRAPH_REPORT.md"

# FILE_TREE
{
  echo "# File Tree — $repo_name"
  echo ""
  echo "See also: [[$repo_name - GRAPH_REPORT]]"
  echo ""
  echo '```'
  if command -v tree &>/dev/null; then
    tree -I "node_modules|.git|dist|build|graphify-out|.next|__pycache__|.venv|coverage" --dirsfirst -a
  elif command -v pwsh &>/dev/null || command -v powershell &>/dev/null; then
    PS=$(command -v pwsh || command -v powershell)
    TMPPS=$(mktemp --suffix=.ps1)
    cat > "$TMPPS" << 'PSEOF'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ignore = @('node_modules','.git','dist','build','graphify-out','.next','__pycache__','.venv','coverage')
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

# Canvas
if [[ -f graphify-out/graph.json ]]; then
  TMPPY=$(mktemp --suffix=.py)
  cat > "$TMPPY" << 'PYEOF'
import sys, json
from pathlib import Path
from collections import defaultdict
try:
    from graphify.build import build_from_json
    from graphify.export import to_canvas
    raw = json.loads(Path('graphify-out/graph.json').read_text())
    G = build_from_json(raw)
    communities = defaultdict(list)
    for node in raw.get('nodes', []):
        cid = node.get('community')
        if cid is not None:
            communities[cid].append(node['id'])
    communities = dict(communities)
    labels_path = Path('graphify-out/.graphify_labels.json')
    labels = {int(k): v for k, v in json.loads(labels_path.read_text()).items()} if labels_path.exists() else None
    to_canvas(G, communities, sys.argv[1], community_labels=labels)
except Exception as e:
    print(f'canvas skip: {e}', file=sys.stderr)
PYEOF
  if command -v uv &>/dev/null; then
    uv run --no-project python "$TMPPY" "$dest/$repo_name.canvas" 2>/dev/null || echo "canvas skip: uv run failed" >&2
  else
    PY=$(command -v python3 || echo "")
    [[ -z "$PY" ]] && echo "canvas skip: no python found" >&2 || "$PY" "$TMPPY" "$dest/$repo_name.canvas"
  fi
  rm -f "$TMPPY"
fi
