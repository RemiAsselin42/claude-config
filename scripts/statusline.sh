#!/usr/bin/env bash
# Claude Code statusline: @allthingsclaude/bar with a caveman line inserted
# after bar's model line, restyled to match bar (brand label │ dim content).
# Wired by install.sh via settings.json → "statusLine".
# Degrades to whichever half is present: no caveman plugin → bar only,
# no claude-bar → raw badge only.

input=$(cat)

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Caveman badge: delegate to the plugin's own statusline script. Multiple
# cached plugin versions can coexist — pick the most recently modified one.
badge_script=""
for s in "$CFG"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
  [ -f "$s" ] || continue
  if [ -z "$badge_script" ] || [ "$s" -nt "$badge_script" ]; then
    badge_script="$s"
  fi
done
badge=""
[ -n "$badge_script" ] && badge=$(bash "$badge_script" 2>/dev/null)

# Resolve claude-bar: PATH first, then common npm-prefix locations (the
# statusline shell is non-login, so nvm/asdf/Homebrew paths may be missing).
bar_bin=""
if command -v claude-bar >/dev/null 2>&1; then
  bar_bin=claude-bar
else
  for c in "$APPDATA/npm/claude-bar" "$HOME/.npm-global/bin/claude-bar" \
           /opt/homebrew/bin/claude-bar /usr/local/bin/claude-bar \
           "$HOME/.asdf/shims/claude-bar" "$HOME"/.nvm/versions/node/*/bin/claude-bar; do
    [ -x "$c" ] && bar_bin="$c" && break
  done
fi

# Append effort level to model name ("Fable 5 · xhigh"). Per-session override
# comes in the stdin payload (.effort.level); fallback walks the same override
# order Claude Code uses (settings.local.json before settings.json). Only
# claude-bar consumes the patched payload — skip the jq work without it.
if [ -n "$bar_bin" ] && command -v jq >/dev/null 2>&1; then
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
if [ -n "$bar_bin" ]; then
  if command -v timeout >/dev/null 2>&1; then
    bar=$(printf '%s' "$input" | timeout 2 "$bar_bin" 2>/dev/null)
  else
    bar=$(printf '%s' "$input" | "$bar_bin" 2>/dev/null)
  fi
fi

# Restyle the badge as a bar-like line: "Caveman │ <mode> [│ savings]".
# Colors copied from bar's colors.js (BRAND / DIM truecolor). ESC is built
# with printf — BSD sed has no \x1b escape. If the badge format ever drifts,
# pass the plugin's output through verbatim instead of guessing.
cave_line=""
if [ -n "$badge" ]; then
  ESC=$(printf '\033')
  B="${ESC}[38;2;217;119;87m"; D="${ESC}[38;2;120;115;108m"; R="${ESC}[0m"
  plain=$(printf '%s' "$badge" | sed "s/${ESC}\[[0-9;]*m//g")
  case "$plain" in
    "[CAVEMAN]"*|"[CAVEMAN:"*)
      mode=$(printf '%s' "$plain" | sed -n 's/^\[CAVEMAN:\([A-Z0-9-]*\)\].*/\1/p' | tr '[:upper:]' '[:lower:]')
      [ -n "$mode" ] || mode=full
      savings=$(printf '%s' "$plain" | sed 's/^\[[^]]*\]//; s/^ *//')
      cave_line="${B}Caveman${R}${D} │ ${R}${D}${mode}${R}"
      [ -n "$savings" ] && cave_line="${cave_line}${D} │ ${R}${D}${savings}${R}"
      ;;
    *) cave_line="$badge" ;;
  esac
fi

if [ -n "$bar" ] && [ -n "$cave_line" ]; then
  first=$(printf '%s\n' "$bar" | head -n 1)
  rest=$(printf '%s\n' "$bar" | tail -n +2)
  printf '%s\n%s\n' "$first" "$cave_line"
  [ -n "$rest" ] && printf '%s\n' "$rest"
elif [ -n "$bar" ]; then
  printf '%s' "$bar"
elif [ -n "$cave_line" ]; then
  printf '%s\n' "$cave_line"
fi
