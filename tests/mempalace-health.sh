#!/usr/bin/env bash
# Self-check for the MemPalace parts of install.sh and session-start.sh after the
# outage of 2026-10-04: a `uv tool install --upgrade` made while a session's
# mempalace-mcp.exe was running deleted half the tool venv (uv removes the whole
# environment when it cannot replace a shim in use), the import of chromadb then
# failed for two days while install.sh kept printing "✓ MemPalace", and every
# hook hid the error. The functions are taken out of install.sh by name and run
# with stubs; every path they could touch (uv's tool dir, APPDATA, the config)
# points into the temp dir, so nothing here reaches a real venv or palace.
#
#   bash tests/mempalace-health.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }

# Read by the functions eval'd in below: exported so that shellcheck sees them
# used, and so that the stubs on PATH see the same values.
export RED='' GREEN='' YELLOW='' CYAN='' DIM='' BOLD='' RESET='' AUTO_YES=false VERBOSE=true
export TOOL_BIN_DIR="$T/bin" MEMPALACE_CONFIG="$T/config.json" MEMPALACE_PALACE="$T/palace"
export MEMPALACE_MODEL="embeddinggemma" MEMPALACE_OVERRIDES="$T/overrides.txt" MEMPALACE_STOP_WAIT=5
export APPDATA="$T/appdata"   # never the real one: the first version of test 5d ran a cleanup against it
mkdir -p "$TOOL_BIN_DIR" "$MEMPALACE_PALACE" "$T/stubs" "$APPDATA"

missing=0
for fn in _run_quiet _ok _ok_flush _detail _ask _is_yes _mempalace_config_set _mempalace_configured_model \
          _mempalace_set_write_routing _mempalace_diverged _mempalace_state _mempalace_set_palace_path \
          _mempalace_repair_divergence _mempalace_accel_extra _mempalace_daemon_stop _setup_mempalace _uv_tool_install \
          _tool_venv_root _tool_venv_python _tool_import_ok _tool_venv_filter _tool_venv_holders _tool_venv_kill_holders; do
  body="$(awk -v n="$fn" '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
  if [[ -z "$body" ]]; then echo "  FAIL  $fn not found in install.sh"; fail=$((fail + 1)); missing=1; continue; fi
  eval "$body"
done

# Stubs on PATH for everything the functions call outside install.sh.
export PATH="$T/stubs:$PATH"
stub() {  # stub <name> <body>: an executable on PATH
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/stubs/$1"; chmod +x "$T/stubs/$1"
}
stub jq "$(command -v jq) \"\$@\""   # the real jq, found before the stubs dir shadows anything

if (( missing )); then
  echo; echo "$pass passed, $fail failed"; exit 1
fi

# ── 1. The import probe decides, not `--version` ─────────────────────────────
echo "== import probe"
# A venv laid out as uv does off Windows: <uv tool dir>/<pkg>/bin/python.
root="$T/uvtools"; mkdir -p "$root/mempalace/bin"
stub uv "case \"\$1 \$2\" in 'tool dir') printf '%s\\n' '$root' ;; *) echo \"uv \$*\" >> '$T/uv.log' ;; esac"
_is_windows() { return 1; }
printf '#!/usr/bin/env bash\n[ -f "%s/import-ok" ]\n' "$T" > "$root/mempalace/bin/python"; chmod +x "$root/mempalace/bin/python"
rm -f "$T/import-ok"
if ! _tool_import_ok mempalace; then ok "a venv whose interpreter cannot import is not ok"; else ko "a venv whose interpreter cannot import is not ok"; fi
touch "$T/import-ok"
if _tool_import_ok mempalace; then ok "a venv whose interpreter imports is ok"; else ko "a venv whose interpreter imports is ok"; fi
if ! _tool_import_ok nothere; then ok "a tool with no venv is not ok"; else ko "a tool with no venv is not ok"; fi

# ── 2. _mempalace_state: broken comes first ──────────────────────────────────
echo "== _mempalace_state"
touch "$MEMPALACE_PALACE/chroma.sqlite3"
printf '{"embedding_model": "minilm"}\n' > "$MEMPALACE_CONFIG"   # a model mismatch on top
stub mempalace "echo 'repair-status cannot resolve the palace backend: No module named dotenv' >&2; exit 2"
rm -f "$T/import-ok"
[[ "$(_mempalace_state)" == broken ]] && ok "no import: broken, even with a model mismatch" || ko "no import: broken, even with a model mismatch (got $(_mempalace_state))"
touch "$T/import-ok"
[[ "$(_mempalace_state)" == mismatch ]] && ok "import ok, other model: mismatch" || ko "import ok, other model: mismatch (got $(_mempalace_state))"
printf '{"embedding_model": "embeddinggemma"}\n' > "$MEMPALACE_CONFIG"
stub mempalace "printf '  [drawers]\\n    status:         OK\\n'"
[[ "$(_mempalace_state)" == ok ]] && ok "import ok, same model, no DIVERGED: ok" || ko "import ok, same model, no DIVERGED: ok (got $(_mempalace_state))"
stub mempalace "printf '  [drawers]\\n    status:         DIVERGED\\n'"
[[ "$(_mempalace_state)" == diverged ]] && ok "DIVERGED in repair-status: diverged" || ko "DIVERGED in repair-status: diverged (got $(_mempalace_state))"

# ── 3. _setup_mempalace fails closed on a broken venv ────────────────────────
echo "== _setup_mempalace on a broken venv"
rm -f "$T/import-ok"
MEMPALACE_READY="unset"
out="$(_setup_mempalace 2>&1)"
[[ "$out" == *"✗"*"MemPalace"* ]] && ok "a red line names MemPalace" || ko "a red line names MemPalace: $out"
[[ "$out" != *"✓ MemPalace"* ]] && ok "no '✓ MemPalace'" || ko "no '✓ MemPalace': $out"
[[ "$out" == *"--reinstall"* ]] && ok "the line names the repair command" || ko "the line names the repair command: $out"
[[ "$out" != *"--overrides"* ]] && ok "no --overrides in it off Windows (the file exists for an accelerated build only)" || ko "no --overrides in it off Windows: $out"
# The function runs in this shell, so the gate it sets is visible here.
_setup_mempalace >/dev/null 2>&1
[[ "$MEMPALACE_READY" == false ]] && ok "MEMPALACE_READY=false" || ko "MEMPALACE_READY=false (got $MEMPALACE_READY)"

# ── 4. Write routing written for the daemon model ────────────────────────────
echo "== write routing"
printf '{}\n' > "$MEMPALACE_CONFIG"
_mempalace_set_write_routing prefer
[[ "$(jq -r '.write_routing.hooks' "$MEMPALACE_CONFIG" | tr -d '\r')" == require ]] && ok "hooks: require (never a direct write beside the daemon)" || ko "hooks: require (got $(jq -c .write_routing "$MEMPALACE_CONFIG"))"
[[ "$(jq -r '.write_routing.cli' "$MEMPALACE_CONFIG" | tr -d '\r')" == prefer ]] && ok "cli: prefer (mines may start the daemon)" || ko "cli: prefer (got $(jq -c .write_routing "$MEMPALACE_CONFIG"))"
[[ "$(jq -r '.write_routing.default' "$MEMPALACE_CONFIG" | tr -d '\r')" == prefer ]] && ok "default: prefer" || ko "default: prefer"

# ── 5. _setup_mempalace on a healthy palace brings the daemon back ───────────
echo "== _setup_mempalace on a healthy palace"
touch "$T/import-ok"; printf '{"embedding_model": "embeddinggemma"}\n' > "$MEMPALACE_CONFIG"
stub mempalace "echo \"\$*\" >> '$T/mp.log'; case \"\$1\" in repair-status) printf '  [drawers]\\n    status:         OK\\n' ;; esac; exit 0"
rm -f "$T/mp.log"; MEMPALACE_READY="unset"
_setup_mempalace >/dev/null 2>&1
[[ "$MEMPALACE_READY" == true ]] && ok "MEMPALACE_READY=true" || ko "MEMPALACE_READY=true (got $MEMPALACE_READY)"
grep -q '^daemon start' "$T/mp.log" 2>/dev/null && ok "the daemon stopped for the upgrade is started again" || ko "the daemon stopped for the upgrade is started again: $(cat "$T/mp.log" 2>/dev/null)"

# ── 6. _mempalace_daemon_stop waits for the daemon to let go, bounded ────────
echo "== _mempalace_daemon_stop"
# The holder list shows the daemon for the first two calls, then nothing.
printf '0\n' > "$T/stop-calls"
_tool_venv_holders() {
  local n; n=$(cat "$T/stop-calls"); echo $((n + 1)) > "$T/stop-calls"
  (( n < 2 )) && printf '  29820  C:\\Python313\\python.exe -m mempalace.daemon serve --palace x\n'
  return 0
}
stub mempalace "echo \"\$*\" >> '$T/mp.log'"
stub sleep ':'   # no real waiting
rm -f "$T/mp.log"
_mempalace_daemon_stop
grep -q '^daemon stop' "$T/mp.log" && ok "daemon stop is sent" || ko "daemon stop is sent"
[[ "$(cat "$T/stop-calls")" == 3 ]] && ok "it waits until the daemon is no longer a holder" || ko "it waits until the daemon is no longer a holder (holders asked $(cat "$T/stop-calls") times)"
printf '0\n' > "$T/stop-calls"
_tool_venv_holders() { local n; n=$(cat "$T/stop-calls"); echo $((n + 1)) > "$T/stop-calls"; printf '  1  python.exe -m mempalace.daemon serve\n'; }
_mempalace_daemon_stop; rc=$?
[[ $rc -eq 0 && "$(cat "$T/stop-calls")" == "$MEMPALACE_STOP_WAIT" ]] && ok "a daemon that never lets go: gives up after MEMPALACE_STOP_WAIT, returns 0" || ko "a daemon that never lets go: gives up after MEMPALACE_STOP_WAIT, returns 0 (rc=$rc, asked $(cat "$T/stop-calls"))"
rm -f "$T/stubs/sleep"

# ── 7. _uv_tool_install looks for holders before it calls uv ─────────────────
echo "== _uv_tool_install"
_is_windows() { return 0; }
_tool_venv_python() { printf '%s\n' "$root/mempalace/bin/python"; }   # the probe above, whatever the tool
_tool_venv_kill_holders() { echo "kill $1" >> "$T/kill.log"; }
_ask() { return 1; }   # the kill is declined
holders_out=""
_tool_venv_holders() { printf '%s' "$holders_out"; }

# a. holder present, kill declined, the installed copy imports: skipped, carries on
rm -f "$T/uv.log" "$T/kill.log"; touch "$T/import-ok"
holders_out=$'  18812  C:\\Python313\\python.exe C:\\Users\\u\\.local\\bin\\mempalace-mcp.exe'
out="$(_uv_tool_install mempalace '[dml]' --overrides "$MEMPALACE_OVERRIDES" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "holder, declined, imports: returns 0" || ko "holder, declined, imports: returns 0 (got $rc)"
[[ ! -f "$T/uv.log" ]] && ok "uv is not called" || ko "uv is not called: $(cat "$T/uv.log")"
[[ ! -f "$T/kill.log" ]] && ok "nothing is killed" || ko "nothing is killed"
[[ "$out" == *"⚠"*"skipped"* ]] && ok "a visible warning says the upgrade was skipped" || ko "a visible warning says the upgrade was skipped: $out"

# b. holder present, kill declined, the installed copy does not import: 1
rm -f "$T/uv.log" "$T/import-ok"
out="$(_uv_tool_install mempalace '[dml]' 2>&1)"; rc=$?
[[ $rc -eq 1 ]] && ok "holder, declined, no import: returns 1" || ko "holder, declined, no import: returns 1 (got $rc)"
[[ ! -f "$T/uv.log" ]] && ok "uv is still not called" || ko "uv is still not called"

# c. no holder: one `uv tool install --upgrade`, then the probe
rm -f "$T/uv.log"; holders_out=""; touch "$T/import-ok"
_uv_tool_install mempalace '[dml]' --overrides "$MEMPALACE_OVERRIDES" >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "no holder: returns 0" || ko "no holder: returns 0 (got $rc)"
[[ "$(grep -c . "$T/uv.log" 2>/dev/null)" == 1 ]] && ok "uv called once" || ko "uv called once: $(cat "$T/uv.log" 2>/dev/null)"
grep -q -- 'tool install mempalace\[dml\] --overrides .* --upgrade' "$T/uv.log" && ok "with --upgrade, the spec and the overrides" || ko "with --upgrade, the spec and the overrides: $(cat "$T/uv.log")"
if ! grep -q -- '--reinstall' "$T/uv.log"; then ok "no --reinstall when the venv imports" ; else ko "no --reinstall when the venv imports"; fi

# d. no holder, the upgrade leaves a venv that does not import: one --reinstall
rm -f "$T/uv.log" "$T/import-ok"
_uv_tool_install graphifyy >/dev/null 2>&1; rc=$?
[[ "$(grep -c -- '--reinstall' "$T/uv.log" 2>/dev/null)" == 1 ]] && ok "a broken venv after the upgrade gets one --reinstall" || ko "a broken venv after the upgrade gets one --reinstall: $(cat "$T/uv.log" 2>/dev/null)"
[[ $rc -ne 0 ]] && ok "still broken after it: non-zero" || ko "still broken after it: non-zero"
[[ -d "$APPDATA" ]] && ok "the cleanup stayed inside the stubbed tool dir (APPDATA untouched)" || ko "the cleanup stayed inside the stubbed tool dir (APPDATA untouched)"

# e. the holder query names the venv (from `uv tool dir`) and the ~/.local/bin shims of the tool
unset -f _tool_venv_holders
body="$(awk -v n=_tool_venv_holders '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"; eval "$body"
stub uv "case \"\$1 \$2\" in 'tool dir') printf '%s\\n' 'D:\\uv\\tools' ;; esac"   # not under APPDATA: UV_TOOL_DIR moved it
stub powershell.exe "printf '%s\\n' \"\$*\" > '$T/ps.log'"
stub cygpath "printf '%s\\n' 'C:\\Users\\u\\.local\\bin'"
_tool_venv_holders mempalace >/dev/null 2>&1
if grep -qF 'D:\uv\tools\mempalace\*' "$T/ps.log" 2>/dev/null; then ok "the query matches the venv path uv reports, not %APPDATA%" ; else ko "the query matches the venv path uv reports, not %APPDATA%: $(cat "$T/ps.log" 2>/dev/null)"; fi
if grep -qF '.local\bin\mempalace*' "$T/ps.log" 2>/dev/null; then ok "the query matches the tool's shims under ~/.local/bin" ; else ko "the query matches the tool's shims under ~/.local/bin: $(cat "$T/ps.log" 2>/dev/null)"; fi
_tool_venv_holders graphifyy >/dev/null 2>&1
if grep -qF '.local\bin\graphify*' "$T/ps.log" 2>/dev/null; then ok "graphifyy's shims are graphify*" ; else ko "graphifyy's shims are graphify*: $(cat "$T/ps.log" 2>/dev/null)"; fi
# f. a PowerShell that fails reads as no holder, and does not fail the caller
stub powershell.exe "exit 1"
out="$(_tool_venv_holders mempalace)"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "a failing PowerShell: no holder, status 0 (set -e in install.sh)" || ko "a failing PowerShell: no holder, status 0 (rc=$rc, out=$out)"

# ── 8. session-start.sh: starts the daemon, says when MemPalace is down ──────
echo "== session-start.sh"
SS="$REPO_DIR/scripts/session-start.sh"
stub timeout 'shift; exec "$@"'
mkdir -p "$T/repo"; cd "$T/repo" || exit 1
export HF_HUB_OFFLINE=1   # what settings.json gives every hook
# The harness check session-start.sh runs (scripts/harness-drift.sh): a scratch
# config dir whose pointer names an empty throwaway clone with its origin ref,
# so nothing drifts here and the output stays the plain text asserted below.
export CLAUDE_CONFIG_DIR="$T/cfg"; mkdir -p "$T/cfg" "$T/clone"
git -C "$T/clone" init -q -b main && git -C "$T/clone" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$T/clone" update-ref refs/remotes/origin/main HEAD
printf '%s\n' "$T/clone" > "$T/cfg/claude-config.path"
# a. daemon down, wake-up dies at import: one capped line, exit 0, daemon started once
stub mempalace "echo \"\$* HF=\${HF_HUB_OFFLINE:-unset}\" >> '$T/mp.log'
case \"\$1 \$2\" in
  'daemon start') exit 0 ;;
  'wake-up '*|'wake-up') printf 'Traceback (most recent call last):\\n  File x\\nModuleNotFoundError: No module named '\"'\"'dotenv'\"'\"' %0500d\\n' 0 >&2; exit 1 ;;
esac"
rm -f "$T/mp.log"
out="$(bash "$SS")"; rc=$?
[[ $rc -eq 0 ]] && ok "exits 0 whatever happens" || ko "exits 0 whatever happens (got $rc)"
[[ "$out" == *"MemPalace is down"* ]] && ok "says MemPalace is down" || ko "says MemPalace is down: $out"
line="$(printf '%s\n' "$out" | grep -A1 -m1 'MemPalace is down' | tail -1)"   # the detail under the heading
[[ -n "$line" && ${#line} -le 200 ]] && ok "the detail line is capped (${#line} chars)" || ko "the detail line is capped (${#line} chars)"
[[ "$line" == *"ModuleNotFoundError"* ]] && ok "the line quotes the error" || ko "the line quotes the error: $line"
[[ "$line" == *"install.sh"* ]] && ok "the line says what to run" || ko "the line says what to run: $line"
[[ "$(grep -c '^daemon start' "$T/mp.log")" == 1 ]] && ok "daemon start asked once (a no-op when it already runs)" || ko "daemon start asked once: $(cat "$T/mp.log")"
! grep -q '^daemon status' "$T/mp.log" && ok "no separate daemon status call" || ko "no separate daemon status call"
grep -q '^daemon start HF=unset' "$T/mp.log" && ok "the daemon starts without HF_HUB_OFFLINE" || ko "the daemon starts without HF_HUB_OFFLINE: $(grep '^daemon start' "$T/mp.log")"
# b. daemon up, wake-up fine and empty: nothing about MemPalace
stub mempalace "echo \"\$*\" >> '$T/mp.log'; exit 0"
rm -f "$T/mp.log"
out="$(bash "$SS")"
[[ "$out" != *"MemPalace"* ]] && ok "healthy and empty diary: silent" || ko "healthy and empty diary: silent: $out"
# c. wake-up times out (124): slow is not down
stub mempalace "case \"\$1 \$2\" in 'daemon start') exit 0 ;; *) exit 124 ;; esac"
out="$(bash "$SS")"
[[ "$out" != *"MemPalace is down"* ]] && ok "a timeout is not reported as down" || ko "a timeout is not reported as down: $out"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
