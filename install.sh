#!/usr/bin/env bash
# Usage: install.sh [-y|--yes] [-v|--verbose]
#   -y, --yes      Accepte les valeurs par défaut pour chaque repo.
#   -v, --verbose  Affiche les sorties détaillées des installateurs.
set -euo pipefail

AUTO_YES=false
VERBOSE="${VERBOSE:-false}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=true
      ;;
    -v|--verbose)
      VERBOSE=true
      ;;
    -h|--help)
      sed -n '2,4p' "$0"
      exit 0
      ;;
    *)
      echo "Option inconnue : $1" >&2
      sed -n '2,4p' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
RED=$'\033[1;31m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$REPO_DIR/vault"
source "$REPO_DIR/scripts/repo-identity.sh"
UV_INSTALL_DIR="${UV_INSTALL_DIR:-$TOOL_BIN_DIR}"
PATH_PERSIST_DECIDED=false
PATH_PERSIST_APPROVED=false

_run_quiet() {
  if [[ "$VERBOSE" == "true" ]]; then
    "$@"
    return
  fi

  local output=""
  output="$(mktemp)"
  if "$@" >"$output" 2>&1; then
    rm -f "$output"
    return 0
  fi

  echo "${YELLOW}Commande échouée : $*${RESET}"
  sed 's/^/  /' "$output"
  rm -f "$output"
  return 1
}

_step() {
  [[ "$VERBOSE" == "true" ]] && echo "${BOLD}${CYAN}$*${RESET}"
  return 0
}

_detail() {
  [[ "$VERBOSE" == "true" ]] && echo "$*"
  return 0
}

_tool_path_persistence_needed() {
  local profile
  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    _profile_has_tool_path "$profile" || return 0
  done
  return 1
}

_ask_for_tool_path_persistence() {
  [[ "$PATH_PERSIST_DECIDED" == "true" ]] && return 0
  PATH_PERSIST_DECIDED=true

  if ! _tool_path_persistence_needed; then
    PATH_PERSIST_APPROVED=true
    return 0
  fi

  if [[ "$AUTO_YES" == "true" ]]; then
    PATH_PERSIST_APPROVED=true
    return 0
  fi

  local answer
  echo "${BOLD}${CYAN}PATH shell :${RESET} $TOOL_BIN_DIR"
  echo "${DIM}Nécessaire pour retrouver uv/rtk depuis les prochains terminaux Git Bash.${RESET}"
  printf "Ajouter ce dossier au PATH persistant (~/.bashrc, ~/.bash_profile, ~/.profile) ${CYAN}[O/n]${RESET} ? "
  read -r answer
  if [[ -z "$answer" || "${answer,,}" == "o" || "${answer,,}" == "oui" || "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
    PATH_PERSIST_APPROVED=true
  else
    PATH_PERSIST_APPROVED=false
    echo "  ${YELLOW}PATH persistant non modifié — PATH actif seulement pour cette exécution.${RESET}"
  fi
}

_persist_tool_path_if_approved() {
  [[ "$PATH_PERSIST_APPROVED" == "true" ]] || return 0

  # Collect profiles that need updating before writing (for feedback).
  local profile
  local -a to_update=()
  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    _profile_has_tool_path "$profile" || to_update+=("$profile")
  done

  [[ ${#to_update[@]} -eq 0 ]] && return 0

  _write_tool_path_to_profiles
  for profile in "${to_update[@]}"; do
    echo "  ${GREEN}✓ PATH persistant : $(basename "$profile")${RESET}"
  done
}

_ensure_uv() {
  export UV_INSTALL_DIR
  mkdir -p "$UV_INSTALL_DIR"
  _add_tool_paths_to_current_session
  _ask_for_tool_path_persistence

  if command -v uv >/dev/null; then
    _persist_tool_path_if_approved
    return 0
  fi

  echo "${BOLD}${CYAN}Installation de uv...${RESET}"
  command -v curl >/dev/null || { echo "${RED}curl requis pour installer uv.${RESET}"; exit 1; }

  if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    _add_tool_paths_to_current_session
    _persist_tool_path_if_approved
  else
    echo "${RED}Installation de uv échouée.${RESET}"
    exit 1
  fi

  command -v uv >/dev/null || {
    echo "${RED}uv installé mais introuvable dans le PATH courant.${RESET}"
    echo "  Ajouter à ton shell : export PATH=\"$UV_INSTALL_DIR:\$PATH\""
    exit 1
  }

  echo "  ${GREEN}✓ uv installé : $(command -v uv)${RESET}"
}

_find_python() {
  local cmd
  for cmd in python3 python py; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    # Test plus robuste : vérifier que Python répond avec une version valide
    if "$cmd" --version >/dev/null 2>&1 && "$cmd" -c 'import sys' >/dev/null 2>&1; then
      printf '%s\n' "$cmd"
      return 0
    fi
  done
  return 1
}

_ensure_chromadb() {
  local python_cmd
  python_cmd="$(_find_python || true)"

  if [[ -z "$python_cmd" ]]; then
    echo "  ${YELLOW}⚠ Python introuvable — chromadb non installé, nettoyage MemPalace limité.${RESET}"
    return 0
  fi

  if "$python_cmd" -c 'import chromadb' >/dev/null 2>&1; then
    echo "  ${GREEN}✓ chromadb${RESET}"
    return 0
  fi

  _detail "  Installation de chromadb dans le Python courant..."
  # Utiliser 'python -m pip install' plutôt que 'uv pip install --python' pour éviter
  # les problèmes de validation d'environnement sur Windows
  if _run_quiet "$python_cmd" -m pip install chromadb; then
    "$python_cmd" -c 'import chromadb' >/dev/null 2>&1 || {
      echo "  ${YELLOW}⚠ chromadb installé mais non importable par $python_cmd.${RESET}"
      return 0
    }
    echo "  ${GREEN}✓ chromadb installé${RESET}"
  else
    echo "  ${YELLOW}⚠ chromadb non installé — le nettoyage MemPalace utilisera uv en fallback si possible.${RESET}"
  fi
}

_prepare_dependencies() {
  echo "${BOLD}${CYAN}Préparation des dépendances...${RESET}"
  mkdir -p "$TOOL_BIN_DIR"
  _add_tool_paths_to_current_session

  command -v node >/dev/null || { echo "${RED}Node.js requis (https://nodejs.org)${RESET}"; exit 1; }
  _ensure_uv

  _run_quiet uv tool install graphifyy --upgrade
  command -v graphify >/dev/null || { echo "${RED}Graphify installé mais introuvable dans le PATH courant.${RESET}"; exit 1; }
  echo "  ${GREEN}✓ Graphify${RESET}"

  _run_quiet uv tool install mempalace --upgrade
  command -v mempalace >/dev/null || { echo "${RED}MemPalace installé mais introuvable dans le PATH courant.${RESET}"; exit 1; }
  echo "  ${GREEN}✓ MemPalace${RESET}"

  _ensure_chromadb

  if command -v rtk >/dev/null; then
    echo "  ${GREEN}✓ RTK${RESET}"
  elif SETUP_RTK_INIT=false SETUP_RTK_MANAGE_PATH=false SETUP_RTK_QUIET=true bash "$REPO_DIR/scripts/setup-rtk.sh"; then
    echo "  ${GREEN}✓ RTK prêt${RESET}"
  else
    echo "  ${YELLOW}⚠ RTK : installation/préparation échouée, tentative d'activation plus tard.${RESET}"
  fi
}

# --- Charger les vars machine-specific ---
if [[ ! -f "$REPO_DIR/env.local" ]]; then
  echo "${RED}Copier env.local.template en env.local et remplir les valeurs.${RESET}"
  echo "  cp env.local.template env.local"
  exit 1
fi
source "$REPO_DIR/env.local"

# --- Vérifier les prérequis ---
_prepare_dependencies

# --- Nettoyer les symlinks cassés dans ~/.claude ---
echo "${BOLD}${CYAN}Configuration Claude...${RESET}"
_step "Nettoyage des symlinks cassés..."
for dir in agents commands scripts hooks; do
  target="$CLAUDE_DIR/$dir"
  if [[ -L "$target" && ! -e "$target" ]]; then
    rm -f "$target"
    _detail "  ${YELLOW}⚠ Symlink cassé supprimé : $target${RESET}"
  fi
done

# --- Copier agents, commands et scripts ---
_step "Copie agents, commands et scripts..."
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/hooks"
# Utilise nullglob pour éviter l'échec du glob si un dossier source est vide
(
  shopt -s nullglob
  for dir in agents commands scripts hooks; do
    files=("$REPO_DIR/$dir/"*)
    if [[ ${#files[@]} -gt 0 ]]; then
      cp -r "${files[@]}" "$CLAUDE_DIR/$dir/"
    fi
  done
)
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true
_detail "  ${GREEN}✓ Fichiers Claude copiés${RESET}"

# --- Générer session-stop.sh avec chemin absolu du repo ---
_step "Génération de session-stop.sh..."
SYNC_SCRIPT="$REPO_DIR/scripts/sync-graph-to-vault.sh"
cat > "$CLAUDE_DIR/scripts/session-stop.sh" << 'STOPSCRIPT'
#!/usr/bin/env bash
# Généré par install.sh — NE PAS MODIFIER MANUELLEMENT.
# Pour re-générer : relancer install.sh depuis le repo claude-config.
# Hook Stop Claude Code : met à jour graphify et sync le vault si dans un repo graphifié.
[[ -d "graphify-out" ]] || exit 0
graphify update . 2>/dev/null || true
STOPSCRIPT
echo "bash \"$SYNC_SCRIPT\"" >> "$CLAUDE_DIR/scripts/session-stop.sh"
cat >> "$CLAUDE_DIR/scripts/session-stop.sh" << STOPSCRIPT2
if git -C "$REPO_DIR" status --porcelain vault/ | grep -q .; then
  git -C "$REPO_DIR" add vault/
  git -C "$REPO_DIR" commit -m "graphify: sync vault — \$(date +%Y-%m-%d)"
  git -C "$REPO_DIR" push origin master 2>/dev/null || true
fi
STOPSCRIPT2
chmod +x "$CLAUDE_DIR/scripts/session-stop.sh"
_detail "  ${GREEN}✓ session-stop.sh généré${RESET}"

# --- Initialiser MemPalace ---
_step "Initialisation de MemPalace..."
export PYTHONUTF8=1
if [[ -d "$HOME/.mempalace" ]]; then
  _detail "  ${DIM}Déjà initialisé.${RESET}"
else
  mkdir -p "$HOME/.mempalace"
  mempalace init --yes ~/.mempalace
  echo "  ${GREEN}✓ MemPalace initialisé${RESET}"
  if [[ -d "$CLAUDE_DIR/projects" ]]; then
    _detail "  Reconstruction de l'index depuis les transcripts..."
    mempalace mine "$CLAUDE_DIR/projects/" --mode convos || true
    echo "  ${GREEN}✓ Index MemPalace reconstruit${RESET}"
  else
    echo "  ${DIM}Aucun transcript — index vide (normal sur un nouveau PC).${RESET}"
  fi
fi

# --- Copier CLAUDE.md global (substitution du chemin vault) ---
_step "Copie CLAUDE.md global..."
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.backup"
  claude_backup_created=true
else
  claude_backup_created=false
fi
sed "s|\${VAULT_DIR}|$VAULT_DIR|g" "$REPO_DIR/CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
if [[ "$claude_backup_created" == "true" ]]; then
  _detail "  ${GREEN}✓ CLAUDE.md copié (backup créé)${RESET}"
else
  _detail "  ${GREEN}✓ CLAUDE.md copié${RESET}"
fi

# --- Préserver/restaurer caveman mode ---
# Copy defaults if not present on this machine (new install)
if [[ ! -f "$CLAUDE_DIR/caveman.enabled" && -f "$REPO_DIR/defaults/caveman.enabled" ]]; then
  cp "$REPO_DIR/defaults/caveman.enabled" "$CLAUDE_DIR/caveman.enabled"
  _detail "  ${DIM}caveman.enabled restauré depuis defaults${RESET}"
fi
if [[ ! -f "$CLAUDE_DIR/caveman.level" && -f "$REPO_DIR/defaults/caveman.level" ]]; then
  cp "$REPO_DIR/defaults/caveman.level" "$CLAUDE_DIR/caveman.level"
  _detail "  ${DIM}caveman.level restauré depuis defaults${RESET}"
fi
# Always inject if flag present (block goes to top of CLAUDE.md)
if [[ -f "$CLAUDE_DIR/caveman.enabled" ]]; then
  bash "$CLAUDE_DIR/scripts/caveman-toggle.sh" inject 2>/dev/null || true
  _detail "  ${GREEN}✓ Caveman mode injecté ($(cat "$CLAUDE_DIR/caveman.level" 2>/dev/null || echo full))${RESET}"
fi

# --- Générer claude.json depuis le template ---
_step "Génération de claude.json..."
sed "s|\${FIGMA_API_KEY}|${FIGMA_API_KEY}|g" \
  "$REPO_DIR/claude.json.template" > "$CLAUDE_DIR/claude.json"

# --- Copier settings.json ---
_step "Copie settings.json..."
cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# --- Installer RTK (après CLAUDE.md et settings.json — rtk init -g peut les modifier) ---
_step "Activation de RTK..."
if SETUP_RTK_MANAGE_PATH=false SETUP_RTK_QUIET=true bash "$CLAUDE_DIR/scripts/setup-rtk.sh"; then
  _detail "  ${GREEN}✓ RTK activé${RESET}"
else
  echo "  ${YELLOW}⚠ RTK : exécuter manuellement : bash ~/.claude/scripts/setup-rtk.sh${RESET}"
fi
echo "  ${GREEN}✓ Configuration Claude mise à jour${RESET}"

# --- Vault Obsidian ---
_detail "${BOLD}${CYAN}Vault Obsidian${RESET} ${DIM}$VAULT_DIR${RESET}"

# --- Setup Graphify dans tous les repos git ---
echo ""
if [[ "$VERBOSE" == "true" ]]; then
  echo "${BOLD}${CYAN}Recherche des repos git...${RESET}"
else
  echo "${BOLD}${CYAN}Repos git${RESET}"
fi

REPOS_FOUND=()
PARENT_DIR="$(dirname "$REPO_DIR")"

# Scan mono-niveau : seuls les repos git directement sous $PARENT_DIR sont détectés.
# Les sous-dossiers imbriqués (monorepos, workspaces) ne sont pas parcourus.
for dir in "$PARENT_DIR"/*/; do
  [[ -d "$dir/.git" ]] || continue
  repo_path="${dir%/}"
  [[ "$repo_path" == "$REPO_DIR" ]] && continue
  REPOS_FOUND+=("$repo_path")
done

# Retourne 0 si CLAUDE.md est versionné (git-tracked) dans le repo
_is_claude_md_tracked() {
  git -C "$1" ls-files --error-unmatch "CLAUDE.md" &>/dev/null
}

_setup_repo_gitignore() {
  local repo="$1"
  local gitignore_claude_md="${2:-false}"
  local gitignore="$repo/.gitignore"

  # Supprimer les anciens blocs graphify fragmentés ou avec commentaire obsolète
  if grep -qF "graphify-out/" "$gitignore" 2>/dev/null; then
    local tmp
    tmp=$(grep -v -E '^graphify-out/|^# Graphify' "$gitignore")
    printf '%s\n' "$tmp" > "$gitignore"
  fi

  printf '\n# Graphify — artefacts générés localement\ngraphify-out/\n' >> "$gitignore"
  _detail "  ${GREEN}✓ .gitignore : bloc graphify mis à jour${RESET}"

  if [[ "$gitignore_claude_md" == "true" ]] && ! grep -qF "CLAUDE.md" "$gitignore" 2>/dev/null; then
    printf '\n# Claude Code — config locale non-versionnée\nCLAUDE.md\nmempalace.yaml\n' >> "$gitignore"
    _detail "  ${GREEN}✓ .gitignore : CLAUDE.md + mempalace.yaml ajoutés (config locale)${RESET}"
  elif ! grep -qF "mempalace.yaml" "$gitignore" 2>/dev/null; then
    printf '\nmempalace.yaml\n' >> "$gitignore"
    _detail "  ${GREEN}✓ .gitignore : mempalace.yaml ajouté${RESET}"
  fi
}

_generate_mempalace_yaml() {
  local repo="$1"
  local repo_name="$(canonical_repo_name "$repo")"
  local yaml_file="$repo/mempalace.yaml"
  if [[ -f "$yaml_file" ]]; then
    [[ "$VERBOSE" == "true" ]] && echo "  ${DIM}mempalace.yaml déjà présent — conservé.${RESET}" || echo "  ${DIM}· mempalace.yaml : présent${RESET}"
    return
  fi
  cat > "$yaml_file" << YAML
wing: $repo_name
exclude:
  - graphify-out/
  - .git/
  - node_modules/
YAML
  [[ "$VERBOSE" == "true" ]] && echo "  ${GREEN}✓ mempalace.yaml généré (wing: $repo_name)${RESET}" || echo "  ${DIM}· mempalace.yaml : généré${RESET}"
}

_setup_repo_graphify() {
  local repo="$1"
  local repo_name="$(canonical_repo_name "$repo")"
  local obsidian_dir="$VAULT_DIR/Projets/$repo_name"
  mkdir -p "$obsidian_dir"

  # CLAUDE.md versionné → setup complet ; sinon → générer + gitignorer
  if _is_claude_md_tracked "$repo"; then
    (
      cd "$repo"
      _run_quiet graphify claude install
      _detail "  ${GREEN}✓ claude install${RESET}"
      _run_quiet graphify hook install
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _setup_repo_gitignore "$repo" false
    [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· CLAUDE.md : versionné — hooks installés${RESET}" || true
  else
    # Générer CLAUDE.md depuis le template avec le nom du repo substitué
    sed "s|{{REPO_NAME}}|$repo_name|g" "$REPO_DIR/templates/CLAUDE.project.md" > "$repo/CLAUDE.md"
    _detail "  ${GREEN}✓ CLAUDE.md généré depuis template (local)${RESET}"
    (
      cd "$repo"
      _run_quiet graphify hook install
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _setup_repo_gitignore "$repo" true
    [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· CLAUDE.md : généré (local) — hooks installés${RESET}" || true
  fi

  (
    cd "$repo"
    if [[ -f "graphify-out/GRAPH_REPORT.md" ]]; then
      [[ "$VERBOSE" == "true" ]] && echo "  ${DIM}(graphe existant conservé)${RESET}" || echo "  ${DIM}· graphe : conservé${RESET}"
    else
      _detail "  Génération du graphe..."
      if [[ "$VERBOSE" == "true" ]]; then
        graphify update . && echo "  ${GREEN}✓ graphe généré${RESET}" || echo "  ${YELLOW}⚠ graphe : erreur post-traitement (non-bloquant)${RESET}"
      else
        graphify update . >/dev/null 2>&1 && echo "  ${DIM}· graphe : généré${RESET}" || echo "  ${DIM}· graphe : erreur post-traitement (non-bloquant)${RESET}"
      fi
    fi
  )

  # Sync vault : GRAPH_REPORT.md + FILE_TREE.md + graph.canvas
  (cd "$repo" && bash "$REPO_DIR/scripts/sync-graph-to-vault.sh")
  [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· vault : synchronisé${RESET}" || true

  # Hook post-commit pour sync vault
  local hook_file="$repo/.git/hooks/post-commit"
  local hook_line="bash \"$REPO_DIR/scripts/sync-graph-to-vault.sh\""
  if [[ -f "$hook_file" ]]; then
    grep -qF "sync-graph-to-vault" "$hook_file" || echo "$hook_line" >> "$hook_file"
  else
    printf '#!/usr/bin/env bash\n%s\n' "$hook_line" > "$hook_file"
    chmod +x "$hook_file"
  fi
  _detail "  ${GREEN}✓ hook sync vault${RESET}"

  _generate_mempalace_yaml "$repo"
}

if [[ ${#REPOS_FOUND[@]} -eq 0 ]]; then
  echo "${DIM}Aucun repo git trouvé (hors claude-config).${RESET}"
else
  echo "${BOLD}Repos détectés — choisir lesquels indexer (graphify + mempalace + vault) :${RESET}"
  echo ""
  for repo in "${REPOS_FOUND[@]}"; do
    repo_name="$(canonical_repo_name "$repo")"
    local_name="$(basename "$repo")"
    repo_label="$repo_name"
    [[ "$local_name" != "$repo_name" ]] && repo_label="$local_name → $repo_name"
    if [[ -f "$repo/.graphifyignore" ]]; then
      state=" ${YELLOW}[exclu]${RESET}"
    else
      state=" ${GREEN}[indexé]${RESET}"
    fi
    echo "  $repo_label$state"
  done
  echo ""

  for repo in "${REPOS_FOUND[@]}"; do
    repo_name="$(canonical_repo_name "$repo")"
    local_name="$(basename "$repo")"
    repo_label="$repo_name"
    [[ "$local_name" != "$repo_name" ]] && repo_label="$local_name → $repo_name"
    if [[ -f "$repo/.graphifyignore" ]]; then
      current="${DIM} (actuellement exclu)${RESET}"
      default_hint="${CYAN}[o/N]${RESET}"
    else
      current="${DIM} (actuellement indexé)${RESET}"
      default_hint="${CYAN}[O/n]${RESET}"
    fi

    if [[ "$AUTO_YES" == "true" ]]; then
      [[ -f "$repo/.graphifyignore" ]] && answer="n" || answer="o"
      printf "Indexer %b%-40s%b%b → %s (défaut)\n" "$BOLD" "$repo_label" "$RESET" "$current" "$answer"
    else
      printf "Indexer %b%-40s%b%b %b ? " "$BOLD" "$repo_label" "$RESET" "$current" "$default_hint"
      read -r answer
      # Défaut selon l'état actuel : exclu→N, indexé→O
      if [[ -z "$answer" ]]; then
        [[ -f "$repo/.graphifyignore" ]] && answer="n" || answer="o"
      fi
    fi

    if [[ "${answer,,}" == "o" ]]; then
      # S'assurer qu'il n'est pas exclu (supprimer .graphifyignore s'il existe)
      rm -f "$repo/.graphifyignore"
      echo "${BOLD}[$repo_label]${RESET} ${YELLOW}Setup...${RESET}"
      _setup_repo_graphify "$repo"
      echo "  ${GREEN}✓ $repo_label${RESET}"
    else
      if ! bash "$REPO_DIR/scripts/exclude-from-index.sh" --yes "$repo"; then
        echo "  ${YELLOW}⚠ Exclusion de $repo_label incomplète — poursuite de l'installation.${RESET}"
      fi
    fi
  done
fi

# Graphify pour ce repo de config aussi
echo ""
echo "${BOLD}[claude-config]${RESET} Setup..."
_run_quiet graphify claude install
_detail "  ${GREEN}✓ claude install${RESET}"
_run_quiet graphify hook install
_detail "  ${GREEN}✓ hook install${RESET}"
if [[ -f "$REPO_DIR/graphify-out/GRAPH_REPORT.md" ]]; then
  _detail "  ${DIM}(graphe existant conservé)${RESET}"
else
  _detail "  Génération du graphe..."
  if [[ "$VERBOSE" == "true" ]]; then
    graphify update . && echo "  ${GREEN}✓ graphe généré${RESET}" || echo "  ${YELLOW}⚠ graphe : erreur post-traitement (non-bloquant)${RESET}"
  else
    graphify update . >/dev/null 2>&1 && echo "  ${DIM}· graphe : généré${RESET}" || echo "  ${DIM}· graphe : erreur post-traitement (non-bloquant)${RESET}"
  fi
fi
bash "$REPO_DIR/scripts/sync-graph-to-vault.sh"

# mempalace.yaml pour claude-config (vault/ exclu — notes Obsidian, pas du code)
if [[ ! -f "$REPO_DIR/mempalace.yaml" ]]; then
  cat > "$REPO_DIR/mempalace.yaml" << YAML
wing: claude-config
exclude:
  - graphify-out/
  - vault/
  - .git/
YAML
  echo "  ${GREEN}✓ mempalace.yaml généré pour claude-config${RESET}"
else
  echo "  ${DIM}mempalace.yaml déjà présent — conservé.${RESET}"
fi

# Committer le vault si des changements ont été générés
echo ""
if git -C "$REPO_DIR" status --porcelain vault/ | grep -q .; then
  git -C "$REPO_DIR" add vault/
  git -C "$REPO_DIR" commit -m "graphify: sync vault — $(date +%Y-%m-%d)"
  echo "${GREEN}✓ Vault commité dans claude-config.${RESET}"
else
  echo "${DIM}Vault déjà à jour — aucun commit nécessaire.${RESET}"
fi
git -C "$REPO_DIR" push origin master 2>/dev/null && echo "${GREEN}✓ Vault pushé.${RESET}" || echo "${YELLOW}⚠ Push échoué (pas de remote ?).${RESET}"

echo ""
echo "${GREEN}Installation terminée.${RESET}"
echo "${DIM}Relancer Claude Code pour que les changements prennent effet.${RESET}"
