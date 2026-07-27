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

# Returns 0 if $profile already contains $dir (or its sentinel comment).
# $2/$3 default to TOOL_BIN_DIR and its historical sentinel, so the existing
# no-argument callers keep their exact behaviour.
_profile_has_tool_path() {
  local profile="$1" dir="${2:-$TOOL_BIN_DIR}" sentinel="${3:-tool path}"
  [[ -f "$profile" ]] || return 1
  grep -qF "# claude-config: $sentinel" "$profile" 2>/dev/null && return 0
  grep -qF "$dir" "$profile" 2>/dev/null && return 0
  [[ "$dir" == "$TOOL_BIN_DIR" ]] && grep -qF '$HOME/.local/bin' "$profile" 2>/dev/null
}

# Appends $dir (default TOOL_BIN_DIR) to the three canonical shell profiles.
_write_tool_path_to_profiles() {
  local dir="${1:-$TOOL_BIN_DIR}" sentinel="${2:-tool path}" profile
  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    _profile_has_tool_path "$profile" "$dir" "$sentinel" && continue
    touch "$profile"
    {
      printf '\n# claude-config: %s\n' "$sentinel"
      printf 'case ":$PATH:" in\n'
      printf '  *":%s:"*) ;;\n' "$dir"
      printf '  *) export PATH="%s:$PATH" ;;\n' "$dir"
      printf 'esac\n'
    } >> "$profile"
  done
}

# Where `npm install -g` puts its CLI shims. On Windows they land directly in
# the prefix (%APPDATA%\npm), elsewhere in <prefix>/bin. Prints the native path.
_npm_global_bin() {
  command -v npm >/dev/null 2>&1 || return 1
  local prefix
  prefix="$(npm prefix -g 2>/dev/null)" || return 1
  [[ -n "$prefix" ]] || return 1
  if _is_windows; then
    printf '%s\n' "$prefix"
  else
    printf '%s\n' "$prefix/bin"
  fi
}

# Windows keeps a persistent PATH of its own, which shell profiles never feed.
# A dir missing from it is invisible to every process Claude Code spawns —
# MCP servers and hook commands included. Idempotent; prints "added" when it
# actually changed the user PATH.
_ensure_windows_user_path() {
  local dir="$1"
  _is_windows || return 0
  [[ -n "$dir" ]] || return 0
  powershell.exe -NoProfile -Command "
    \$d = '${dir//\'/\'\'}'
    \$p = [Environment]::GetEnvironmentVariable('Path','User')
    if ((\$p -split ';') -notcontains \$d) {
      [Environment]::SetEnvironmentVariable('Path', (\$p.TrimEnd(';') + ';' + \$d), 'User')
      Write-Output 'added'
    }
  " 2>/dev/null | tr -d '\r'
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
