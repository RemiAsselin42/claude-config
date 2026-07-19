#!/usr/bin/env bash
# Installs RTK and activates it for Claude Code via rtk init -g.
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
    answer="y"
  else
    printf "Add %s to persistent PATH (~/.bashrc, ~/.bash_profile, ~/.profile) [Y/n]? " "$TOOL_BIN_DIR"
    read -r answer
  fi

  if [[ -n "$answer" && "${answer,,}" != "o" && "${answer,,}" != "oui" && "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
    echo "  Persistent PATH not modified."
    return 0
  fi

  _write_tool_path_to_profiles
  echo "  PATH $TOOL_BIN_DIR added to shell profiles"
}

mkdir -p "$TOOL_BIN_DIR"
_add_tool_paths_to_current_session

if _is_windows; then
  # --- Windows: winget when resolvable from Git Bash, GitHub release fallback
  # otherwise (App Execution Alias often breaks winget in Git Bash). The
  # PreToolUse hook (`rtk hook claude`) ships via the repo's settings.json
  # copied by install.sh; rtk init runs --hook-only as an idempotent safety net. ---
  RTK_EXE=""
  if command -v rtk &>/dev/null; then
    log "RTK already installed: $(rtk --version)"
    RTK_EXE="$(command -v rtk)"
  else
    if command -v winget &>/dev/null; then
      log "Installing RTK via winget..."
      run_cmd winget install rtk-ai.rtk --accept-package-agreements --accept-source-agreements || true
      # Verify by resolving the installed exe — an empty glob means the install
      # failed (errors are swallowed above in quiet mode).
      WINGET_PKGS="$(cygpath -u "${LOCALAPPDATA}/Microsoft/WinGet/Packages" 2>/dev/null || true)"
      RTK_EXE="$(compgen -G "$WINGET_PKGS/rtk-ai.rtk_*/rtk.exe" 2>/dev/null | head -1)"
      if [[ -x "$RTK_EXE" ]]; then
        # Bash wrapper in ~/.local/bin so rtk resolves from Claude Code's bash
        # shell (Windows PATH is not refreshed in the current session).
        RTK_EXE_WIN="$(cygpath -w "$RTK_EXE")"
        cat > "$TOOL_BIN_DIR/rtk" << WRAPPER
#!/usr/bin/env bash
exec "$RTK_EXE_WIN" "\$@"
WRAPPER
        chmod +x "$TOOL_BIN_DIR/rtk"
        log "  Bash wrapper created: $TOOL_BIN_DIR/rtk → $RTK_EXE_WIN"
      else
        log "  winget install failed — falling back to GitHub release."
        RTK_EXE=""
      fi
    else
      log "winget not found in this shell — falling back to GitHub release."
    fi
    if [[ ! -x "$RTK_EXE" ]]; then
      log "Downloading RTK from GitHub releases..."
      RTK_ZIP="$(mktemp)"
      if curl -fsSL -o "$RTK_ZIP" \
           "https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.zip" \
         && unzip -o -q "$RTK_ZIP" rtk.exe -d "$TOOL_BIN_DIR"; then
        RTK_EXE="$TOOL_BIN_DIR/rtk.exe"
        log "  RTK downloaded: $RTK_EXE"
      fi
      rm -f "$RTK_ZIP"
    fi
  fi

  if [[ -x "$RTK_EXE" ]]; then
    _persist_tool_path_if_allowed
    if [[ "$SETUP_RTK_INIT" == "true" ]]; then
      log "Activating Claude Code hook..."
      run_cmd "$RTK_EXE" telemetry disable || true
      run_cmd "$RTK_EXE" init -g --hook-only --auto-patch
    else
      log "  RTK activation deferred."
    fi
  else
    echo "WARNING: RTK install failed (winget unavailable or failed, GitHub download failed)."
    echo "Install App Installer (winget) via Microsoft Store, or download rtk.exe manually:"
    echo "  https://github.com/rtk-ai/rtk/releases → $TOOL_BIN_DIR/rtk.exe"
    exit 1
  fi
else
  # --- Linux / macOS: install + bash hook ---
  if command -v rtk &>/dev/null; then
    log "RTK already installed: $(rtk --version)"
  else
    log "Installing RTK..."
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
    log "Activating Claude Code hook..."
    run_cmd rtk telemetry disable || true
    run_cmd rtk init -g --hook-only --auto-patch
  else
    log "RTK activation deferred."
  fi
fi

if [[ "$SETUP_RTK_QUIET" != "true" ]]; then
  echo ""
  echo "=== Done ==="
  echo "Restart Claude Code for changes to take effect."
  echo "Verify with: rtk gain"
fi
