#!/usr/bin/env bash
# Installe RTK et l'active pour Claude Code via rtk init -g.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-identity.sh"

SETUP_RTK_INIT="${SETUP_RTK_INIT:-true}"
SETUP_RTK_MANAGE_PATH="${SETUP_RTK_MANAGE_PATH:-true}"
SETUP_RTK_YES="${SETUP_RTK_YES:-false}"
SETUP_RTK_QUIET="${SETUP_RTK_QUIET:-false}"

log() {
  [[ "$SETUP_RTK_QUIET" == "true" ]] || echo "$*"
}

run_cmd() {
  if [[ "$SETUP_RTK_QUIET" == "true" ]]; then
    "$@" >/dev/null 2>&1
  else
    "$@"
  fi
}

log "=== RTK setup ==="

_persist_tool_path_if_allowed() {
  [[ "$SETUP_RTK_MANAGE_PATH" == "false" ]] && return 0

  local needs_update=false
  local profile
  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    _profile_has_tool_path "$profile" || needs_update=true
  done
  [[ "$needs_update" == "true" ]] || return 0

  local answer
  if [[ "$SETUP_RTK_YES" == "true" ]]; then
    answer="o"
  else
    printf "Ajouter %s au PATH persistant (~/.bashrc, ~/.bash_profile, ~/.profile) [O/n] ? " "$TOOL_BIN_DIR"
    read -r answer
  fi

  if [[ -n "$answer" && "${answer,,}" != "o" && "${answer,,}" != "oui" && "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
    echo "  PATH persistant non modifié."
    return 0
  fi

  _write_tool_path_to_profiles
  echo "  PATH $TOOL_BIN_DIR ajouté dans les profils shell"
}

mkdir -p "$TOOL_BIN_DIR"
_add_tool_paths_to_current_session

if _is_windows; then
  # --- Windows : installation via winget + mode CLAUDE.md (pas de hook bash) ---
  if ! command -v rtk &>/dev/null; then
    log "Installation de RTK via winget..."
    run_cmd winget install rtk-ai.rtk --accept-package-agreements --accept-source-agreements || true
  else
    log "RTK déjà installé : $(rtk --version)"
  fi
  # Appel direct à rtk.exe via son chemin winget (PATH non rafraîchi en session courante)
  if [[ "$SETUP_RTK_INIT" == "true" ]]; then
    log "Activation du mode CLAUDE.md (Windows natif)..."
  fi
  WINGET_PKGS="$(cygpath -u "${LOCALAPPDATA}/Microsoft/WinGet/Packages" 2>/dev/null || true)"
  RTK_EXE="$(compgen -G "$WINGET_PKGS/rtk-ai.rtk_*/rtk.exe" 2>/dev/null | head -1)"
  if [[ -x "$RTK_EXE" ]]; then
    # Créer un wrapper bash dans ~/.local/bin pour que rtk soit accessible
    # depuis le shell bash de Claude Code (le PATH Windows n'est pas rafraîchi).
    mkdir -p "$TOOL_BIN_DIR"
    RTK_EXE_WIN="$(cygpath -w "$RTK_EXE")"
    cat > "$TOOL_BIN_DIR/rtk" << WRAPPER
#!/usr/bin/env bash
exec "$RTK_EXE_WIN" "\$@"
WRAPPER
    chmod +x "$TOOL_BIN_DIR/rtk"
    log "  Wrapper bash créé : $TOOL_BIN_DIR/rtk → $RTK_EXE_WIN"
    _persist_tool_path_if_allowed

    if [[ "$SETUP_RTK_INIT" == "true" ]]; then
      run_cmd "$RTK_EXE" telemetry disable || true
      run_cmd "$RTK_EXE" init -g --claude-md
    else
      log "  Activation RTK reportée."
    fi
  else
    echo "WARNING: rtk.exe introuvable dans $WINGET_PKGS"
    echo "Lance 'rtk init -g' manuellement depuis un nouveau terminal."
    exit 1
  fi
else
  # --- Linux / macOS : installation + hook bash ---
  if command -v rtk &>/dev/null; then
    log "RTK déjà installé : $(rtk --version)"
  else
    log "Installation de RTK..."
    if command -v brew &>/dev/null; then
      run_cmd brew install rtk
    else
      if [[ "$SETUP_RTK_QUIET" == "true" ]]; then
        curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh >/dev/null 2>&1
      else
        curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
      fi
    fi
  fi
  _persist_tool_path_if_allowed
  if [[ "$SETUP_RTK_INIT" == "true" ]]; then
    log "Activation du hook Claude Code..."
    run_cmd rtk telemetry disable || true
    run_cmd rtk init -g
  else
    log "Activation RTK reportée."
  fi
fi

if [[ "$SETUP_RTK_QUIET" != "true" ]]; then
  echo ""
  echo "=== Done ==="
  echo "Redémarre Claude Code pour que les changements prennent effet."
  echo "Vérifie avec : rtk gain"
fi
