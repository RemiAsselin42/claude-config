#!/usr/bin/env bash
# exclude-from-index.sh [--yes] <repo-path> [<repo-path> ...]
#
# Exclut un ou plusieurs repos de l'indexation graphify + mempalace + vault Obsidian.
# --yes : supprime graphify-out/ et le dossier vault sans demander (mode non-interactif).
# Idempotent — safe à relancer.

set -euo pipefail

AUTO_YES=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  AUTO_YES=true
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-identity.sh"
VAULT_PROJETS="$SCRIPT_DIR/../vault/Projets"

# ── couleurs ──────────────────────────────────────────────────────────────────
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${DIM}✓ $*${NC}"; }
warn() { echo -e "  ${YELLOW}⚠  $*${NC}"; }
info() { echo -e "  ${DIM}· $*${NC}"; }
err()  { echo -e "  ${RED}✗ $*${NC}"; }

# ── python disponible ? ───────────────────────────────────────────────────────
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

# ── supprime un wing mempalace via chromadb ───────────────────────────────────
delete_mempalace_wing() {
  local wing="$1"
  local -a py_cmd

  if [[ -n "$PYTHON" ]] && "$PYTHON" -c 'import chromadb' >/dev/null 2>&1; then
    py_cmd=("$PYTHON")
  elif command -v uv &>/dev/null; then
    info "Mempalace : chromadb absent du Python courant — utilisation via uv..."
    if uv run --no-project --quiet --with chromadb python -c 'import chromadb' >/dev/null 2>&1; then
      py_cmd=(uv run --no-project --quiet --with chromadb python)
    else
      warn "Mempalace : impossible d'installer chromadb via uv — nettoyage ignoré"
      return 0
    fi
  else
    warn "Mempalace : chromadb absent et uv introuvable — nettoyage ignoré"
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
    info "Mempalace : wing '$wing' non supprimé — base inaccessible, nettoyage ignoré"
    return 0
  fi

  if [[ "$result" =~ ^[0-9]+$ ]]; then
    if [[ "$result" -gt 0 ]]; then
      ok "Mempalace : $result entrées supprimées (wing '$wing')"
    else
      info "Mempalace : wing '$wing' déjà absent ou vide"
    fi
  else
    info "Mempalace : réponse inattendue — nettoyage ignoré"
  fi
}

# ── traitement d'un repo ──────────────────────────────────────────────────────
exclude_repo() {
  local repo_path
  repo_path="$(realpath "$1")"
  local repo_name
  repo_name="$(canonical_repo_name "$repo_path")"
  local local_name
  local_name="$(basename "$repo_path")"
  local repo_label="$repo_name"
  [[ "$local_name" != "$repo_name" ]] && repo_label="$local_name -> $repo_name"

  echo -e "\033[1m[$repo_label]\033[0m \033[1;33mExclusion...\033[0m"

  # validation
  if [[ ! -d "$repo_path" ]]; then
    err "Dossier introuvable : $repo_path"; return 1
  fi

  # ── 1. graphify hooks ──────────────────────────────────────────────────────
  if ! command -v graphify &>/dev/null; then
    warn "graphify introuvable — hooks non désinstallés (pas dans PATH)"
  elif [[ -d "$repo_path/.git" ]]; then
    local hook="$repo_path/.git/hooks/post-commit"
    if grep -q "graphify" "$hook" 2>/dev/null; then
      if (cd "$repo_path" && graphify hook uninstall 2>/dev/null); then
        ok "Graphify : hooks désinstallés"
      else
        warn "Graphify : désinstallation des hooks échouée (non-bloquant)"
      fi
    else
      info "Graphify : aucun hook installé"
    fi
  else
    info "Graphify : pas un repo git, hooks ignorés"
  fi

  # ── 2. .graphifyignore ────────────────────────────────────────────────────
  local ignore_file="$repo_path/.graphifyignore"
  if [[ ! -f "$ignore_file" ]]; then
    touch "$ignore_file"
    ok "Graphify : .graphifyignore créé"
  else
    info "Graphify : .graphifyignore déjà présent"
  fi

  # ── 3. graphify-out existant ──────────────────────────────────────────────
  if [[ -d "$repo_path/graphify-out" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$repo_path/graphify-out"
      ok "Graphify : graphify-out/ supprimé"
    else
      warn "graphify-out/ présent — suppression ? (o/N) "
      read -r answer
      if [[ "${answer,,}" == "o" ]]; then
        rm -rf "$repo_path/graphify-out"
        ok "Graphify : graphify-out/ supprimé"
      else
        info "Graphify : graphify-out/ conservé"
      fi
    fi
  fi

  # ── 4. mempalace wing ─────────────────────────────────────────────────────
  delete_mempalace_wing "$repo_name"

  # ── 5. vault Obsidian ────────────────────────────────────────────────────
  local vault_dir="$VAULT_PROJETS/$repo_name"
  if [[ -d "$vault_dir" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$vault_dir"
      ok "Vault : $vault_dir supprimé"
    else
      warn "Vault Obsidian : suppression de $vault_dir ? (o/N) "
      read -r answer
      if [[ "${answer,,}" == "o" ]]; then
        rm -rf "$vault_dir"
        ok "Vault : $vault_dir supprimé"
      else
        info "Vault : conservé"
      fi
    fi
  else
    info "Vault : aucun dossier trouvé pour '$repo_name'"
  fi

  local legacy_vault_dir="$VAULT_PROJETS/$local_name"
  if [[ "$local_name" != "$repo_name" && -d "$legacy_vault_dir" ]]; then
    if [[ "$AUTO_YES" == "true" ]]; then
      rm -rf "$legacy_vault_dir"
      ok "Vault : ancien dossier local $legacy_vault_dir supprimé"
    else
      warn "Vault Obsidian : suppression de l'ancien dossier local $legacy_vault_dir ? (o/N) "
      read -r answer
      if [[ "${answer,,}" == "o" ]]; then
        rm -rf "$legacy_vault_dir"
        ok "Vault : ancien dossier local supprimé"
      else
        info "Vault : ancien dossier local conservé"
      fi
    fi
  fi

  echo -e "  ${GREEN}✓ $repo_label${NC}"
}

# ── main ──────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--yes] <repo-path> [<repo-path> ...]"
  echo ""
  echo "  --yes   Supprime graphify-out/ et le vault sans confirmation (mode non-interactif)."
  echo ""
  echo "Exclut un repo de graphify (hooks + .graphifyignore),"
  echo "supprime son wing mempalace, et nettoie le vault Obsidian."
  exit 1
fi

for path in "$@"; do
  exclude_repo "$path"
done

