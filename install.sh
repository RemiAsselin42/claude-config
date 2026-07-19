#!/usr/bin/env bash
# Usage: install.sh [-y|--yes] [-v|--verbose]
#   -y, --yes      Accept defaults for each repo.
#   -v, --verbose  Show verbose output from installers.
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
  if [[ -z "$answer" || "${answer,,}" == "o" || "${answer,,}" == "oui" || "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
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

_ensure_uv() {
  export UV_INSTALL_DIR
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
    echo "  ${GREEN}✓ chromadb${RESET}"
    return 0
  fi

  _detail "  Installing chromadb into current Python..."
  # Use 'python -m pip install' rather than 'uv pip install --python' to avoid
  # environment validation issues on Windows
  if _run_quiet "$python_cmd" -m pip install chromadb; then
    "$python_cmd" -c 'import chromadb' >/dev/null 2>&1 || {
      echo "  ${YELLOW}⚠ chromadb installed but not importable by $python_cmd.${RESET}"
      return 0
    }
    echo "  ${GREEN}✓ chromadb installed${RESET}"
  else
    echo "  ${YELLOW}⚠ chromadb not installed — MemPalace cleanup will fall back to uv if available.${RESET}"
  fi
}

_prepare_dependencies() {
  echo "${BOLD}${CYAN}Preparing dependencies...${RESET}"
  mkdir -p "$TOOL_BIN_DIR"
  _add_tool_paths_to_current_session

  command -v node >/dev/null || { echo "${RED}Node.js is required (https://nodejs.org)${RESET}"; exit 1; }
  _ensure_uv

  _run_quiet uv tool install graphifyy --upgrade
  command -v graphify >/dev/null || { echo "${RED}Graphify installed but not found in current PATH.${RESET}"; exit 1; }
  echo "  ${GREEN}✓ Graphify${RESET}"

  _run_quiet uv tool install mempalace --upgrade
  command -v mempalace >/dev/null || { echo "${RED}MemPalace installed but not found in current PATH.${RESET}"; exit 1; }
  echo "  ${GREEN}✓ MemPalace${RESET}"

  _ensure_chromadb

  if command -v rtk >/dev/null; then
    echo "  ${GREEN}✓ RTK${RESET}"
  elif SETUP_RTK_INIT=false SETUP_RTK_MANAGE_PATH=false SETUP_RTK_QUIET=true bash "$REPO_DIR/scripts/setup-rtk.sh"; then
    echo "  ${GREEN}✓ RTK ready${RESET}"
  else
    echo "  ${YELLOW}⚠ RTK: install/prepare failed, will attempt activation later.${RESET}"
  fi

  if _run_quiet npm install -g context-mode; then
    echo "  ${GREEN}✓ context-mode${RESET}"
  else
    echo "  ${YELLOW}⚠ context-mode: install failed — run manually: npm install -g context-mode${RESET}"
  fi

  if [[ -n "${MILVUS_ADDRESS:-}" ]]; then
    if _run_quiet npm install -g @zilliz/claude-context-mcp; then
      echo "  ${GREEN}✓ Zilliz (semantic search — add MCP server manually to settings.json if needed)${RESET}"
    else
      echo "  ${YELLOW}⚠ Zilliz install failed — run manually: npm install -g @zilliz/claude-context-mcp${RESET}"
    fi
  else
    echo "  ${DIM}· Zilliz: skipped (MILVUS_ADDRESS not set in env.local)${RESET}"
  fi
}

# Pinned Claude Code plugins, replicated on every machine.
# Format: "<marketplace-repo>|<plugin>@<marketplace-name>"
PINNED_PLUGINS=(
  "DietrichGebert/ponytail|ponytail@ponytail"
  "JuliusBrussee/caveman|caveman@caveman"
)

_caveman_plugin_installed() {
  command -v claude >/dev/null 2>&1 || return 1
  claude plugin list 2>/dev/null | grep -qi "caveman"
}

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
      echo "  ${DIM}· ${name}: already installed${RESET}"
      continue
    fi
    if ! claude plugin marketplace list 2>/dev/null | grep -qi "${marketplace##*/}"; then
      _run_quiet claude plugin marketplace add "$marketplace" || true
    fi
    if _run_quiet claude plugin install "$plugin"; then
      echo "  ${GREEN}✓ ${plugin}${RESET}"
    else
      echo "  ${YELLOW}⚠ ${plugin}: install failed — run manually:${RESET}"
      echo "    claude plugin marketplace add ${marketplace} && claude plugin install ${plugin}"
    fi
  done
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

# --- Sync from upstream if available ---
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
  bash "$REPO_DIR/scripts/sync-upstream.sh" --force
  echo "  ${GREEN}✓ upstream synced${RESET}"
fi

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
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true
_detail "  ${GREEN}✓ Claude files copied${RESET}"

# --- Generate session-stop.sh with absolute repo path ---
_step "Generating session-stop.sh..."
SYNC_SCRIPT="$REPO_DIR/scripts/sync-graph-to-vault.sh"
cat > "$CLAUDE_DIR/scripts/session-stop.sh" << 'STOPSCRIPT'
#!/usr/bin/env bash
# Generated by install.sh — DO NOT EDIT MANUALLY.
# To regenerate: re-run install.sh from the claude-config repo.
# Claude Code Stop hook: updates graphify and syncs the vault if in a graphified repo.
[[ -d "graphify-out" ]] || exit 0
graphify update . 2>/dev/null || true
STOPSCRIPT
echo "bash \"$SYNC_SCRIPT\"" >> "$CLAUDE_DIR/scripts/session-stop.sh"
# Commit + reconcile + push via the shared, divergence-safe helper (fetch→merge→push).
echo "bash \"$REPO_DIR/scripts/vault-sync.sh\"" >> "$CLAUDE_DIR/scripts/session-stop.sh"
chmod +x "$CLAUDE_DIR/scripts/session-stop.sh"
_detail "  ${GREEN}✓ session-stop.sh generated${RESET}"

# --- Initialize MemPalace ---
_step "Initializing MemPalace..."
export PYTHONUTF8=1
if [[ -d "$HOME/.mempalace" ]]; then
  _detail "  ${DIM}Already initialized.${RESET}"
else
  mkdir -p "$HOME/.mempalace"
  mempalace init --yes ~/.mempalace
  echo "  ${GREEN}✓ MemPalace initialized${RESET}"
  if [[ -d "$CLAUDE_DIR/projects" ]]; then
    _detail "  Rebuilding index from transcripts..."
    mempalace mine "$CLAUDE_DIR/projects/" --mode convos || true
    echo "  ${GREEN}✓ MemPalace index rebuilt${RESET}"
  else
    echo "  ${DIM}No transcripts — empty index (normal on a new machine).${RESET}"
  fi
fi

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

# --- Generate claude.json from template ---
_step "Generating claude.json..."
sed "s|\${FIGMA_API_KEY}|${FIGMA_API_KEY}|g" \
  "$REPO_DIR/claude.json.template" > "$CLAUDE_DIR/claude.json"

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
  if _run_quiet npx cc-safe-setup; then
    echo "  ${GREEN}✓ CC Safe Setup (safety hooks active)${RESET}"
  else
    echo "  ${YELLOW}⚠ CC Safe Setup failed — run manually: npx cc-safe-setup${RESET}"
  fi
else
  echo "  ${YELLOW}⚠ npx not found — CC Safe Setup skipped${RESET}"
fi

# --- Install pinned plugins (after settings.json copy — plugin state must survive it) ---
_step "Installing pinned plugins..."
_install_pinned_plugins

# --- Preserve/restore caveman mode (after plugins — upstream plugin takes precedence) ---
# Copy defaults if not present on this machine (new install)
if [[ ! -f "$CLAUDE_DIR/caveman.enabled" && -f "$REPO_DIR/defaults/caveman.enabled" ]]; then
  cp "$REPO_DIR/defaults/caveman.enabled" "$CLAUDE_DIR/caveman.enabled"
  _detail "  ${DIM}caveman.enabled restored from defaults${RESET}"
fi
if [[ ! -f "$CLAUDE_DIR/caveman.level" && -f "$REPO_DIR/defaults/caveman.level" ]]; then
  cp "$REPO_DIR/defaults/caveman.level" "$CLAUDE_DIR/caveman.level"
  _detail "  ${DIM}caveman.level restored from defaults${RESET}"
fi
if _caveman_plugin_installed; then
  # The upstream plugin injects its own compression instructions via hook —
  # a local block in CLAUDE.md would duplicate them.
  bash "$CLAUDE_DIR/scripts/caveman-toggle.sh" remove 2>/dev/null || true
  echo "  ${DIM}· Caveman: handled by upstream plugin (local block stripped)${RESET}"
elif [[ -f "$CLAUDE_DIR/caveman.enabled" ]]; then
  bash "$CLAUDE_DIR/scripts/caveman-toggle.sh" inject 2>/dev/null || true
  _detail "  ${GREEN}✓ Caveman mode injected ($(cat "$CLAUDE_DIR/caveman.level" 2>/dev/null || echo full))${RESET}"
fi

echo "  ${GREEN}✓ Claude configuration updated${RESET}"

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
  local repo_name="$(canonical_repo_name "$repo")"
  local yaml_file="$repo/mempalace.yaml"
  if [[ -f "$yaml_file" ]]; then
    [[ "$VERBOSE" == "true" ]] && echo "  ${DIM}mempalace.yaml already present — kept.${RESET}" || echo "  ${DIM}· mempalace.yaml: present${RESET}"
    return
  fi
  cat > "$yaml_file" << YAML
wing: $repo_name
exclude:
  - graphify-out/
  - .git/
  - node_modules/
YAML
  [[ "$VERBOSE" == "true" ]] && echo "  ${GREEN}✓ mempalace.yaml generated (wing: $repo_name)${RESET}" || echo "  ${DIM}· mempalace.yaml: generated${RESET}"
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
  if awk '/^## graphify[[:space:]]*$/{skip=1; next} skip && /^## /{skip=0} !skip' "$md" > "$tmp"; then
    mv "$tmp" "$md"
  else
    rm -f "$tmp"
    return 1
  fi
}

_setup_repo_graphify() {
  local repo="$1"
  local repo_name="$(canonical_repo_name "$repo")"
  local obsidian_dir="$VAULT_DIR/Projets/$repo_name"
  mkdir -p "$obsidian_dir"

  # Versioned CLAUDE.md → full setup; otherwise → generate + gitignore
  if _is_claude_md_tracked "$repo"; then
    (
      cd "$repo"
      _run_quiet graphify claude install
      _detail "  ${GREEN}✓ claude install${RESET}"
      _run_quiet graphify hook install
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _strip_graphify_md_section "$repo"
    _setup_repo_gitignore "$repo" false
    [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· CLAUDE.md: versioned — hooks installed${RESET}" || true
  else
    # Generate CLAUDE.md from template with repo name substituted
    sed "s|{{REPO_NAME}}|$repo_name|g" "$REPO_DIR/templates/CLAUDE.project.md" > "$repo/CLAUDE.md"
    _detail "  ${GREEN}✓ CLAUDE.md generated from template (local)${RESET}"
    (
      cd "$repo"
      _run_quiet graphify hook install
      _detail "  ${GREEN}✓ hook install${RESET}"
    )
    _setup_repo_gitignore "$repo" true
    [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· CLAUDE.md: generated (local) — hooks installed${RESET}" || true
  fi

  (
    cd "$repo"
    if [[ -f "graphify-out/GRAPH_REPORT.md" ]]; then
      [[ "$VERBOSE" == "true" ]] && echo "  ${DIM}(existing graph kept)${RESET}" || echo "  ${DIM}· graph: kept${RESET}"
    else
      _detail "  Generating graph..."
      if [[ "$VERBOSE" == "true" ]]; then
        graphify update . && echo "  ${GREEN}✓ graph generated${RESET}" || echo "  ${YELLOW}⚠ graph: post-processing error (non-blocking)${RESET}"
      else
        graphify update . >/dev/null 2>&1 && echo "  ${DIM}· graph: generated${RESET}" || echo "  ${DIM}· graph: post-processing error (non-blocking)${RESET}"
      fi
    fi
  )

  # Sync vault: GRAPH_REPORT.md + FILE_TREE.md + graph.canvas
  (cd "$repo" && bash "$REPO_DIR/scripts/sync-graph-to-vault.sh")
  [[ "$VERBOSE" != "true" ]] && echo "  ${DIM}· vault: synced${RESET}" || true

  # Post-commit hook for vault sync
  local hook_file="$repo/.git/hooks/post-commit"
  local hook_line="bash \"$REPO_DIR/scripts/sync-graph-to-vault.sh\""
  if [[ -f "$hook_file" ]]; then
    grep -qF "sync-graph-to-vault" "$hook_file" || echo "$hook_line" >> "$hook_file"
  else
    printf '#!/usr/bin/env bash\n%s\n' "$hook_line" > "$hook_file"
    chmod +x "$hook_file"
  fi
  _detail "  ${GREEN}✓ vault sync hook${RESET}"

  _generate_mempalace_yaml "$repo"
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

    if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" || "${answer,,}" == "o" ]]; then
      # Make sure it is not excluded (remove .graphifyignore if present)
      rm -f "$repo/.graphifyignore"
      echo "${BOLD}[$repo_label]${RESET} ${YELLOW}Setting up...${RESET}"
      _setup_repo_graphify "$repo"
      echo "  ${GREEN}✓ $repo_label${RESET}"
    else
      if ! bash "$REPO_DIR/scripts/exclude-from-index.sh" --yes "$repo"; then
        echo "  ${YELLOW}⚠ Exclusion of $repo_label incomplete — continuing installation.${RESET}"
      fi
    fi
  done
fi

# Graphify for the config repo itself
echo ""
echo "${BOLD}[claude-config]${RESET} Setting up..."
_run_quiet graphify claude install
_detail "  ${GREEN}✓ claude install${RESET}"
_strip_graphify_md_section "$REPO_DIR"
_run_quiet graphify hook install
_detail "  ${GREEN}✓ hook install${RESET}"
if [[ -f "$REPO_DIR/graphify-out/GRAPH_REPORT.md" ]]; then
  _detail "  ${DIM}(existing graph kept)${RESET}"
else
  _detail "  Generating graph..."
  if [[ "$VERBOSE" == "true" ]]; then
    graphify update . && echo "  ${GREEN}✓ graph generated${RESET}" || echo "  ${YELLOW}⚠ graph: post-processing error (non-blocking)${RESET}"
  else
    graphify update . >/dev/null 2>&1 && echo "  ${DIM}· graph: generated${RESET}" || echo "  ${DIM}· graph: post-processing error (non-blocking)${RESET}"
  fi
fi
bash "$REPO_DIR/scripts/sync-graph-to-vault.sh"

# mempalace.yaml for claude-config (vault/ excluded — Obsidian notes, not code)
if [[ ! -f "$REPO_DIR/mempalace.yaml" ]]; then
  cat > "$REPO_DIR/mempalace.yaml" << YAML
wing: claude-config
exclude:
  - graphify-out/
  - vault/
  - .git/
YAML
  echo "  ${GREEN}✓ mempalace.yaml generated for claude-config${RESET}"
else
  echo "  ${DIM}mempalace.yaml already present — kept.${RESET}"
fi

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
