#!/usr/bin/env bash
# Usage: install.sh [-y|--yes] [-v|--verbose]
#   -y, --yes      Accept defaults for each repo.
#   -v, --verbose  Show verbose output from installers.
set -euo pipefail

# Neutralize VS Code's JS debug auto-attach: it injects a bootloader through
# NODE_OPTIONS into every node child process, which slows npm/npx steps
# ("Waiting for the debugger to disconnect") and can leave zombie node
# processes holding npm locks, deadlocking quiet installs.
unset NODE_OPTIONS VSCODE_INSPECTOR_OPTIONS

AUTO_YES=false
# Exported: child scripts (exclude-from-index.sh) gate their own detail lines on it.
export VERBOSE="${VERBOSE:-false}"
ORIG_ARGS=("$@")
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
      echo "Unknown option: $1" >&2
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

# --- Sync from upstream FIRST so the rest of the script runs the latest version ---
# If the sync brings changes, re-exec the updated install.sh and abandon this run.
# CLAUDE_CONFIG_SYNCED guards against re-exec loops.
if [[ "${CLAUDE_CONFIG_SYNCED:-}" != "1" ]]; then
  # Auto-add the upstream remote on private forks (origin = claude-config-private)
  if ! git -C "$REPO_DIR" remote get-url upstream &>/dev/null; then
    _origin_url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)"
    if [[ "$_origin_url" == *claude-config-private* ]]; then
      git -C "$REPO_DIR" remote add upstream "${_origin_url/claude-config-private/claude-config}"
      echo "  ${GREEN}✓ upstream remote added${RESET}"
    fi
    unset _origin_url
  fi
  if git -C "$REPO_DIR" remote get-url upstream &>/dev/null; then
    echo "${BOLD}${CYAN}Syncing from upstream...${RESET}"
    _head_before="$(git -C "$REPO_DIR" rev-parse HEAD)"
    bash "$REPO_DIR/scripts/sync-upstream.sh" --force
    _head_after="$(git -C "$REPO_DIR" rev-parse HEAD)"
    if [[ "$_head_before" != "$_head_after" ]]; then
      echo "  ${YELLOW}Config updated from upstream — restarting install.sh with the new version...${RESET}"
      export CLAUDE_CONFIG_SYNCED=1
      exec bash "$REPO_DIR/install.sh" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
    fi
    echo "  ${GREEN}✓ upstream synced (no changes)${RESET}"
    unset _head_before _head_after
  fi
fi

_run_quiet() {
  if [[ "$VERBOSE" == "true" ]]; then
    "$@"
    return
  fi

  local output
  output="$(mktemp)"
  # stdin is closed so a hidden interactive prompt fails fast (and gets its
  # captured output printed below) instead of hanging the install silently.
  if "$@" >"$output" 2>&1 </dev/null; then
    rm -f "$output"
    return 0
  fi

  echo "${YELLOW}Command failed: $*${RESET}"
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

# Steady-state confirmations. Verbose prints one line each; otherwise they are
# queued and _ok_flush collapses the whole section into a single line — a
# re-run on an already-configured machine has nothing new to say per item.
OK_ITEMS=()
_ok() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "  ${GREEN}✓ $*${RESET}"
  else
    OK_ITEMS+=("$*")
  fi
  return 0
}

_ok_flush() {
  if [[ "$VERBOSE" != "true" && ${#OK_ITEMS[@]} -gt 0 ]]; then
    local joined
    printf -v joined '%s, ' "${OK_ITEMS[@]}"
    echo "  ${GREEN}✓${RESET} ${DIM}${joined%, }${RESET}"
  fi
  OK_ITEMS=()
  return 0
}

# Accepts y/yes/o/oui/true/1, case-insensitive. Empty string is NOT a yes —
# callers decide their own default before calling. true/1 are here for env.local
# toggles, which read as booleans rather than as answers to a prompt.
_is_yes() {
  local a="${1,,}"
  [[ "$a" == "y" || "$a" == "yes" || "$a" == "o" || "$a" == "oui" || "$a" == "true" || "$a" == "1" ]]
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
  echo "${BOLD}${CYAN}Shell PATH:${RESET} $TOOL_BIN_DIR"
  echo "${DIM}Required to find uv/rtk from future Git Bash terminals.${RESET}"
  printf "Add this directory to persistent PATH (~/.bashrc, ~/.bash_profile, ~/.profile) ${CYAN}[Y/n]${RESET}? "
  read -r answer
  if [[ -z "$answer" ]] || _is_yes "$answer"; then
    PATH_PERSIST_APPROVED=true
  else
    PATH_PERSIST_APPROVED=false
    echo "  ${YELLOW}Persistent PATH not modified — active only for this session.${RESET}"
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
    echo "  ${GREEN}✓ Persistent PATH: $(basename "$profile")${RESET}"
  done
}

# npm's global bin is not on PATH by default on Windows: `npm install -g` lands
# CLIs in %APPDATA%\npm, which neither the user nor the machine PATH contains.
# Every globally installed tool is then unreachable — context-mode's settings.json
# hooks silently no-op behind `|| true`, and its MCP server can never start.
_ensure_npm_bin_on_path() {
  local native session
  native="$(_npm_global_bin)" || return 0
  if _is_windows; then
    session="$(cygpath -u "$native" 2>/dev/null || printf '%s' "$native")"
  else
    session="$native"
  fi
  [[ -d "$session" ]] || return 0
  [[ ":$PATH:" == *":$session:"* ]] || export PATH="$session:$PATH"

  [[ "$PATH_PERSIST_APPROVED" == "true" ]] || return 0
  _write_tool_path_to_profiles "$session" "npm global bin"
  # The Windows PATH is the one Claude Code's own child processes inherit.
  if [[ -n "$(_ensure_windows_user_path "$native")" ]]; then
    _ok "npm global bin on user PATH"
  elif _is_windows; then
    echo "  ${YELLOW}⚠ npm global bin missing from the Windows user PATH — MCP servers will fail with -32000.${RESET}"
    echo "  ${YELLOW}  Add it manually: Settings > Environment Variables > Path > ${native}${RESET}"
  fi
  return 0
}

_ensure_uv() {
  export UV_INSTALL_DIR
  # Cache and tool dirs may sit on different filesystems (common on Windows);
  # copy mode avoids uv's hardlink-fallback warning.
  export UV_LINK_MODE=copy
  mkdir -p "$UV_INSTALL_DIR"
  _add_tool_paths_to_current_session
  _ask_for_tool_path_persistence

  if command -v uv >/dev/null; then
    _persist_tool_path_if_approved
    return 0
  fi

  echo "${BOLD}${CYAN}Installing uv...${RESET}"
  command -v curl >/dev/null || { echo "${RED}curl is required to install uv.${RESET}"; exit 1; }

  if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    _add_tool_paths_to_current_session
    _persist_tool_path_if_approved
  else
    echo "${RED}uv installation failed.${RESET}"
    exit 1
  fi

  command -v uv >/dev/null || {
    echo "${RED}uv installed but not found in current PATH.${RESET}"
    echo "  Add to your shell: export PATH=\"$UV_INSTALL_DIR:\$PATH\""
    exit 1
  }

  echo "  ${GREEN}✓ uv installed: $(command -v uv)${RESET}"
}

_find_python() {
  local cmd
  for cmd in python3 python py; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    # More robust check: verify Python responds with a valid version
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
    echo "  ${YELLOW}⚠ Python not found — chromadb not installed, MemPalace cleanup limited.${RESET}"
    return 0
  fi

  if "$python_cmd" -c 'import chromadb' >/dev/null 2>&1; then
    _ok "chromadb"
    return 0
  fi

  _detail "  Installing chromadb into current Python..."
  # Use 'python -m pip install' rather than 'uv pip install --python' to avoid
  # environment validation issues on Windows
  # -q + --no-warn-script-location: chromadb is only needed as an importable
  # library; its console scripts (chroma.exe, uvicorn.exe, ...) are unused.
  if _run_quiet "$python_cmd" -m pip install -q --no-warn-script-location chromadb; then
    "$python_cmd" -c 'import chromadb' >/dev/null 2>&1 || {
      echo "  ${YELLOW}⚠ chromadb installed but not importable by $python_cmd.${RESET}"
      return 0
    }
    _ok "chromadb installed"
  else
    echo "  ${YELLOW}⚠ chromadb not installed — MemPalace cleanup will fall back to uv if available.${RESET}"
  fi
}

# --- MemPalace ---------------------------------------------------------------
# Defaults only. env.local is sourced further down, well after this point, so
# the overrides are re-read in _setup_mempalace — assigning them here alone
# would freeze them before the user's values ever land.
MEMPALACE_MODEL="embeddinggemma"
MEMPALACE_CONFIG="$HOME/.mempalace/config.json"
MEMPALACE_PALACE="$HOME/.mempalace/palace"

# The configured model is also the model the existing palace was built with:
# chromadb refuses reads when the two diverge, so a palace that opens at all
# agrees with config.json. No palace introspection needed.
_mempalace_configured_model() {
  local model=""
  if [[ -f "$MEMPALACE_CONFIG" ]]; then
    model="$(jq -r '.embedding_model // empty' "$MEMPALACE_CONFIG" 2>/dev/null || true)"
  fi
  printf '%s\n' "${model:-minilm}"
}

# No CLI subcommand writes this key (`palace set-embedder` only records identity
# metadata), so the config file is edited directly. Never export
# MEMPALACE_EMBEDDING_MODEL instead: the env var outranks the file, and a stale
# one left in a shell profile would silently override the palace on later runs.
_mempalace_set_model() {
  local model="$1"
  local tmp
  mkdir -p "$(dirname "$MEMPALACE_CONFIG")"
  [[ -f "$MEMPALACE_CONFIG" ]] || printf '{}\n' > "$MEMPALACE_CONFIG"
  tmp="$(mktemp)"
  if jq --arg m "$model" '.embedding_model = $m' "$MEMPALACE_CONFIG" > "$tmp"; then
    mv "$tmp" "$MEMPALACE_CONFIG"
    chmod 600 "$MEMPALACE_CONFIG" 2>/dev/null || true
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# A palace with no recorded embedder identity prints an EmbedderIdentityUnknown
# warning on every single search — noise in front of every result Claude reads.
# `init` and `repair rebuild-index` both leave it unrecorded, so record it after
# each. --force is safe only here: we call this right after building the palace
# with exactly the configured model, so the vectors are known to match.
_mempalace_record_identity() {
  _run_quiet mempalace palace set-embedder --model "$(_mempalace_configured_model)" --force \
    || echo "  ${DIM}· mempalace: embedder identity not recorded${RESET}"
}

# Independent of the model comparison: a palace can be both on the wrong model
# and diverged, and the divergence is what breaks reads and segfaults writes.
_mempalace_diverged() {
  [[ -f "$MEMPALACE_PALACE/chroma.sqlite3" ]] || return 1
  mempalace repair-status 2>/dev/null | grep -q 'DIVERGED'
}

# missing | mismatch | diverged | ok
_mempalace_state() {
  # chroma.sqlite3, not the directory: `mempalace init` writes config.json but
  # never creates palace/, so "directory exists" is not "initialized".
  [[ -f "$MEMPALACE_PALACE/chroma.sqlite3" ]] || { printf 'missing\n'; return; }
  [[ "$(_mempalace_configured_model)" == "$MEMPALACE_MODEL" ]] || { printf 'mismatch\n'; return; }
  _mempalace_diverged && { printf 'diverged\n'; return; }
  printf 'ok\n'
}

# Yes/no prompt. $2 is the answer used for empty input and for -y runs.
_ask() {
  local prompt="$1" default="$2" answer
  if [[ "$AUTO_YES" == "true" ]]; then
    _is_yes "$default"
    return
  fi
  printf '%s ' "$prompt"
  read -r answer
  [[ -z "$answer" ]] && answer="$default"
  _is_yes "$answer"
}

_setup_mempalace() {
  export PYTHONUTF8=1
  # Now that env.local has been sourced, honour its overrides.
  # Multilingual by default: repo content and session transcripts here are
  # largely non-English, and MemPalace's own default (minilm /
  # all-MiniLM-L6-v2) is trained on English only.
  MEMPALACE_MODEL="${MEMPALACE_EMBEDDING_MODEL:-embeddinggemma}"
  MEMPALACE_PALACE="${MEMPALACE_PALACE_PATH:-$HOME/.mempalace/palace}"

  if ! command -v jq >/dev/null; then
    echo "  ${YELLOW}⚠ jq missing — MemPalace embedding model left as configured.${RESET}"
    MEMPALACE_MODEL="$(_mempalace_configured_model)"
  fi

  local state current drawers
  state="$(_mempalace_state)"
  current="$(_mempalace_configured_model)"

  case "$state" in
    missing)
      mkdir -p "$HOME/.mempalace"
      # Set the model before init so the palace is built with it from the start
      # and no re-embed is ever needed on a fresh machine.
      command -v jq >/dev/null && _mempalace_set_model "$MEMPALACE_MODEL"
      # LLM-assisted refinement only when the default Ollama model is actually
      # available; otherwise heuristics-only, without the graceful-fallback
      # notice. timeout: `ollama list` blocks indefinitely when the binary
      # exists but the daemon is down — never let the gate hang the install.
      local -a llm_flag=()
      timeout 5 ollama list 2>/dev/null | grep -q gemma4 || llm_flag=(--no-llm)
      # Pipe 'n' to decline init's "Mine this directory now?" prompt: mining
      # ~/.mempalace itself only indexes its own config.json into a junk wing.
      # Repos are mined into their own wings by _mine_repo_into_wing instead.
      printf 'n\n' | mempalace init --yes ${llm_flag[@]+"${llm_flag[@]}"} ~/.mempalace
      _mempalace_record_identity
      echo "  ${GREEN}✓ MemPalace initialized (embedder: $MEMPALACE_MODEL)${RESET}"
      ;;
    mismatch)
      drawers="$(mempalace repair-status 2>/dev/null | sed -n 's/.*sqlite count:[[:space:]]*//p' | head -1)"
      echo "  ${YELLOW}MemPalace embedder: palace holds '$current', target is '$MEMPALACE_MODEL'.${RESET}"
      echo "  ${DIM}Switching re-embeds every drawer (${drawers:-?}) and downloads the model — several minutes.${RESET}"
      # Default no, including under -y: an unbounded download plus full re-embed
      # must not ambush an unattended install.
      if _ask "  Re-index now ${CYAN}[y/N]${RESET}?" "n"; then
        _mempalace_set_model "$MEMPALACE_MODEL"
        if mempalace repair rebuild-index --yes; then
          _mempalace_record_identity
          echo "  ${GREEN}✓ MemPalace re-indexed with $MEMPALACE_MODEL${RESET}"
        else
          _mempalace_set_model "$current"
          echo "  ${YELLOW}⚠ Re-index failed — reverted to '$current', palace still readable.${RESET}"
        fi
      else
        echo "  ${DIM}· Kept '$current' — re-run install.sh and accept to switch.${RESET}"
      fi
      ;;
    diverged)
      _mempalace_repair_divergence
      ;;
    *)
      _ok "MemPalace ($current)"
      ;;
  esac

  # A declined re-index leaves the palace on its old model — and possibly still
  # diverged, which silently degrades every search to keyword matching. Re-check
  # rather than letting the mismatch branch mask it.
  [[ "$state" == "mismatch" ]] && _mempalace_diverged && _mempalace_repair_divergence

  # Gate for _mine_repo_into_wing: mining a diverged palace segfaults chromadb.
  if _mempalace_diverged; then MEMPALACE_READY=false; else MEMPALACE_READY=true; fi
  return 0
}

_mempalace_repair_divergence() {
  echo "  ${YELLOW}MemPalace: vector search disabled — HNSW index diverged from SQLite.${RESET}"
  mempalace repair-status 2>/dev/null | sed -n 's/^\(.*count:.*\|.*divergence:.*\)$/  \1/p'
  # Default yes, including under -y: bounded work, and semantic search stays
  # broken until it runs.
  if _ask "  Rebuild the index now ${CYAN}[Y/n]${RESET}?" "y"; then
    # rebuild-index (--mode from-sqlite --archive-existing), not plain `repair`:
    # legacy mode bails when the chromadb client cannot open the collection —
    # which is exactly the diverged state — and exits 0 having done nothing.
    # from-sqlite reads the rows directly and archives the old palace first.
    if mempalace repair rebuild-index --yes; then
      _mempalace_record_identity
      echo "  ${GREEN}✓ MemPalace index rebuilt — semantic search restored${RESET}"
      echo "  ${DIM}  (previous palace kept as ~/.mempalace/palace.pre-rebuild-*)${RESET}"
    else
      echo "  ${YELLOW}⚠ Repair failed — searches stay keyword-only (mempalace repair rebuild-index)${RESET}"
    fi
  else
    echo "  ${DIM}· Skipped — searches stay keyword-only until the rebuild runs.${RESET}"
  fi
}

# Claude Code stores transcripts in ~/.claude/projects/<native path with every
# non-alphanumeric character replaced by '-'>. Drive-letter case varies between
# entries, so the comparison is case-insensitive.
_transcript_dir_for() {
  local repo="$1"
  local native="$repo"
  _is_windows && native="$(cygpath -w "$repo" 2>/dev/null || printf '%s' "$repo")"
  local encoded
  encoded="$(printf '%s' "$native" | sed 's/[^a-zA-Z0-9]/-/g')"
  local dir
  for dir in "$CLAUDE_DIR/projects"/*/; do
    [[ -d "$dir" ]] || continue
    if [[ "$(basename "$dir")" == "${encoded,,}" || "${dir,,}" == *"/${encoded,,}/" ]]; then
      printf '%s\n' "${dir%/}"
      return 0
    fi
  done
  return 1
}

# Files and past transcripts of one repo, both into that repo's own wing —
# this is what makes `mempalace search --wing <repo>` return anything.
_mine_repo_into_wing() {
  local repo="$1" wing="$2"
  command -v mempalace >/dev/null || return 0
  # Writing into a palace whose HNSW index has diverged segfaults chromadb
  # (observed: exit 139, nothing filed). _setup_mempalace clears this flag when
  # the index is healthy; without it, every repo would crash in turn.
  [[ "${MEMPALACE_READY:-false}" == "true" ]] || return 0
  # --background: mining 18 repos synchronously would add minutes to every run.
  if mempalace mine "$repo" --wing "$wing" --background >/dev/null 2>&1; then
    _detail "  ${DIM}· mempalace: mining → wing '$wing'${RESET}"
  else
    echo "  ${DIM}· mempalace: file mining skipped${RESET}"
  fi
  local transcripts
  transcripts="$(_transcript_dir_for "$repo" || true)"
  if [[ -n "$transcripts" ]]; then
    mempalace mine "$transcripts" --mode convos --wing "$wing" --background >/dev/null 2>&1 \
      || echo "  ${DIM}· mempalace: transcript mining skipped${RESET}"
  fi
}

_ensure_shellcheck() {
  if command -v shellcheck >/dev/null; then
    _ok "shellcheck"
    return 0
  fi
  if _is_windows; then
    # stable-tag asset: version-independent URL. GNU tar in Git Bash cannot
    # read zip archives; delegate extraction to PowerShell.
    local tmp
    tmp="$(mktemp -d)"
    if _run_quiet curl -fsSL -o "$tmp/shellcheck.zip" "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.zip" \
      && _run_quiet powershell.exe -NoProfile -Command "Expand-Archive -Force '$(cygpath -w "$tmp/shellcheck.zip")' '$(cygpath -w "$tmp")'" \
      && cp "$tmp/shellcheck.exe" "$TOOL_BIN_DIR/"; then
      _ok "shellcheck installed ($TOOL_BIN_DIR/shellcheck.exe)"
    else
      echo "  ${YELLOW}⚠ shellcheck: install failed — pre-commit lint will be skipped (scoop install shellcheck)${RESET}"
    fi
    rm -rf "$tmp"
  else
    echo "  ${YELLOW}⚠ shellcheck missing — pre-commit lint skipped (brew install shellcheck / apt install shellcheck)${RESET}"
  fi
}

# Windows 11 delegates hidden-console allocations to Windows Terminal by
# default ("Let Windows decide"), and Windows Terminal cannot create an
# invisible window — so every background spawn (Stop-hook vault sync, graphify
# rebuilds, the per-commit FILE_TREE powershell) flashes a terminal window.
# Delegating to the classic Windows Console Host honours hidden spawns.
# Revert: Windows Terminal > Settings > Startup > Default terminal application.
CONHOST_DELEGATION_GUID="{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"
_setup_terminal_delegation() {
  _is_windows || return 0
  local key='HKCU\Console\%%Startup' current
  current="$(reg.exe query "$key" //v DelegationTerminal 2>/dev/null | tr -d '\r')" || true
  if [[ "$current" == *"$CONHOST_DELEGATION_GUID"* ]]; then
    _ok "terminal delegation (conhost)"
    return 0
  fi
  echo "${BOLD}${CYAN}Windows default terminal:${RESET} Windows Terminal handles hidden-console spawns"
  echo "${DIM}Background hooks (automatic vault commits, graph rebuilds) briefly flash a terminal window. Delegating to Windows Console Host makes them silent; regular terminals are unaffected.${RESET}"
  if _ask "Set the default terminal to Windows Console Host ${CYAN}[Y/n]${RESET}?" "y"; then
    reg.exe add "$key" //v DelegationConsole //t REG_SZ //d "$CONHOST_DELEGATION_GUID" //f >/dev/null \
      && reg.exe add "$key" //v DelegationTerminal //t REG_SZ //d "$CONHOST_DELEGATION_GUID" //f >/dev/null \
      && _ok "terminal delegation → conhost" \
      || echo "  ${YELLOW}⚠ could not update terminal delegation (registry write failed)${RESET}"
  else
    echo "  ${YELLOW}Default terminal left unchanged — background hooks may flash windows.${RESET}"
  fi
}

# On Windows, `uv tool install --upgrade` fails with "Accès refusé (os error 5)"
# when a running process (e.g. an MCP server spawned by an open Claude Code
# session) holds files open under the tool's venv — Windows cannot delete open
# files. Kill the lockers and retry with --reinstall to recover the half-upgraded
# venv the failed attempt leaves behind.
_uv_tool_install() {
  local pkg="$1"
  _run_quiet uv tool install "$pkg" --upgrade && return 0
  _is_windows || return 1
  echo "  ${DIM}· $pkg: venv locked by a running process — stopping it and retrying${RESET}"
  # Win32_Process, not Get-Process: enumerating Get-Process .Path aborts the
  # pipeline on the first process whose MainModule is inaccessible (PS 5.1).
  local pat
  # shellcheck disable=SC1003  # literal backslashes, not an escaped quote
  pat="${APPDATA:-}"'\uv\tools\'"$pkg"'\*'
  powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.ExecutablePath -like '$pat' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1 || true
  _run_quiet uv tool install "$pkg" --upgrade --reinstall
}

_prepare_dependencies() {
  echo "${BOLD}${CYAN}Preparing dependencies...${RESET}"
  mkdir -p "$TOOL_BIN_DIR"
  _add_tool_paths_to_current_session

  command -v node >/dev/null || { echo "${RED}Node.js is required (https://nodejs.org)${RESET}"; exit 1; }
  _ensure_uv
  # After _ensure_uv: it is what asks for PATH-persistence consent.
  _ensure_npm_bin_on_path

  _uv_tool_install graphifyy
  command -v graphify >/dev/null || { echo "${RED}Graphify installed but not found in current PATH.${RESET}"; exit 1; }
  # Keep the user-level Claude skill in step with the package: it is written
  # once by `graphify install` and never refreshed by upgrades, so every
  # graphify command warns "skill is from X, package is Y" until re-run.
  _run_quiet graphify install --platform claude || true
  _ok "Graphify"

  _uv_tool_install mempalace
  command -v mempalace >/dev/null || { echo "${RED}MemPalace installed but not found in current PATH.${RESET}"; exit 1; }
  _ok "MemPalace"

  _ensure_chromadb

  if command -v rtk >/dev/null; then
    _ok "RTK"
  elif SETUP_RTK_INIT=false SETUP_RTK_MANAGE_PATH=false SETUP_RTK_QUIET=true bash "$REPO_DIR/scripts/setup-rtk.sh"; then
    _ok "RTK ready"
  else
    echo "  ${YELLOW}⚠ RTK: install/prepare failed, will attempt activation later.${RESET}"
  fi

  # jq is required by the cc-safe-setup hooks for JSON parsing
  if command -v jq >/dev/null; then
    _ok "jq"
  elif _is_windows; then
    # Direct release download — usable in the current session, no winget
    # dependency (winget is often unresolvable from Git Bash, and a winget
    # install would not be in PATH until a new terminal anyway).
    if _run_quiet curl -fsSL -o "$TOOL_BIN_DIR/jq.exe" "https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe"; then
      _ok "jq installed ($TOOL_BIN_DIR/jq.exe)"
    else
      echo "  ${YELLOW}⚠ jq: download failed — cc-safe-setup hooks need it (winget install jqlang.jq / scoop install jq)${RESET}"
    fi
  else
    echo "  ${YELLOW}⚠ jq missing — cc-safe-setup hooks need it (brew install jq / apt install jq)${RESET}"
  fi

  _ensure_shellcheck

  if _run_quiet npm install -g --no-fund --no-audit --loglevel=error context-mode; then
    _ok "context-mode"
  else
    echo "  ${YELLOW}⚠ context-mode: install failed — run manually: npm install -g context-mode${RESET}"
  fi

  if [[ -n "${MILVUS_ADDRESS:-}" ]]; then
    if _run_quiet npm install -g --no-fund --no-audit --loglevel=error @zilliz/claude-context-mcp; then
      _ok "Zilliz (semantic search — add MCP server manually to settings.json if needed)"
    else
      echo "  ${YELLOW}⚠ Zilliz install failed — run manually: npm install -g @zilliz/claude-context-mcp${RESET}"
    fi
  else
    _detail "  ${DIM}· Zilliz: skipped (MILVUS_ADDRESS not set in env.local)${RESET}"
  fi
  _ok_flush
}

# Pinned Claude Code plugins, replicated on every machine.
# Format: "<marketplace-repo>|<plugin>@<marketplace-name>"
PINNED_PLUGINS=(
  "DietrichGebert/ponytail|ponytail@ponytail"
  "JuliusBrussee/caveman|caveman@caveman"
)

_install_pinned_plugins() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "  ${YELLOW}⚠ claude CLI not found — install plugins manually in Claude Code: /plugin install <name>${RESET}"
    return 0
  fi
  local entry marketplace plugin name
  for entry in "${PINNED_PLUGINS[@]}"; do
    marketplace="${entry%%|*}"
    plugin="${entry#*|}"
    name="${plugin%%@*}"
    if claude plugin list 2>/dev/null | grep -qi "$name"; then
      _detail "  ${DIM}· ${name}: already installed${RESET}"
      continue
    fi
    if ! claude plugin marketplace list 2>/dev/null | grep -qi "${marketplace##*/}"; then
      _run_quiet claude plugin marketplace add "$marketplace" || true
    fi
    if _run_quiet claude plugin install "$plugin"; then
      _ok "${plugin}"
    else
      echo "  ${YELLOW}⚠ ${plugin}: install failed — run manually:${RESET}"
      echo "    claude plugin marketplace add ${marketplace} && claude plugin install ${plugin}"
    fi
  done
}

# stdio MCP servers, as "<name> <command> [args...]".
# The MemPalace server is its own binary: `mempalace mcp` only prints setup help,
# which is why a client that ran it saw the process exit immediately.
MCP_STDIO_SERVERS=(
  "mempalace mempalace-mcp"
  "context-mode context-mode"
)

# Claude Code spawns stdio MCP servers without a shell, so on Windows only a real
# .exe is launchable: npm's shims (an extensionless sh script plus a .cmd) both
# fail with ENOENT, which the client reports as "Connection closed" (-32000).
# Those commands have to go through `cmd /c`.
_mcp_needs_cmd_shim() {
  _is_windows || return 1
  local resolved
  resolved="$(command -v "$1" 2>/dev/null)" || return 1
  # command -v drops the .exe suffix, so probe the file itself.
  [[ "$resolved" == *.exe || -f "$resolved.exe" ]] && return 1
  return 0
}

# `claude mcp add --scope user` writes to ~/.claude.json, the only place (with a
# project .mcp.json) Claude Code reads MCP servers from. Idempotent: an existing
# registration is left alone, so a re-run never duplicates or resets a server.
_setup_mcp_servers() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "  ${YELLOW}⚠ claude CLI not found — MCP servers not registered${RESET}"
    return 0
  fi

  local entry name cmd shim
  for entry in "${MCP_STDIO_SERVERS[@]}"; do
    # shellcheck disable=SC2086  # deliberate split: entry is "name command args..."
    set -- $entry
    name="$1"; cmd="$2"; shift 2
    if ! command -v "$cmd" >/dev/null 2>&1; then
      if claude mcp get "$name" >/dev/null 2>&1; then
        _detail "  ${DIM}· MCP $name: already registered${RESET}"
      else
        echo "  ${YELLOW}⚠ MCP $name: '$cmd' not on PATH — not registered${RESET}"
      fi
      continue
    fi
    local -a spawn=("$cmd" "$@")
    if _mcp_needs_cmd_shim "$cmd"; then
      # Absolute path to the .cmd shim, not the bare name: Claude Code inherits
      # its launcher's env, and a terminal opened before the npm dir landed on
      # the user PATH (or any GUI launch without it) spawns `cmd /c context-mode`
      # into "'context-mode' n'est pas reconnu" → -32000. The registration is
      # machine-local (~/.claude.json), so an absolute path is safe there.
      # //c, not /c: Git Bash rewrites a lone /c into a Windows path (C:/)
      # before the argument ever reaches claude; // collapses back to /c.
      shim="$(cygpath -w "$(command -v "$cmd")").cmd"
      spawn=(cmd //c "$shim" "$@")
    fi
    if claude mcp get "$name" >/dev/null 2>&1; then
      # Upgrade legacy bare-name registrations to the absolute shim in place;
      # anything else already registered is left alone.
      if ! _mcp_needs_cmd_shim "$cmd" || claude mcp get "$name" 2>/dev/null | grep -qF "$shim"; then
        _detail "  ${DIM}· MCP $name: already registered${RESET}"
        continue
      fi
      _run_quiet claude mcp remove --scope user "$name" || true
    fi
    if _run_quiet claude mcp add --scope user "$name" -- "${spawn[@]}"; then
      _ok "MCP $name"
    else
      echo "  ${YELLOW}⚠ MCP $name: registration failed${RESET}"
    fi
  done

  # Figma's remote server authenticates over OAuth, not with a personal access
  # token: figd_ keys are rejected there (401) whether sent as a bearer or as
  # X-Figma-Token — they only work against the desktop app's local server. So no
  # header at all; the browser flow runs once, from /mcp inside Claude Code.
  if claude mcp get figma >/dev/null 2>&1; then
    _detail "  ${DIM}· MCP figma: already registered${RESET}"
  elif _run_quiet claude mcp add --scope user --transport http figma "https://mcp.figma.com/mcp"; then
    _ok "MCP figma (authenticate once with /mcp)"
  else
    echo "  ${YELLOW}⚠ MCP figma: registration failed${RESET}"
  fi
}

# --- Load machine-specific vars ---
if [[ ! -f "$REPO_DIR/env.local" ]]; then
  echo "${RED}Copy env.local.template to env.local and fill in the values.${RESET}"
  echo "  cp env.local.template env.local"
  exit 1
fi
source "$REPO_DIR/env.local"

# --- Check prerequisites ---
_prepare_dependencies
_setup_terminal_delegation

# --- Clean broken symlinks in ~/.claude ---
echo "${BOLD}${CYAN}Configuring Claude...${RESET}"
_step "Cleaning broken symlinks..."
for dir in agents commands scripts hooks; do
  target="$CLAUDE_DIR/$dir"
  if [[ -L "$target" && ! -e "$target" ]]; then
    rm -f "$target"
    _detail "  ${YELLOW}⚠ Broken symlink removed: $target${RESET}"
  fi
done

# --- Copy agents, commands and scripts ---
_step "Copying agents, commands and scripts..."
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/templates"
# Use nullglob to avoid glob failure if a source directory is empty
(
  shopt -s nullglob
  for dir in agents commands scripts hooks templates; do
    files=("$REPO_DIR/$dir/"*)
    if [[ ${#files[@]} -gt 0 ]]; then
      cp -r "${files[@]}" "$CLAUDE_DIR/$dir/"
    fi
  done
)
chmod +x "$CLAUDE_DIR/hooks/"*.sh "$CLAUDE_DIR/scripts/"*.sh 2>/dev/null || true

# Mirror commands/ and agents/: prune deployed files whose source was removed
# from the repo, so deletions propagate to every machine. Other directories
# stay additive (scripts/ still holds leftovers from older installs).
for dir in agents commands; do
  for f in "$CLAUDE_DIR/$dir"/*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ ! -e "$REPO_DIR/$dir/$base" ]]; then
      rm -rf "$f"
      echo "  ${DIM}· pruned stale $dir/$base${RESET}"
    fi
  done
done
_detail "  ${GREEN}✓ Claude files copied${RESET}"

# --- Record the config repo location for hooks ---
# Hooks and generated scripts resolve the repo through this pointer instead of
# hardcoding an absolute path, so they survive repo moves and machine changes.
printf '%s\n' "$REPO_DIR" > "$CLAUDE_DIR/claude-config.path"
_detail "  ${GREEN}✓ claude-config.path recorded ($REPO_DIR)${RESET}"

# --- MemPalace: init, embedder, index health ---
# Repos are NOT mined here: each one is mined into its own wing by
# _mine_repo_into_wing, from _setup_repo_graphify. A single global mine of
# ~/.claude/projects/ is what produced the unscoped `projects`/`sessions` wings
# that made `search --wing <repo>` return nothing.
_step "Setting up MemPalace..."
_setup_mempalace

# --- Copy global CLAUDE.md (with vault path substitution) ---
_step "Copying global CLAUDE.md..."
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.backup"
  claude_backup_created=true
else
  claude_backup_created=false
fi
sed "s|\${VAULT_DIR}|$VAULT_DIR|g" "$REPO_DIR/CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
if [[ "$claude_backup_created" == "true" ]]; then
  _detail "  ${GREEN}✓ CLAUDE.md copied (backup created)${RESET}"
else
  _detail "  ${GREEN}✓ CLAUDE.md copied${RESET}"
fi

# --- MCP servers (user scope) ---
# Claude Code reads MCP servers from ~/.claude.json (what `claude mcp add`
# writes), from a project .mcp.json, or from managed policy — never from
# settings.json's "mcpServers" key nor from ~/.claude/claude.json. Both were
# used here and neither ever loaded a single server.
_step "Registering MCP servers..."
rm -f "$CLAUDE_DIR/claude.json"   # migration: unread file, and it held the Figma token
_setup_mcp_servers

# --- Copy settings.json ---
_step "Copying settings.json..."
cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# --- Install RTK (after CLAUDE.md and settings.json — rtk init -g may modify them) ---
_step "Activating RTK..."
if SETUP_RTK_MANAGE_PATH=false SETUP_RTK_QUIET=true bash "$CLAUDE_DIR/scripts/setup-rtk.sh"; then
  _detail "  ${GREEN}✓ RTK activated${RESET}"
else
  echo "  ${YELLOW}⚠ RTK: run manually: bash ~/.claude/scripts/setup-rtk.sh${RESET}"
fi

# --- Install CC Safe Setup (after settings.json copy — it appends hooks non-destructively) ---
_step "Installing safety hooks (cc-safe-setup)..."
if command -v npx >/dev/null; then
  # cc-safe-setup has no --yes flag and its "Install all N hooks?" prompt
  # hangs invisibly under _run_quiet — feed it a stream of "y" instead.
  if _run_quiet bash -c 'yes | npx --yes cc-safe-setup'; then
    _ok "CC Safe Setup (safety hooks active)"
  else
    echo "  ${YELLOW}⚠ CC Safe Setup failed — run manually: npx cc-safe-setup${RESET}"
  fi
else
  echo "  ${YELLOW}⚠ npx not found — CC Safe Setup skipped${RESET}"
fi

# cc-safe-setup registers hooks as bare .sh paths. On Windows that goes through
# the file association, which is `bash --login -i` — a fresh console window pops
# up on every hook fire. Prefix with an explicit interpreter.
# It also installs api-error-alert.sh, which reads a .stop_reason field Claude Code
# never sends: it fires on every normal Stop and its notifier is Linux/macOS-only.
# Drop it.
if command -v jq >/dev/null && [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  if jq '(.hooks[]?[]?.hooks[]?.command) |= (if test("^[^ ]+[.]sh$") then "bash \"" + . + "\"" else . end)
         | (.hooks[]?) |= map(select((.hooks | map(.command) | join(" ") | test("api-error-alert")) | not))' \
       "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" 2>/dev/null; then
    mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
    _detail "  ${DIM}hook commands normalized (bash prefix)${RESET}"
  else
    rm -f "$CLAUDE_DIR/settings.json.tmp"
  fi
fi

# --- Install pinned plugins (after settings.json copy — plugin state must survive it) ---
_step "Installing pinned plugins..."
_install_pinned_plugins

# --- Statusline: claude-bar, vendored at scripts/claude-bar (fork of
# @allthingsclaude/bar 0.1.6 with local fixes — no npm dependency). Already
# deployed by the scripts/ copy above; statusline.sh resolves it first. ---
_step "Checking statusline (claude-bar, vendored)..."
if command -v node >/dev/null; then
  _ok "claude-bar vendored"
  _detail "    ${DIM}login once: node ~/.claude/scripts/claude-bar/src/index.js login${RESET}"
else
  echo "  ${YELLOW}⚠ node not found — claude-bar half of the statusline disabled${RESET}"
fi

# --- Default terse mode: ponytail (never together with caveman — both compress
# output; scripts/style-toggle.sh switches between them via the plugins' user
# configs, which their SessionStart hooks re-read on every session — a bare
# flag file would be reset to the builtin 'full' default at the next session) ---
_style_cfg_root="${XDG_CONFIG_HOME:-${APPDATA:-$HOME/.config}}"
if [[ ! -f "$_style_cfg_root/ponytail/config.json" && ! -f "$_style_cfg_root/caveman/config.json" ]]; then
  bash "$CLAUDE_DIR/scripts/style-toggle.sh" ponytail full >/dev/null
  _detail "  ${DIM}ponytail enabled by default (full) — switch: style-toggle.sh caveman${RESET}"
fi
# Legacy caveman-toggle machinery (pre plugin-flag era) — retire deployed copies.
rm -f "$CLAUDE_DIR/scripts/caveman-toggle.sh" "$CLAUDE_DIR/caveman.enabled" "$CLAUDE_DIR/caveman.level"
_ok_flush
_detail "  ${GREEN}✓ Claude configuration updated${RESET}"

# --- Obsidian Vault ---
_detail "${BOLD}${CYAN}Obsidian Vault${RESET} ${DIM}$VAULT_DIR${RESET}"

# --- Setup Graphify in all git repos ---
echo ""
if [[ "$VERBOSE" == "true" ]]; then
  echo "${BOLD}${CYAN}Scanning for git repos...${RESET}"
else
  echo "${BOLD}${CYAN}Git repos${RESET}"
fi

REPOS_FOUND=()
PARENT_DIR="$(dirname "$REPO_DIR")"

# Single-level scan: only git repos directly under $PARENT_DIR are detected.
# Nested subfolders (monorepos, workspaces) are not traversed.
for dir in "$PARENT_DIR"/*/; do
  [[ -d "$dir/.git" ]] || continue
  repo_path="${dir%/}"
  [[ "$repo_path" == "$REPO_DIR" ]] && continue
  REPOS_FOUND+=("$repo_path")
done

# Returns 0 if CLAUDE.md is git-tracked in the repo
_is_claude_md_tracked() {
  git -C "$1" ls-files --error-unmatch "CLAUDE.md" &>/dev/null
}

_setup_repo_gitignore() {
  local repo="$1"
  local gitignore_claude_md="${2:-false}"
  local gitignore="$repo/.gitignore"
  local template="$REPO_DIR/templates/gitignore.append"

  # Remove old fragmented or stale-comment graphify blocks so template re-adds them cleanly
  if grep -qF "graphify-out/" "$gitignore" 2>/dev/null; then
    local tmp
    tmp=$(grep -v -E '^graphify-out/|^# Graphify' "$gitignore")
    printf '%s\n' "$tmp" > "$gitignore"
  fi

  # Append entries from the template that are not already present.
  # Comments and blank lines are written as-is to preserve readability.
  # CLAUDE.md is skipped when it is version-controlled in the repo.
  local added=()
  local pending_comments=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" || "$line" == \#* ]]; then
      pending_comments+="$line"$'\n'
      continue
    fi
    [[ "$line" == "CLAUDE.md" && "$gitignore_claude_md" != "true" ]] && pending_comments="" && continue
    if ! grep -qxF "$line" "$gitignore" 2>/dev/null; then
      printf '%s' "$pending_comments" >> "$gitignore"
      printf '%s\n' "$line" >> "$gitignore"
      added+=("$line")
    fi
    pending_comments=""
  done < "$template"

  if [[ ${#added[@]} -gt 0 ]]; then
    _detail "  ${GREEN}✓ .gitignore: added ${added[*]}${RESET}"
  fi
}

_generate_mempalace_yaml() {
  local repo="$1"
  local repo_name
  repo_name="$(canonical_repo_name "$repo")"
  local yaml_file="$repo/mempalace.yaml"
  if [[ -f "$yaml_file" ]]; then
    _detail "  ${DIM}· mempalace.yaml: already present — kept.${RESET}"
    return
  fi
  # vault/ only exists in the config repo (Obsidian notes, not code);
  # excluding a nonexistent dir is harmless elsewhere, so one list fits all.
  cat > "$yaml_file" << YAML
wing: $repo_name
exclude:
  - graphify-out/
  - vault/
  - .git/
  - node_modules/
YAML
  [[ "$VERBOSE" == "true" ]] && echo "  ${GREEN}✓ mempalace.yaml generated (wing: $repo_name)${RESET}" || echo "  ${DIM}· mempalace.yaml: generated${RESET}"
}

# Post-commit vault-sync hook line: resolves the config repo through the
# ~/.claude/claude-config.path pointer at runtime — no hardcoded absolute path.
VAULT_HOOK_LINE='CLAUDE_CONFIG_DIR="$(cat "$HOME/.claude/claude-config.path" 2>/dev/null)"; [ -d "$CLAUDE_CONFIG_DIR" ] && bash "$CLAUDE_CONFIG_DIR/scripts/sync-graph-to-vault.sh"'

_install_vault_sync_hook() {
  local repo="$1"
  local hook_file="$repo/.git/hooks/post-commit"
  if [[ -f "$hook_file" ]]; then
    # Migrate legacy lines that hardcoded an absolute repo path
    if grep -q 'sync-graph-to-vault' "$hook_file" && ! grep -qF 'claude-config.path' "$hook_file"; then
      local tmp
      tmp="$(grep -v 'sync-graph-to-vault' "$hook_file")"
      printf '%s\n' "$tmp" > "$hook_file"
    fi
    grep -qF 'claude-config.path' "$hook_file" || printf '%s\n' "$VAULT_HOOK_LINE" >> "$hook_file"
  else
    printf '#!/usr/bin/env bash\n%s\n' "$VAULT_HOOK_LINE" > "$hook_file"
    chmod +x "$hook_file"
  fi
}

# graphify's generated post-commit hook reads the first line of the graphify
# launcher to find its shebang; on Windows that launcher is a binary, so the
# command substitution ingests null bytes and bash warns on every commit.
# Stripping them with tr is harmless on POSIX installs too.
_patch_graphify_hook_nullbytes() {
  local hook="$1/.git/hooks/post-commit"
  [[ -f "$hook" ]] || return 0
  grep -qF 'tr -d "[:cntrl:]"' "$hook" && return 0
  sed -i 's#head -1 "$GRAPHIFY_BIN" | sed#head -1 "$GRAPHIFY_BIN" | tr -d "[:cntrl:]" | sed#' "$hook"
}

# graphify claude install injects a "## graphify" section into the repo's
# CLAUDE.md — generalized rules that already live in the global ~/.claude/CLAUDE.md.
# Keep the hooks it installs, drop the duplicated section (case-sensitive: the
# injected heading is exactly "## graphify", not "## Graphify (Knowledge Graph)").
_strip_graphify_md_section() {
  local md="$1/CLAUDE.md"
  [[ -f "$md" ]] && grep -q '^## graphify[[:space:]]*$' "$md" || return 0
  local tmp
  tmp="$(mktemp "$md.XXXXXX")"
  # Buffered blanks are only flushed before content, so the trailing blank line
  # left behind by the removed section is dropped instead of accumulating
  # one extra line in the tracked CLAUDE.md on every install run.
  if awk '
    /^## graphify[[:space:]]*$/{skip=1; next}
    skip && /^## /{skip=0}
    skip{next}
    /^[[:space:]]*$/{blanks = blanks $0 "\n"; next}
    {printf "%s", blanks; blanks=""; print}
  ' "$md" > "$tmp"; then
    mv "$tmp" "$md"
  else
    rm -f "$tmp"
    return 1
  fi
}

# CLAUDE.md files generated before the vault moved into the config repo point at
# ~/.claude/vault, which no longer exists — Claude follows a dead path looking
# for the graph report. Repair the path in place instead of regenerating, so any
# repo notes written below the template survive. Returns 0 only when it edited.
# Untracked CLAUDE.md only: rewriting a versioned one would dirty the repo.
_fix_stale_vault_path() {
  local md="$1/CLAUDE.md"
  [[ -f "$md" ]] || return 1
  # Literal text to find inside the file, not a path to expand — hence the
  # split, which also keeps shellcheck from reading it as a stray tilde (SC2088).
  local tilde='~'
  local stale="$tilde/.claude/vault"
  grep -qF "$stale" "$md" 2>/dev/null || return 1
  local tmp
  tmp="$(mktemp "$md.XXXXXX")"
  if sed "s|$stale|$VAULT_DIR|g" "$md" > "$tmp"; then
    mv "$tmp" "$md"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# `graphify update` is AST-only, so communities come out of it as "Community 12"
# — in GRAPH_REPORT, in the canvas groups and in every vault note. Naming them is
# a separate LLM pass. Default backend is the `claude` CLI already on PATH, so
# this costs no API key; set GRAPHIFY_LABEL_BACKEND=none in env.local to skip it.
#
# Only runs when there is something to name: `graphify label` re-clusters and
# rewrites graph.json on every invocation, which is not free even when the LLM
# has nothing left to do.
#
# Two kinds of non-name to catch. "Community 12" is the bare placeholder. The
# second is graphify's LLM-free fallback, which names each community after its
# highest-degree hub — so the labels come out as file names ("renderer.js",
# "package.json"). Both mean no LLM has ever described these communities, and
# matching only the first left such repos stuck on hub names forever.
_graphify_needs_labels() {
  local labels="$1/graphify-out/.graphify_labels.json"
  [[ -f "$labels" ]] || return 0
  grep -q '"Community [0-9]' "$labels" && return 0
  grep -qE '"[^"]+\.(js|mjs|cjs|jsx|ts|tsx|vue|svelte|py|php|rb|go|rs|java|kt|cs|swift|sh|sql|json|ya?ml|toml|md|css|scss|html)"' "$labels"
}

_graphify_semantic_pass() {
  local repo="$1"
  local backend="${GRAPHIFY_LABEL_BACKEND:-claude-cli}"
  [[ "$backend" == "none" ]] && return 0
  [[ -f "$repo/graphify-out/graph.json" ]] || return 0

  local model_args=()
  [[ -n "${GRAPHIFY_LABEL_MODEL:-}" ]] && model_args=(--model "$GRAPHIFY_LABEL_MODEL")

  if [[ "$backend" == "claude-cli" ]] && ! command -v claude >/dev/null 2>&1; then
    echo "  ${DIM}· labels: skipped (claude CLI not on PATH)${RESET}"
    return 0
  fi

  (
    cd "$repo" || exit 0
    # Deep semantic re-extraction: adds the INFERRED edges that connect files the
    # AST pass leaves as isolated islands. Slow and token-hungry on every repo,
    # hence opt-in.
    if _is_yes "${GRAPHIFY_DEEP_EXTRACT:-false}"; then
      _detail "  Deep semantic extraction ($backend)..."
      _run_quiet graphify extract . --backend "$backend" "${model_args[@]}" --mode deep \
        && echo "  ${DIM}· graph: deep extraction done${RESET}" \
        || echo "  ${YELLOW}⚠ deep extraction failed (non-blocking)${RESET}"
    fi
    if _graphify_needs_labels "$repo"; then
      # No --missing-only: it narrows the LLM to communities whose label is absent
      # or exactly "Community N", so a repo sitting on hub-derived file names would
      # come back untouched. _graphify_needs_labels is the gate; once it fires, the
      # whole set gets named. Labeling is batched 100 communities per call, so a
      # full pass costs a handful of calls even on the largest repo here.
      _detail "  Naming communities ($backend)..."
      _run_quiet graphify label . --backend "$backend" "${model_args[@]}" \
        && echo "  ${DIM}· labels: named${RESET}" \
        || echo "  ${YELLOW}⚠ community labeling failed (non-blocking)${RESET}"
    else
      _detail "  ${DIM}· labels: already named${RESET}"
    fi
  )
}

_setup_repo_graphify() {
  local repo="$1"
  # Config-repo mode: skip .gitignore management (the repo versions its own),
  # and always refresh the graph synchronously so the vault-sync commit below
  # includes it — a stale graph left the post-commit hook's background rebuild
  # to dirty graphify-out/ after install finished.
  local is_config="${2:-false}"
  # graphify skips hooks that already exist (even with --force), so a repo keeps
  # whatever template it got first. Old templates detached the background rebuild
  # with DETACHED_PROCESS: the console-less child then flashes a visible console
  # window for every git call it spawns during the rebuild. Uninstall+install
  # rewrites the block with the current template (CREATE_NO_WINDOW, no flash);
  # non-graphify hook content (vault sync line) is preserved by both commands.
  _graphify_hook_refresh() {
    _run_quiet graphify hook uninstall || true
    _run_quiet graphify hook install
  }
  local repo_name
  repo_name="$(canonical_repo_name "$repo")"
  local obsidian_dir="$VAULT_DIR/Projets/$repo_name"
  mkdir -p "$obsidian_dir"

  # Versioned CLAUDE.md → full setup; otherwise → generate + gitignore
  if _is_claude_md_tracked "$repo"; then
    (
      cd "$repo"
      _run_quiet graphify claude install
      _detail "  ${GREEN}✓ claude install${RESET}"
      _graphify_hook_refresh
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _patch_graphify_hook_nullbytes "$repo"
    _strip_graphify_md_section "$repo"
    [[ "$is_config" == "true" ]] || _setup_repo_gitignore "$repo" false
    _detail "  ${DIM}· CLAUDE.md: versioned — hooks installed${RESET}"
  else
    # Generate CLAUDE.md from template only when absent — never overwrite a
    # local (untracked) CLAUDE.md the user may have customized.
    local claude_md_state
    if [[ -f "$repo/CLAUDE.md" ]]; then
      claude_md_state="kept"
      _fix_stale_vault_path "$repo" && claude_md_state="repaired"
      _detail "  ${DIM}CLAUDE.md already present — $claude_md_state.${RESET}"
    else
      claude_md_state="generated"
      sed -e "s|{{REPO_NAME}}|$repo_name|g" -e "s|{{VAULT_DIR}}|$VAULT_DIR|g" \
        "$REPO_DIR/templates/CLAUDE.project.md" > "$repo/CLAUDE.md"
      _detail "  ${GREEN}✓ CLAUDE.md generated from template (local)${RESET}"
    fi
    (
      cd "$repo"
      _graphify_hook_refresh
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _patch_graphify_hook_nullbytes "$repo"
    _setup_repo_gitignore "$repo" true
    _detail "  ${DIM}· CLAUDE.md: $claude_md_state (local) — hooks installed${RESET}"
  fi

  (
    cd "$repo"
    if [[ "$is_config" != "true" && -f "graphify-out/GRAPH_REPORT.md" ]]; then
      _detail "  ${DIM}· graph: kept${RESET}"
    else
      _detail "  Updating graph..."
      if [[ "$VERBOSE" == "true" ]]; then
        graphify update . && echo "  ${GREEN}✓ graph updated${RESET}" || echo "  ${YELLOW}⚠ graph: post-processing error (non-blocking)${RESET}"
      else
        graphify update . >/dev/null 2>&1 && _detail "  ${DIM}· graph: updated${RESET}" || echo "  ${YELLOW}⚠ graph: post-processing error (non-blocking)${RESET}"
      fi
    fi
  )

  # Name communities before syncing, so the vault gets the real names rather than
  # "Community 12" frozen into the canvas groups and the notes' frontmatter.
  _graphify_semantic_pass "$repo"

  # Sync vault: GRAPH_REPORT.md + FILE_TREE.md + canvas + one note per graph node
  (cd "$repo" && bash "$REPO_DIR/scripts/sync-graph-to-vault.sh")
  _detail "  ${DIM}· vault: synced${RESET}"

  # Post-commit hook for vault sync (pointer-based, migrates legacy absolute paths)
  _install_vault_sync_hook "$repo"
  _detail "  ${GREEN}✓ vault sync hook${RESET}"

  _generate_mempalace_yaml "$repo"
  _mine_repo_into_wing "$repo" "$repo_name"
}

if [[ ${#REPOS_FOUND[@]} -eq 0 ]]; then
  echo "${DIM}No git repos found (excluding claude-config).${RESET}"
else
  echo "${BOLD}Repos found — choose which to index (graphify + mempalace + vault):${RESET}"
  echo ""
  for repo in "${REPOS_FOUND[@]}"; do
    repo_name="$(canonical_repo_name "$repo")"
    local_name="$(basename "$repo")"
    repo_label="$repo_name"
    [[ "$local_name" != "$repo_name" ]] && repo_label="$local_name → $repo_name"
    if [[ -f "$repo/.graphifyignore" ]]; then
      state=" ${YELLOW}[excluded]${RESET}"
    else
      state=" ${GREEN}[indexed]${RESET}"
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
      current="${DIM} (currently excluded)${RESET}"
      default_hint="${CYAN}[y/N]${RESET}"
    else
      current="${DIM} (currently indexed)${RESET}"
      default_hint="${CYAN}[Y/n]${RESET}"
    fi

    if [[ "$AUTO_YES" == "true" ]]; then
      [[ -f "$repo/.graphifyignore" ]] && answer="n" || answer="y"
      printf "Index %b%-40s%b%b → %s (default)\n" "$BOLD" "$repo_label" "$RESET" "$current" "$answer"
    else
      printf "Index %b%-40s%b%b %b? " "$BOLD" "$repo_label" "$RESET" "$current" "$default_hint"
      read -r answer
      # Default based on current state: excluded→N, indexed→Y
      if [[ -z "$answer" ]]; then
        [[ -f "$repo/.graphifyignore" ]] && answer="n" || answer="y"
      fi
    fi

    if _is_yes "$answer"; then
      # Make sure it is not excluded (remove .graphifyignore if present)
      rm -f "$repo/.graphifyignore"
      _detail "${BOLD}[$repo_label]${RESET} ${YELLOW}Setting up...${RESET}"
      _setup_repo_graphify "$repo"
      echo "  ${GREEN}✓ $repo_label${RESET}"
    else
      if ! bash "$REPO_DIR/scripts/exclude-from-index.sh" --yes "$repo"; then
        echo "  ${YELLOW}⚠ Exclusion of $repo_label incomplete — continuing installation.${RESET}"
      fi
    fi
  done
fi

# Graphify for the config repo itself — same pipeline as indexed repos,
# in config mode (no .gitignore management, forced graph refresh).
echo ""
_detail "${BOLD}[claude-config]${RESET} Setting up..."
_setup_repo_graphify "$REPO_DIR" true
echo "  ${GREEN}✓ claude-config${RESET}"

# Lint gate (shellcheck) — config repo ONLY: its scripts are deployed to
# every machine and inherited by forks, so quality is enforced at the source.
# (Comment must not start with "shellcheck": that word right after "#" is
# parsed as a shellcheck directive.)
cat > "$REPO_DIR/.git/hooks/pre-commit" << 'PRECOMMIT'
#!/usr/bin/env bash
# Generated by install.sh — DO NOT EDIT MANUALLY.
# Blocks commits on shellcheck warnings in staged shell scripts.
command -v shellcheck >/dev/null || exit 0
mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM -- '*.sh')
[[ ${#files[@]} -eq 0 ]] && exit 0
shellcheck -S warning "${files[@]}"
PRECOMMIT
chmod +x "$REPO_DIR/.git/hooks/pre-commit"
_detail "  ${GREEN}✓ shellcheck pre-commit gate${RESET}"

# Harden vault auto-sync against multi-machine divergence:
#  - keep THIS machine's regenerated vault on merge conflicts (merge=ours driver,
#    referenced by .gitattributes' `vault/** merge=ours`)
#  - ensure a manual `git pull` uses merge (not rebase) so that driver applies
git -C "$REPO_DIR" config merge.ours.driver true
git -C "$REPO_DIR" config pull.rebase false

# Commit the vault and reconcile with origin (fetch→merge→push, conflict-safe)
echo ""
if bash "$REPO_DIR/scripts/vault-sync.sh"; then
  echo "${GREEN}✓ Vault synced with origin.${RESET}"
else
  echo "${YELLOW}⚠ Vault sync incomplete — see message above.${RESET}"
fi

echo ""
echo "${GREEN}Installation complete.${RESET}"
echo "${DIM}Restart Claude Code for changes to take effect.${RESET}"
echo ""
echo "${DIM}Tip: run ${CYAN}/init-context${DIM} inside any repo to generate context/architecture.md,${RESET}"
echo "${DIM}     context/patterns.md, and context/constraints.md from the codebase.${RESET}"
