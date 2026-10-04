#!/usr/bin/env bash
# Self-check for install.sh's --only switch: the usage names both halves, a bad
# value is refused before anything runs, and _in_scope answers the way the two
# guarded blocks expect under each of the three scopes. Run after touching the
# argument parsing or either `if _in_scope` block:
#
#   bash tests/install-scope.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"

pass=0
fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL  $1"; fail=$((fail + 1)); }

# -h exits inside the argument loop, before the upstream sync or any install step.
usage="$(bash "$INSTALL" -h 2>&1)"
if [[ "$usage" == *"--only claude"* && "$usage" == *"--only repos"* ]]; then
  ok "-h documents both scopes"
else
  ko "-h does not document both scopes: $usage"
fi

# An unknown scope must die in the parser: install.sh has side effects from the
# upstream sync onward, so the check cannot wait until the guarded blocks.
for bad in "--only bogus" "--only=bogus" "--only"; do
  # shellcheck disable=SC2086  # deliberate split: the argument list is the case under test
  out="$(bash "$INSTALL" $bad 2>&1)"
  rc=$?
  if [[ $rc -eq 1 && "$out" == *"claude or repos"* ]]; then
    ok "'$bad' is refused with exit 1"
  else
    ko "'$bad' exited $rc: $out"
  fi
done

# The guard itself, taken straight out of install.sh by name.
body="$(awk '$0 == "_in_scope() {" {f=1} f{print} f&&/^}/{exit}' "$INSTALL")"
[[ -n "$body" ]] || { echo "FAIL: _in_scope not found in install.sh"; exit 1; }
eval "$body"

check() {
  local scope="$1" half="$2" expected="$3" rc
  # shellcheck disable=SC2034  # read by the eval'd _in_scope
  SCOPE="$scope"
  if _in_scope "$half"; then rc=0; else rc=1; fi
  if [[ $rc -eq $expected ]]; then
    ok "SCOPE=$scope: the $half block $([[ $rc -eq 0 ]] && echo runs || echo 'is skipped')"
  else
    ko "SCOPE=$scope: _in_scope $half returned $rc, expected $expected"
  fi
}
check all claude 0
check all repos 0
check claude claude 0
check claude repos 1
check repos claude 1
check repos repos 0

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
