#!/usr/bin/env bash
# Claude Code statusline, rendered from the stdin payload alone — no network,
# no OAuth token (this replaced a vendored fork of @allthingsclaude/bar, which
# fetched the same numbers from a private endpoint with its own login).
# Lines: Model · Cache (context window) · Usage (5h/7d rate limits, present on
# subscription accounts) · active terse mode (ponytail/caveman badge) · Github.
# Wired by install.sh via settings.json → "statusLine". Needs jq (install.sh
# provides it); without it only a placeholder model line is printed.
# Check: bash tests/statusline.sh

input=$(cat)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

ESC=$(printf '\033')
B="${ESC}[38;2;217;119;87m"     # brand
BD="${ESC}[38;2;184;90;58m"     # brand dark    (≥ 75 %)
BL="${ESC}[38;2;240;196;174m"   # brand light   (≥ 25 %)
BLL="${ESC}[38;2;245;217;203m"  # brand lighter (< 25 %)
T="${ESC}[38;2;100;96;90m"      # bar track
D="${ESC}[38;2;120;115;108m"    # dim text
R="${ESC}[0m"
SEP="${D} │ ${R}"

# Label column: 8 chars, the width of "Ponytail" — keep in sync with the badge
# padding below so every line's separator lands in the same cell.
label() { printf '%s%-8s%s%s' "$B" "$1" "$R" "$SEP"; }

intensity() {
  if   (( $1 >= 75 )); then printf '%s' "$BD"
  elif (( $1 >= 50 )); then printf '%s' "$B"
  elif (( $1 >= 25 )); then printf '%s' "$BL"
  else                      printf '%s' "$BLL"
  fi
}

bar() {
  local pct=$1 w=10 f k
  f=$(( (pct * w + 50) / 100 )); (( f > w )) && f=$w
  printf '%s' "$(intensity "$pct")"
  for ((k = 0; k < f; k++)); do printf '█'; done
  printf '%s' "$T"
  for ((k = f; k < w; k++)); do printf '░'; done
  printf '%s' "$R"
}

fmt_tokens() {
  local t=$1
  if (( t >= 1000000 )); then
    local m=$(( t / 1000000 )) r=$(( (t % 1000000) / 100000 ))
    (( r > 0 )) && printf '%d.%dM' "$m" "$r" || printf '%dM' "$m"
  elif (( t >= 1000 )); then printf '%dk' $(( t / 1000 ))
  else printf '%d' "$t"
  fi
}

# Time left until an epoch-seconds instant, as "3d 4h" / "2h 12m" / "5m".
countdown() {
  local s=$(( $1 - $(date +%s) )) h m
  (( s <= 0 )) && { printf '0s'; return; }
  h=$(( s / 3600 )); m=$(( (s % 3600) / 60 ))
  if   (( h >= 24 )); then printf '%dd %dh' $(( h / 24 )) $(( h % 24 ))
  elif (( h > 0 ));   then printf '%dh %dm' "$h" "$m"
  elif (( m > 0 ));   then printf '%dm' "$m"
  else printf '<1m'
  fi
}

# ── Parse the payload (one jq pass) ──────────────────────────────────────────
model="?"; effort=""; cws=200000; pct=0; used=0; p5=""; r5=""; p7=""; r7=""; cwd=""
if command -v jq >/dev/null 2>&1; then
  # Unit separator, not tab: read collapses runs of whitespace IFS characters,
  # which would shift every field after an empty one (no effort, no cwd…).
  IFS=$'\x1f' read -r model effort cws pct used p5 r5 p7 r7 cwd < <(printf '%s' "$input" | jq -r '
    def pctOrEmpty: if . == null then "" else round end;
    [ (.model.display_name // "?"),
      (.effort.level // ""),
      (.context_window.context_window_size // 200000),
      (.context_window.used_percentage // 0 | floor),
      ((.context_window.current_usage // {})
        | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
      (.rate_limits.five_hour.used_percentage | pctOrEmpty),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage | pctOrEmpty),
      (.rate_limits.seven_day.resets_at // ""),
      (.workspace.current_dir // "")
    ] | map(tostring) | join("")' 2>/dev/null | tr -d '\r')   # jq on Windows ends lines with CRLF
  # Effort: the payload carries the live value; older Claude Code versions omit
  # it, so fall back to the same override order Claude Code uses.
  if [ -z "$effort" ]; then
    for f in "$CFG/settings.local.json" "$CFG/settings.json"; do
      [ -f "$f" ] || continue
      effort=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null | tr -d '\r')
      [ -n "$effort" ] && break
    done
  fi
fi
[ -n "$model" ] || model="?"

# ── Model ────────────────────────────────────────────────────────────────────
line_model="$(label Model)${B}${model}${R}"
[ -n "$effort" ] && line_model+="${D} · ${effort}${R}"

# ── Cache (context window) ───────────────────────────────────────────────────
line_cache=""
if command -v jq >/dev/null 2>&1; then
  line_cache="$(label Cache)${D}$(fmt_tokens "$used")/$(fmt_tokens "$cws")${R} [$(bar "$pct")] $(intensity "$pct")${pct}%${R}"
fi

# ── Usage (rate limits) — omitted when the payload has none ──────────────────
seg() {
  printf '%s%s ·%s [%s] %s%s%%%s %s· %s%s' \
    "$D" "$1" "$R" "$(bar "$2")" "$(intensity "$2")" "$2" "$R" "$D" "$(countdown "$3")" "$R"
}
line_usage=""
[ -n "$p5" ] && line_usage="$(seg Session "$p5" "${r5:-0}")"
if [ -n "$p7" ]; then
  [ -n "$line_usage" ] && line_usage+="${D} | ${R}"
  line_usage+="$(seg Week "$p7" "${r7:-0}")"
fi
[ -n "$line_usage" ] && line_usage="$(label Usage)${line_usage}"

# ── Mode badge: delegate to the active plugin's own statusline script ────────
# ponytail first, caveman as fallback (style-toggle.sh keeps at most one on, so
# the first non-empty badge wins). Several cached plugin versions can coexist —
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
# Restyle "[PONYTAIL]", "[PONYTAIL:ULTRA]", "[CAVEMAN:X] <savings>" as a
# bar-like line: "Ponytail │ On · Full [· savings]". Unknown format → verbatim.
line_mode=""
if [ -n "$badge" ]; then
  plain=$(printf '%s' "$badge" | sed "s/${ESC}\[[0-9;]*m//g")
  case "$plain" in
    "["[A-Z]*)
      name=$(printf '%s' "$plain" | sed -n 's/^\[\([A-Z]*\)[]:].*/\1/p' | tr '[:upper:]' '[:lower:]')
      mode=$(printf '%s' "$plain" | sed -n 's/^\[[A-Z]*:\([A-Z0-9-]*\)\].*/\1/p' | tr '[:upper:]' '[:lower:]')
      [ -n "$mode" ] || mode=full
      savings=$(printf '%s' "$plain" | sed 's/^\[[^]]*\]//; s/^ *//')
      line_mode="$(label "${name^}")${D}On · ${mode^}${R}"
      [ -n "$savings" ] && line_mode+="${D} · ${savings}${R}"
      ;;
    *) line_mode="$badge" ;;
  esac
fi

# ── Github: branch + live diff vs HEAD, cached 5 s per cwd ───────────────────
# Generated dirs are excluded: graphify background rebuilds keep them dirty
# mid-session until the Stop hook commits them, which would drown the real diff.
# ponytail: names hardcoded — this setup's only churn sources.
line_git=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cache="${TMPDIR:-/tmp}/statusline-git-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
  if [ -f "$cache" ] && (( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) < 5 )); then
    line_git=$(cat "$cache")
  elif git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -n "$branch" ] || branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      line_git="$(label Github)${B}⎇ ${branch}${R}"
      read -r added removed < <(git -C "$cwd" diff HEAD --numstat -- \
        ':(top,exclude)graphify-out' ':(top,exclude)vault' 2>/dev/null \
        | awk '{ a += $1; r += $2 } END { printf "%d %d", a, r }')
      (( added + removed > 0 )) && line_git+="${D} · ${R}${BL}+${added}${R} ${BD}-${removed}${R}"
    fi
    printf '%s' "$line_git" > "$cache" 2>/dev/null || true
  fi
fi

for l in "$line_model" "$line_cache" "$line_usage" "$line_mode" "$line_git"; do
  [ -n "$l" ] && printf '%s\n' "$l"
done
exit 0
