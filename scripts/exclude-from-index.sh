#!/usr/bin/env bash
# exclude-from-index.sh [--yes] <repo-path> [<repo-path> ...]
#
# Excludes one or more repos from graphify + mempalace + Obsidian vault indexing.
# --yes : removes graphify-out/ and the vault folder without prompting (non-interactive).
# Idempotent — safe to re-run.

set -euo pipefail

AUTO_YES=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  AUTO_YES=true
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-identity.sh"
VAULT_PROJETS="$SCRIPT_DIR/../vault/Projets"

# ── colors ────────────────────────────────────────────────────────────────────
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${DIM}✓ $*${NC}"; }
warn() { echo -e "  ${YELLOW}⚠  $*${NC}"; }
info() { echo -e "  ${DIM}· $*${NC}"; }
err()  { echo -e "  ${RED}✗ $*${NC}"; }

# ── python available? ─────────────────────────────────────────────────────────
_find_python() {
  local cmd
  for cmd in python3 python py; do
    command -v "$cmd" &>/dev/null || continue
    "$cmd" -c 'import sys' >/dev/null 2>&1 || continue
    printf '%s\n' "$cmd"
    return 0
  done
  return 1
}
PYTHON="$(_find_python || true)"

# ── delete a mempalace wing via chromadb ──────────────────────────────────────
delete_mempalace_wing() {
  local wing="$1"
  local -a py_cmd

  if [[ -n "$PYTHON" ]] && "$PYTHON" -c 'import chromadb' >/dev/null 2>&1; then
    py_cmd=("$PYTHON")
  elif command -v uv &>/dev/null; then
    info "Mempalace: chromadb not in current Python — falling back to uv..."
    if uv run --no-project --quiet --with chromadb python -c 'import chromadb' >/dev/null 2>&1; then
      py_cmd=(uv run --no-project --quiet --with chromadb python)
    else
      warn "Mempalace: could not install chromadb via uv — cleanup skipped"
      return 0
    fi
  else
    warn "Mempalace: chromadb missing and uv not found — cleanup skipped"
    return 0
  fi

  local palace_path
  palace_path="$("${py_cmd[@]}" -c "
import json, os, pathlib
cfg = pathlib.Path.home() / '.mempalace' / 'config.json'
if cfg.exists():
    d = json.loads(cfg.read_text())
    print(d.get('palace_path', str(pathlib.Path.home() / '.mempalace' / 'palace')))
else:
    print(str(pathlib.Path.home() / '.mempalace' / 'palace'))
" 2>/dev/null || echo "$HOME/.mempalace/palace")"

  local result
  if ! result="$("${py_cmd[@]}" - "$palace_path" "$wing" 2>&1 << 'PYEOF'
import sys, chromadb

palace_path, wing = sys.argv[1], sys.argv[2]
client = chromadb.PersistentClient(path=palace_path)

total = 0
for col_name in ["mempalace_drawers", "mempalace_closets"]:
    try:
        col = client.get_collection(col_name)
        ids = col.get(where={"wing": wing}, include=[])["ids"]
        if ids:
            col.delete(ids=ids)
            total += len(ids)
    except Exception:
        pass

print(total)
PYEOF
)"; then
    info "Mempalace: wing '$wing' not deleted — database inaccessible, cleanup skipped"
    return 0
  fi

  if [[ "$result" =~ ^[0-9]+$ ]]; then
    if [[ "$result" -gt 0 ]]; then
      ok "Mempalace: $result entries deleted (wing '$wing')"
    else
      info "Mempalace: wing '$wing' already absent or empty"
    fi
  else
    info "Mempalace: unexpected response — cleanup skipped"
  fi
}

# ── process a repo ────────────────────────────────────────────────────────────
exclude_repo() {
  local repo_path
  repo_path="$(realpath "$1")"
  local repo_name
  repo_name="$(canonical_repo_name "$repo_path")"
  local local_name
  local_name="$(basename "$repo_path")"
  local repo_label="$repo_name"
  [[ "$local_name" != "$repo_name" ]] && repo_label="$local_name -> $repo_name"

  echo -e "\033[1m[$repo_label]\033[0m \033[1;33mExcluding...\033[0m"

  # validation
  if [[ ! -d "$repo_path" ]]; then
    err "Directory not found: $repo_path"; return 1
  fi

  # ── 1. graphify hooks ──────────────────────────────────────────────────────
  if ! command -v graphify &>/dev/null; then
    warn "graphify not found — hooks not uninstalled (not in PATH)"
  elif [[ -d "$repo_path/.git" ]]; then
    local hook="$repo_path/.git/hooks/post-commit"
    if grep -q "graphify" "$hook" 2>/dev/null; then
      if (cd "$repo_path" && graphify hook uninstall 2>/dev/null); then
        ok "Graphify: hooks uninstalled"
      else
        warn "Graphify: hook uninstall failed (non-blocking)"
      fi
    else
      info "Graphify: no hooks installed"
    fi
  else
    info "Graphify: not a git repo, hooks skipped"
  fi

  # ── 2. .graphifyignore ────────────────────────────────────────────────────
  local ignore_file="$repo_path/.graphifyignore"
  if [[ ! -f "$ignore_file" ]]; then
    touch "$ignore_file"
    ok "Graphify: .graphifyignore created"
  else
    info "Graphify: .graphifyignore already present"
  fi

  # ── 3. existing graphify-out ──────────────────────────────────────────────
  if [[ -d "$repo_path/graphify-out" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$repo_path/graphify-out"
      ok "Graphify: graphify-out/ deleted"
    else
      warn "graphify-out/ present — delete? (y/N) "
      read -r answer
      if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        rm -rf "$repo_path/graphify-out"
        ok "Graphify: graphify-out/ deleted"
      else
        info "Graphify: graphify-out/ kept"
      fi
    fi
  fi

  # ── 4. mempalace wing ─────────────────────────────────────────────────────
  delete_mempalace_wing "$repo_name"

  # ── 5. Obsidian vault ────────────────────────────────────────────────────
  local vault_dir="$VAULT_PROJETS/$repo_name"
  if [[ -d "$vault_dir" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$vault_dir"
      ok "Vault: $vault_dir deleted"
    else
      warn "Obsidian vault: delete $vault_dir? (y/N) "
      read -r answer
      if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        rm -rf "$vault_dir"
        ok "Vault: $vault_dir deleted"
      else
        info "Vault: kept"
      fi
    fi
  else
    info "Vault: no folder found for '$repo_name'"
  fi

  local legacy_vault_dir="$VAULT_PROJETS/$local_name"
  if [[ "$local_name" != "$repo_name" && -d "$legacy_vault_dir" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$legacy_vault_dir"
      ok "Vault: legacy local folder $legacy_vault_dir deleted"
    else
      warn "Obsidian vault: delete legacy local folder $legacy_vault_dir? (y/N) "
      read -r answer
      if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        rm -rf "$legacy_vault_dir"
        ok "Vault: legacy local folder deleted"
      else
        info "Vault: legacy local folder kept"
      fi
    fi
  fi

  echo -e "  ${GREEN}✓ $repo_label${NC}"
}

# ── main ──────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--yes] <repo-path> [<repo-path> ...]"
  echo ""
  echo "  --yes   Deletes graphify-out/ and the vault without confirmation (non-interactive)."
  echo ""
  echo "Excludes a repo from graphify (hooks + .graphifyignore),"
  echo "deletes its mempalace wing, and cleans up the Obsidian vault."
  exit 1
fi

for path in "$@"; do
  exclude_repo "$path"
done
