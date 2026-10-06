#!/usr/bin/env bash
# Self-check that every workflow and every gate template is YAML GitHub can load. A
# workflow with a syntax error is registered under its path, its runs fail with
# "workflow file issue", and no check ever reaches the pull request: nothing requires
# a check that does not exist, so the PR merges with the gate never run. That is how
# papers-helper #16 merged on 2026-10-06, a `: ` inside a one-line `run:` of
# quality-frontend.yml. Parses with js-yaml through npx. Run after touching
# .github/workflows/ or templates/gates/:
#
#   bash tests/workflows-yaml.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
command -v npx >/dev/null 2>&1 || { echo "SKIP: npx (node) not installed"; exit 0; }

pass=0
fail=0
for f in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/templates/gates/*.yml; do
  rel=${f#"$REPO_DIR"/}
  if err=$(npx --yes js-yaml@4 "$f" 2>&1 >/dev/null); then
    echo "  PASS  $rel"
    pass=$((pass + 1))
  else
    echo "  FAIL  $rel: $(printf '%s\n' "$err" | grep -m1 -E 'YAMLException|Error' || echo "$err" | tail -1)"
    fail=$((fail + 1))
  fi
done

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
