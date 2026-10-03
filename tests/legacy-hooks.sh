#!/usr/bin/env bash
# Self-check for install.sh's cc-safe-setup cleanup: the five dropped hooks must
# be gone from the deployed hooks/ directory and from the deployed settings.json
# after every install, and a leftover must fail loudly — a silent leftover is
# how comment-strip.sh corrupted heredocs for months (docs/pitfall.md). Run after
# touching _remove_legacy_cc_safe_hooks or _verify_legacy_cc_safe_hooks_removed:
#
#   bash tests/legacy-hooks.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# Read by the functions eval'd in below, which shellcheck cannot see.
# shellcheck disable=SC2034
RED='' RESET=''
CLAUDE_DIR="$T/claude"
mkdir -p "$CLAUDE_DIR/hooks"

# The array and the two functions, taken straight out of install.sh by name.
eval "$(grep -m1 '^LEGACY_CC_SAFE_HOOKS=(' "$REPO_DIR/install.sh")"
for fn in _remove_legacy_cc_safe_hooks _verify_legacy_cc_safe_hooks_removed; do
  body="$(awk -v n="$fn" '$0 == n"() {" {f=1} f{print} f&&/^}/{exit}' "$REPO_DIR/install.sh")"
  [[ -n "$body" ]] || { echo "FAIL: $fn not found in install.sh"; exit 1; }
  eval "$body"
done

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }

# Red: a machine as cc-safe-setup left it — all eight hook files on disk, one of
# the dropped ones still registered in settings.json.
for h in destructive-guard branch-guard secret-guard comment-strip syntax-check context-monitor cd-git-allow api-error-alert; do
  : > "$CLAUDE_DIR/hooks/$h.sh"
done
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \\"%s/hooks/comment-strip.sh\\""}]}]}}\n' \
  "$CLAUDE_DIR" > "$CLAUDE_DIR/settings.json"
if _verify_legacy_cc_safe_hooks_removed 2>/dev/null; then
  ko "leftovers on disk and in settings.json go unnoticed"
else
  ok "leftovers on disk and in settings.json are reported"
fi

# Removing the files is not enough while settings.json still names one.
_remove_legacy_cc_safe_hooks
for h in "${LEGACY_CC_SAFE_HOOKS[@]}"; do
  [[ -e "$CLAUDE_DIR/hooks/$h.sh" ]] && ko "$h.sh survived the removal"
done
for h in destructive-guard branch-guard secret-guard; do
  [[ -e "$CLAUDE_DIR/hooks/$h.sh" ]] || ko "$h.sh (a kept guard) was removed"
done
ok "the five dropped hooks are removed, the three kept guards stay"
if _verify_legacy_cc_safe_hooks_removed 2>/dev/null; then
  ko "a stale settings.json entry goes unnoticed"
else
  ok "a stale settings.json entry is reported"
fi
msg="$(_verify_legacy_cc_safe_hooks_removed 2>&1 || true)"
if [[ "$msg" == *"settings.json:comment-strip"* ]]; then
  ok "the report names the leftover"
else
  ko "the report does not name the leftover: $msg"
fi

# Green: the repo's settings.json (what install.sh copies) over a clean hooks/.
cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
if _verify_legacy_cc_safe_hooks_removed; then
  ok "a clean install passes"
else
  ko "a clean install is reported as dirty"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
