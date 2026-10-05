#!/usr/bin/env bash
# Self-check that both READMEs describe the repo as git has it: every path in the
# "## Structure" tree is tracked, every tracked entry of a directory the tree
# enumerates is in the tree, and the slash-command table names exactly the files
# in commands/. The tree once kept agents/ and templates/context/ for months after
# both were gone, and listed a local-only docs file; nothing noticed. Reads
# `git ls-files`, not the disk, so an untracked local file cannot make it pass.
# Run after adding, moving or removing a file:
#
#   bash tests/readme-structure.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_DIR" || exit 1

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

tracked="$(git ls-files)"
tracked_exists() {  # "dir/" -> a tracked file under it; "file" -> tracked as is
  case $1 in
    */) grep -q "^$1" <<<"$tracked" ;;
    *)  grep -qxF "$1" <<<"$tracked" ;;
  esac
}

# The fenced block right after "## Structure", one line per entry. Each entry line
# is depth × 4 columns of "│   " or "    ", then "├── " or "└── ", the name, and an
# optional "# comment". Names of directories end with "/", so the path of an entry
# is the plain concatenation of its ancestors' names and its own.
tree_paths() {  # <readme> -> one tracked-relative path per line
  local line depth name path i
  local stack=()
  awk '/^## Structure/{s=1; next} s && /^```/{c++; next} s && c==1' "$1" \
  | while IFS= read -r line; do
      depth=0
      while :; do
        case $line in
          "│   "*) line=${line#"│   "}; depth=$((depth + 1)) ;;
          "    "*) line=${line#"    "}; depth=$((depth + 1)) ;;
          *) break ;;
        esac
      done
      case $line in
        "├── "*) name=${line#"├── "} ;;
        "└── "*) name=${line#"└── "} ;;
        *) continue ;;
      esac
      name=${name%%#*}
      name=${name%"${name##*[! ]}"}
      stack[depth]=$name
      path=""
      for ((i = 0; i < depth; i++)); do path+=${stack[i]}; done
      echo "$path$name"
    done
}

for readme in README.md README.fr.md; do
  paths="$(tree_paths "$readme")"
  [[ -n $paths ]] || { bad "$readme: no entries found under ## Structure"; continue; }

  # 1. Every path in the tree is tracked.
  missing=0
  while IFS= read -r p; do
    tracked_exists "$p" || { bad "$readme: tree lists $p, not tracked"; missing=$((missing + 1)); }
  done <<<"$paths"
  [[ $missing -eq 0 ]] && ok "$readme: every tree entry is tracked"

  # 2. Every tracked entry of a directory the tree enumerates (the parent of at
  #    least one entry) is in the tree, as itself or as the first segment of a
  #    deeper entry. A directory listed without children is a leaf: not checked.
  stray=0
  while IFS= read -r dir; do
    while IFS= read -r entry; do
      [[ -n $entry ]] || continue
      found=0
      while IFS= read -r p; do
        [[ $p == "$dir$entry" || $p == "$dir$entry/"* ]] && { found=1; break; }
      done <<<"$paths"
      [[ $found -eq 1 ]] || { bad "$readme: $dir$entry is tracked but not in the tree"; stray=$((stray + 1)); }
    done < <(git ls-files -- "$dir" | sed "s|^$dir||" | cut -d/ -f1 | sort -u)
  done < <(sed 's|/$||; s|[^/]*$||' <<<"$paths" | grep . | sort -u)
  [[ $stray -eq 0 ]] && ok "$readme: every tracked entry of an enumerated directory is in the tree"

  # 3. The slash-command table and commands/*.md name the same set.
  table="$(sed -n 's/^| `\/\([a-z-]*\)`.*/\1/p' "$readme" | sort)"
  files="$(git ls-files -- commands | sed 's|^commands/||; s|\.md$||' | sort)"
  if [[ $table == "$files" ]]; then
    ok "$readme: the command table matches commands/"
  else
    bad "$readme: command table and commands/ differ:"
    diff <(echo "$table") <(echo "$files") | sed 's/^/        /'
  fi
done

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
