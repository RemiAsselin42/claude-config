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
  # --- Windows: install via winget. The PreToolUse hook (`rtk hook claude`)
  # ships via the repo's settings.json copied by install.sh — verified working
  # on Windows. rtk init runs --hook-only as an idempotent safety net; no
  # RTK.md is generated (the CLAUDE.md template documents the meta commands). ---
  if ! command -v rtk &>/dev/null; then
    log "Installing RTK via winget..."
    run_cmd winget install rtk-ai.rtk --accept-package-agreements --accept-source-agreements || true
  else
    log "RTK already installed: $(rtk --version)"
  fi
  # Call rtk.exe directly via its winget path (PATH not refreshed in current session)
  if [[ "$SETUP_RTK_INIT" == "true" ]]; then
    log "Activating CLAUDE.md mode (native Windows)..."
  fi
  WINGET_PKGS="$(cygpath -u "${LOCALAPPDATA}/Microsoft/WinGet/Packages" 2>/dev/null || true)"
  RTK_EXE="$(compgen -G "$WINGET_PKGS/rtk-ai.rtk_*/rtk.exe" 2>/dev/null | head -1)"
  if [[ -x "$RTK_EXE" ]]; then
    # Create a bash wrapper in ~/.local/bin so rtk is accessible
    # from Claude Code's bash shell (Windows PATH is not refreshed in session).
    mkdir -p "$TOOL_BIN_DIR"
    RTK_EXE_WIN="$(cygpath -w "$RTK_EXE")"
    cat > "$TOOL_BIN_DIR/rtk" << WRAPPER
#!/usr/bin/env bash
exec "$RTK_EXE_WIN" "\$@"
WRAPPER
    chmod +x "$TOOL_BIN_DIR/rtk"
    log "  Bash wrapper created: $TOOL_BIN_DIR/rtk → $RTK_EXE_WIN"
    _persist_tool_path_if_allowed

    if [[ "$SETUP_RTK_INIT" == "true" ]]; then
      run_cmd "$RTK_EXE" telemetry disable || true
      run_cmd "$RTK_EXE" init -g --hook-only --auto-patch
    else
      log "  RTK activation deferred."
    fi
  else
    echo "WARNING: rtk.exe not found in $WINGET_PKGS"
    echo "Run 'rtk init -g' manually from a new terminal."
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
