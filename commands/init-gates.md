---
description: 'Installs the architecture gates (import cycles + layer contracts) in the current repo: proposes the layers, waits for the owner, then creates configs, baselines and CI callers on a branch with a PR.'
argument-hint: '[backend dir and/or frontend dir, or empty to detect them]'
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion, Bash(git status:*), Bash(git fetch:*), Bash(git switch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git log:*), Bash(git diff:*), Bash(gh pr create:*), Bash(uv run:*), Bash(npx:*), Bash(ls:*), Bash(cat:*)
# Only a human may start this command: hooks/protect-gates.js lets Claude create gate files that do not exist yet only while the latest typed message is /init-gates.
disable-model-invocation: true
---

# Install the architecture gates

Target: "$ARGUMENTS" (empty = detect).

The gate logic lives in claude-config (`gates/python/check_imports.py`, `.github/workflows/arch-gates.yml`, pinned at a tag). This command only creates the repo's **declarations**: its layers, its baselines and two short CI callers. Semantics, identical on both sides: runtime imports only, direct edges, module-level cycles, a module in no layer is an error.

**The protected-file exemption.** While the latest message the owner typed is `/init-gates`, `protect-gates` lets you **create** a gate file that does not exist yet (Write to an absent path, or a shell redirect to one). Changing or deleting an existing one stays blocked, and so does `--update-baseline`. Consequences:

- Ask every question with **AskUserQuestion**: its answer comes back as a tool result, so `/init-gates` stays the latest typed message. If the owner types a free reply instead, the exemption ends — say so and ask them to run `/init-gates` again.
- Write each gate file **once**, in its final form. Draft and iterate in the scratchpad, never in the repo.

## 1. Preconditions — stop and report if one fails

Read-only until every check below has passed: stopping must leave the owner exactly where they were.

- `rtk git status`: the tree is clean.
- None of these exist yet: `arch-gates.json`, `import-cycles-baseline.json`, `import-layers-baseline.json`, `.dependency-cruiser.cjs`, `.dependency-cruiser-known-violations.json`, `.github/workflows/arch-gates.yml`. An existing one means the repo already has gates: report it, change nothing.
- Detect the sides (or take them from the arguments):
  - **Python**: a directory with `pyproject.toml` and a package directory under it (the one the app imports from, e.g. `app/`).
  - **Frontend**: a directory with `package.json`, `src/` and the tsconfig whose `include` covers `src` (check `references` when `tsconfig.json` has no `include`).
- Only then: `rtk git fetch` and `git switch -c ci/arch-gates origin/main`.

## 2. Read the real import graph

**Python** — group modules into areas (one area per top-level module or subpackage of the package) and count the edges between areas, from the runtime graph:

```bash
uv run --no-project --with grimp==3.14 python - <<'PY'
import collections, sys, grimp
sys.path.insert(0, "<python dir>")
g = grimp.build_graph("<package>", exclude_type_checking_imports=True, cache_dir=None)
area = lambda m: ".".join(m.split(".")[:2])
edges = collections.Counter((area(a), area(b)) for a in g.modules for b in g.find_modules_directly_imported_by(a) if area(a) != area(b))
for (a, b), n in sorted(edges.items()): print(f"{a} -> {b}  ({n})")
PY
```

A namespace package (a directory of `.py` files without `__init__.py`) is invisible to `grimp.build_graph("<package>")`: list them with `ls` and pass each one as an extra root, as `check_imports.py` does.

**Frontend** — folder-level edges under `src/`, with the pinned versions (runtime imports only: `tsPreCompilationDeps` is off unless the flag is passed; collapse one level deeper, `"^src/[^/]+/[^/]+"`, to see inside a big folder):

```bash
cd <frontend dir> && npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --no-config --ts-config <tsconfig> --include-only "^src" --collapse "^src/[^/]+" --output-type text
```

## 3. Propose the layers — then wait

Order the areas from the lowest (imports nothing of the app: types, config, constants) to the highest (composition root: `main`, `App.tsx`). Put areas that import each other in the **same** layer. Aim for the order in which the fewest edges go up; every upward edge left is debt the baseline will freeze.

Show the owner, per side:

- the layers, lowest first, with the areas in each;
- the upward edges that would be frozen (`a -> b (n imports)`), and the import cycles if any;
- anything you could not classify and why.

Then ask with **AskUserQuestion**: "Approve these layers?" with options *Approve*, *Change them* (the owner writes the change in "Other"), *Stop*. Iterate until *Approve* or *Stop*. Never create a gate file before *Approve*.

## 4. Create the declarations — once each, in final form

**Python** — `<python dir>/arch-gates.json`: the package and the approved layers, in the format the header of `check_imports.py` gives (`cat "$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"`). The root package entry covers only itself: list every top-level module and subpackage explicitly.

Then the baselines, created and never overwritten by the script itself:

```bash
gates="$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"
uv run --no-project --with grimp==3.14 python "$gates" cycles --config <python dir>/arch-gates.json --init-baseline
uv run --no-project --with grimp==3.14 python "$gates" layers --config <python dir>/arch-gates.json --init-baseline
```

Exit 2 on `layers` means a module in no layer: the proposal missed it. Stop, report, and start over from step 3 (the config already exists: the owner deletes it, or runs `/init-gates` on a fresh branch).

**Frontend** — `<frontend dir>/.dependency-cruiser.cjs` from `~/.claude/templates/gates/dependency-cruiser.cjs`: fill `LAYERS` with the approved layers (one array of path regexes per layer, matched right after `src/`, e.g. `'utils/'`, `'(App|main)\\.tsx$'`) and set `tsConfig.fileName` to the tsconfig found in step 1. Change nothing else. Then the baseline:

```bash
cd <frontend dir> && npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --config .dependency-cruiser.cjs --output-type baseline > .dependency-cruiser-known-violations.json
```

**CI** — `.github/workflows/arch-gates.yml` from `~/.claude/templates/gates/arch-gates.yml`, keeping only the `with:` lines of the sides the repo has, with their real paths. Also `.github/workflows/baseline-ratchet.yml` from `~/.claude/templates/gates/baseline-ratchet.yml` if the repo has no ratchet caller yet.

## 5. Prove it — green, red on the fragile case, green

Run the gates exactly as CI does (commands in step 4, without `--init-baseline`; frontend with `--ignore-known`): all green. Then, per side, create one throwaway file that adds a **new** upward import (frontend: through the tsconfig path alias if the repo has one — that is the edge a missing `tsConfig` would silently drop), run the gate, show it red with the violation named, delete the file, run it again: green. `rtk git status` must show no leftover.

## 6. Branch, commit, PR — then hand over

- Commit only the files of step 4 on `ci/arch-gates` (Conventional Commits, `ci(gates): …`), `rtk git push -u origin ci/arch-gates`, `gh pr create` with: the approved layers, the frozen debt (entries per baseline), the red/green proof.
- Tell the owner what only they can do:
  1. the PR's `ratchet / ratchet` check is red **by design**: every baseline is new, so it counts as growth. Setting the `baseline-update` label is how they accept the frozen debt;
  2. once the checks have run, make `arch / python` and/or `arch / frontend` (and `ratchet / ratchet`) required on `main` — offer to do it with their OK;
  3. merging is theirs.
- Never merge, never set the label, never touch a gate file outside this flow.
