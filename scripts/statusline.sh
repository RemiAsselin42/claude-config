#!/usr/bin/env bash
# Claude Code statusline: @allthingsclaude/bar with the active terse-mode line
# (ponytail or caveman — style-toggle.sh keeps at most one on) inserted after
# bar's model line, restyled to match bar (brand label │ dim content).
# Wired by install.sh via settings.json → "statusLine".
# Degrades to whichever half is present: no mode plugin active → bar only,
# no claude-bar → raw badge only.

input=$(cat)

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Mode badge: delegate to the active plugin's own statusline script — ponytail
# first, caveman as fallback (style-toggle.sh keeps at most one flag on, so the
# first non-empty badge wins). Multiple cached plugin versions can coexist —
# pick the most recently modified script of each.
badge=""
for pattern in "ponytail/ponytail/*/hooks/ponytail-statusline.sh" \
               "caveman/caveman/*/src/hooks/caveman-statusline.sh"; do
  badge_script=""
  for s in "$CFG"/plugins/cache/$pattern; do
    [ -f "$s" ] || continue
    if [ -z "$badge_script" ] || [ "$s" -nt "$badge_script" ]; then
      badge_script="$s"
    fi
  done
  [ -n "$badge_script" ] && badge=$(bash "$badge_script" 2>/dev/null)
  [ -n "$badge" ] && break
done

# Resolve claude-bar into "$@": vendored copy first (scripts/claude-bar,
# deployed by install.sh — no npm dependency), then PATH, then npm-prefix
# fallbacks (the statusline shell is non-login, so nvm/asdf/Homebrew paths
# may be missing).
set --
if [ -f "$CFG/scripts/claude-bar/src/index.js" ] && command -v node >/dev/null 2>&1; then
  set -- node "$CFG/scripts/claude-bar/src/index.js"
elif command -v claude-bar >/dev/null 2>&1; then
  set -- claude-bar
else
  for c in "$APPDATA/npm/claude-bar" "$HOME/.npm-global/bin/claude-bar" \
           /opt/homebrew/bin/claude-bar /usr/local/bin/claude-bar \
           "$HOME/.asdf/shims/claude-bar" "$HOME"/.nvm/versions/node/*/bin/claude-bar; do
    [ -x "$c" ] && set -- "$c" && break
  done
fi

# Append effort level to model name ("Fable 5 · xhigh"). Per-session override
# comes in the stdin payload (.effort.level); fallback walks the same override
# order Claude Code uses (settings.local.json before settings.json). Only
# claude-bar consumes the patched payload — skip the jq work without it.
if [ $# -gt 0 ] && command -v jq >/dev/null 2>&1; then
  effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
  if [ -z "$effort" ]; then
    for f in "$CFG/settings.local.json" "$CFG/settings.json"; do
      [ -f "$f" ] || continue
      effort=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
      [ -n "$effort" ] && break
    done
  fi
  if [ -n "$effort" ]; then
    patched=$(printf '%s' "$input" | jq --arg e "$effort" \
      '.model.display_name = ((.model.display_name // "?") + " · " + $e)' 2>/dev/null)
    [ -n "$patched" ] && input="$patched"
  fi
fi

# claude-bar does auth/usage lookups — cap it so a network stall can never
# blank the whole statusline (the caveman half is a pure local read).
bar=""
if [ $# -gt 0 ]; then
  if command -v timeout >/dev/null 2>&1; then
    bar=$(printf '%s' "$input" | timeout 2 "$@" 2>/dev/null)
  else
    bar=$(printf '%s' "$input" | "$@" 2>/dev/null)
  fi
fi

# Restyle the badge as a bar-like line: "<Plugin> │ On · <Level> [· savings]".
# Handles both plugins' formats: "[PONYTAIL]", "[PONYTAIL:ULTRA]",
# "[CAVEMAN:X] <savings>". Colors copied from bar's colors.js (BRAND / DIM
# truecolor). ESC is built with printf — BSD sed has no \x1b escape. If a badge
# format ever drifts, pass the plugin's output through verbatim instead of guessing.
style_line=""
if [ -n "$badge" ]; then
  ESC=$(printf '\033')
  B="${ESC}[38;2;217;119;87m"; D="${ESC}[38;2;120;115;108m"; R="${ESC}[0m"
  plain=$(printf '%s' "$badge" | sed "s/${ESC}\[[0-9;]*m//g")
  case "$plain" in
    "["[A-Z]*)
      name=$(printf '%s' "$plain" | sed -n 's/^\[\([A-Z]*\)[]:].*/\1/p' | tr '[:upper:]' '[:lower:]')
      mode=$(printf '%s' "$plain" | sed -n 's/^\[[A-Z]*:\([A-Z0-9-]*\)\].*/\1/p' | tr '[:upper:]' '[:lower:]')
      [ -n "$mode" ] || mode=full
      savings=$(printf '%s' "$plain" | sed 's/^\[[^]]*\]//; s/^ *//')
      style_line="${B}${name^}${R}${D} │ ${R}${D}On · ${mode^}${R}"
      [ -n "$savings" ] && style_line="${style_line}${D} · ${savings}${R}"
      ;;
    *) style_line="$badge" ;;
  esac
fi

if [ -n "$bar" ] && [ -n "$style_line" ]; then
  # Mode line goes after bar's usage lines (Model/Cache/Usage), just
  # above the git line when bar ends with one ("Github" label).
  last=$(printf '%s\n' "$bar" | tail -n 1)
  plain_last=$(printf '%s' "$last" | sed "s/${ESC}\[[0-9;]*m//g")
  case "$plain_last" in
    "Github"*)
      printf '%s\n' "$bar" | sed '$d'
      printf '%s\n%s\n' "$style_line" "$last"
      ;;
    *)
      printf '%s\n%s\n' "$bar" "$style_line"
      ;;
  esac
elif [ -n "$bar" ]; then
  printf '%s' "$bar"
elif [ -n "$style_line" ]; then
  printf '%s\n' "$style_line"
fi
