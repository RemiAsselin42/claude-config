#!/usr/bin/env bash
# Shared helpers for deriving a stable project identity from git remotes,
# and for managing $TOOL_BIN_DIR in $PATH across profiles.

# ── PATH helpers ──────────────────────────────────────────────────────────────

TOOL_BIN_DIR="${TOOL_BIN_DIR:-$HOME/.local/bin}"

_is_windows() {
  [[ "${OS:-}" == "Windows_NT" ]] || [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || [[ "$(uname -s 2>/dev/null)" == CYGWIN* ]]
}

_add_tool_paths_to_current_session() {
  local path_entry
  for path_entry in "$TOOL_BIN_DIR" "$HOME/.cargo/bin"; do
    [[ -d "$path_entry" ]] || continue
    [[ ":$PATH:" == *":$path_entry:"* ]] || export PATH="$path_entry:$PATH"
  done
}

# Returns 0 if $profile already contains TOOL_BIN_DIR (or the sentinel comment).
_profile_has_tool_path() {
  local profile="$1"
  [[ -f "$profile" ]] || return 1
  grep -qF "# claude-config: tool path" "$profile" 2>/dev/null && return 0
  grep -qF "$TOOL_BIN_DIR" "$profile" 2>/dev/null && return 0
  grep -qF '$HOME/.local/bin' "$profile" 2>/dev/null
}

# Appends TOOL_BIN_DIR to the three canonical shell profiles (idempotent).
_write_tool_path_to_profiles() {
  local profile
  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    _profile_has_tool_path "$profile" && continue
    touch "$profile"
    {
      printf '\n# claude-config: tool path\n'
      printf 'case ":$PATH:" in\n'
      printf '  *":%s:"*) ;;\n' "$TOOL_BIN_DIR"
      printf '  *) export PATH="%s:$PATH" ;;\n' "$TOOL_BIN_DIR"
      printf 'esac\n'
    } >> "$profile"
  done
}

canonical_repo_name() {
  local repo="${1:-$PWD}"
  local remote=""
  local name=""

  remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote" ]]; then
    remote="$(git -C "$repo" config --get remote.origin.url 2>/dev/null || true)"
  fi

  if [[ -n "$remote" ]]; then
    remote="${remote%%\?*}"
    remote="${remote%/}"
    remote="${remote%.git}"
    if [[ "$remote" == *"/"* ]]; then
      name="${remote##*/}"
    elif [[ "$remote" == *":"* ]]; then
      name="${remote##*:}"
    else
      name="$remote"
    fi
  fi

  if [[ -z "$name" ]]; then
    name="$(basename "$repo")"
  fi

  # Keep the online repository name, but make it safe for local paths and wings.
  name="$(printf '%s\n' "$name" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$name" ]]; then
    basename "$repo" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//'
  else
    printf '%s\n' "$name"
  fi
}
