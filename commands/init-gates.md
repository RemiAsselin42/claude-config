---
description: 'Installs the gates in the current repo: import cycles + layer contracts, complexity + duplication, mutation testing on the Python side. Proposes layers, thresholds and the mutation target, waits for the owner, then creates configs, baselines and CI callers on a branch with a PR.'
argument-hint: '[backend dir and/or frontend dir, or empty to detect them]'
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion, Bash(git status:*), Bash(git fetch:*), Bash(git switch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git log:*), Bash(git diff:*), Bash(gh pr create:*), Bash(uv run:*), Bash(npx:*), Bash(npm ci:*), Bash(pnpm install:*), Bash(yarn install:*), Bash(corepack:*), Bash(ls:*), Bash(cat:*)
# Only a human may start this command: hooks/protect-gates.js lets Claude create gate files that do not exist yet only while the latest typed message is /init-gates.
disable-model-invocation: true
---

# Install the architecture gates

Target: "$ARGUMENTS" (empty = detect).

The gate logic lives in claude-config, pinned at a tag: `gates/python/check_imports.py` with `arch-gates-python.yml` and `arch-gates-frontend.yml` (import cycles and layer contracts), `gates/python/check_quality.py` with `quality-python.yml` and `quality-frontend.yml` (cyclomatic complexity and duplication), `gates/python/check_mutation.py` with `mutation-gate.yml` (mutation testing, Python only). This command only creates the repo's **declarations**: layers, baselines and short CI callers; the thresholds live in the callers and the mutation target in `pyproject.toml`. Architecture semantics, identical on both sides: runtime imports only, direct edges, module-level cycles, a module in no layer is an error. Three families, each installed as a whole or not at all; a repo that already has one family gets only the others.

**The protected-file exemption.** While the latest message the owner typed is `/init-gates`, `protect-gates` lets you **create** a gate file that does not exist yet (Write to an absent path, or a shell redirect to one). Changing or deleting an existing one stays blocked, and so does `--update-baseline`. Consequences:

- Ask every question with **AskUserQuestion**: its answer comes back as a tool result, so `/init-gates` stays the latest typed message. If the owner types a free reply instead, the exemption ends — say so and ask them to run `/init-gates` again (that works only while nothing has been created yet; once step 5 has begun, see the last rule of step 7).
- Write each gate file **once**, in its final form. Draft and iterate in the scratchpad, never in the repo.

## 1. Preconditions — stop and report if one fails

Read-only until every check below has passed: stopping must leave the owner exactly where they were.

- `rtk git status`: the tree is clean.
- Which families the repo already has, from its files: **architecture** (`arch-gates.json`, `import-cycles-baseline.json`, `import-layers-baseline.json`, `.dependency-cruiser.cjs`, `.dependency-cruiser-known-violations.json`, `.github/workflows/arch-gates.yml`), **quality** (`complexity-baseline.json`, `duplication-baseline.json`, `.github/workflows/quality-gates.yml`), **mutation** (`mutation-baseline.json`, `.github/workflows/mutation-gate.yml`, a `[tool.mutmut]` section in `pyproject.toml`). A family with any of its files present is installed: report it and leave every file of it alone; only the absent families go on. All three present: stop, there is nothing to do.
- Detect the sides (or take them from the arguments):
  - **Python**: a directory with `pyproject.toml` and a package directory under it (the one the app imports from, e.g. `app/`).
  - **Frontend**: a directory with `package.json`, `src/` and the tsconfig whose `include` covers `src` (check `references` when `tsconfig.json` has no `include`).
- **Detect the repo's own analyzers**: Fallow (`.fallowrc.json`, `fallow.toml`), knip (`knip.json*`, `knip.ts`, a `knip` key in `package.json`), depcheck (`.depcheckrc*`), and any CI job that runs one (`grep -ril 'fallow\|knip\|depcheck' .github/workflows`). They report a created `.dependency-cruiser.cjs` as an unused file (nothing imports a config), and their config is a check you never edit (CLAUDE.md, engineering rules). Note them: step 4 names the line the owner will add, step 7 hands it over.
- Only then: `rtk git fetch` and `git switch -c ci/gates origin/main`.

## 2. Find the boundaries first — before reading the graph

Steps 2 to 4 are the architecture family; when it is already installed, go to step 4b.

The gates exist to hold the boundaries the code must never cross. Fitting the current graph comes second: an order chosen because it gives zero violations can leave the one rule that matters unguarded (in a Figma plugin, sandbox code importing a React panel).

- **Entry points and runtimes**, from the build and deploy configuration, never from folder names alone: `package.json` (`main`, `module`, `exports`, `bin`), bundler inputs (`vite.config.*`, `webpack.config.*`, `rollup.config.*`), extension or plugin manifests (`manifest.json`: main vs UI), `new Worker(...)`, framework conventions (Next.js `app/` server vs `'use client'`), `pyproject.toml` `[project.scripts]`, `Dockerfile`, `Procfile`, CLI entry modules. Each separate runtime (browser, server, sandbox, worker, CLI) is a boundary.
- **Other boundaries the repo already shows**: domain logic vs I/O adapters, server-only code (secrets, database) vs client code, generated code.
- Write each one as an **invariant**: `<A> must never import <B>` — one line, with the file that proves it (e.g. `manifest.json: "main": dist/code.js, "ui": dist/index.html`). No boundary found is a valid answer: say so, and the layers are then plain dependency order.

## 3. Read the real import graph

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

**Mixed areas.** The folder-level view hides folders that straddle a boundary. For every area that touches one, look one level deeper (`--collapse "^src/<area>/[^/]+"`, or per module on the Python side): an area whose files are imported from both sides of a boundary, or import both sides, is **mixed** — e.g. a `features/<x>/` holding both the logic the sandbox runs and the panel the UI renders. Split it by file before proposing anything.

## 4. Draft, probe, then propose — and wait

**Draft in the scratchpad, never in the repo** (gate files can be written once only):

- Frontend: the template with `LAYERS` filled, saved as `<scratchpad>/draft.cjs`, run from the frontend dir with `depcruise src --config <scratchpad>/draft.cjs` (pinned versions as above).
- Python: `<scratchpad>/arch-gates.json`, run with `check_imports.py layers --config <scratchpad>/arch-gates.json --project-dir <python dir>` (and `cycles` the same way).

**Rules the draft must follow**, in this order of priority:

1. **Every invariant of step 2 holds by construction**: what `A` must never import sits in a layer above `A`. A single stack enforces one direction only: when two runtimes must not import each other at all, put lower the one whose misuse breaks the program (the code that runs without a DOM, without secrets...) and list the other direction as a limitation.
2. Areas that import each other go in the same layer — unless that breaks an invariant; then split them.
3. Only then, among the orders that satisfy 1–2, the one with the fewest upward edges. Each upward edge left is debt the baseline freezes: list it.
4. **Fail closed.** When a folder is split by file name (`detection|fix`), write the regexes so that a new file matching no name lands on the side where a wrong import turns **red**, never where it passes. Say which side that is.
5. **Regexes are JavaScript strings**: a literal dot is `'\\.'` — `'\.'` is just `.` and matches any character. After the run, list the modules each layer actually matched (e.g. `--output-type json`) and compare with what you meant.
6. Every module is classified: no `not-in-a-layer*` violation, no exit 2.

**Probe before asking.** Run the draft once without any probe and record its violations: that is the debt the baseline will freeze (no baseline exists yet, so a draft with debt is never green here). For each invariant, create one throwaway file that imports across it — through the tsconfig path alias when the repo has one — and run the draft: the output must be the recorded violations **plus the probe's, naming the expected rule**. Delete the file, run again: exactly the recorded violations; `rtk git status` clean. A probe that adds no violation means the draft is wrong: fix it, do not ask.

**Show the owner, as text before the question** (never collapsed into a tool output), per side:

- the boundaries and invariants found, each with its evidence file;
- the layers, lowest first: `# | regex (or modules) | runtime / role | what it holds`;
- the upward edges and cycles the baseline will freeze (count, then each `a -> b`), or "none";
- each probe and its result (`sandbox/__probe.ts -> features/x/Panel.tsx: red, layer-2`);
- the limitations: what the stack cannot enforce, and where a new file with an unforeseen name lands;
- the repo's own analyzers (step 1), the finding each will raise on a created file and the exact config line the owner adds (Fallow: `unused-file` on `.dependency-cruiser.cjs`, line `"ignorePatterns": [".dependency-cruiser.cjs"]`). Announced here, verified in step 6: the file does not exist yet, so nothing can be run against it now.

Then ask with **AskUserQuestion**: "Approve these layers?" with options *Approve*, *Change them* (the owner writes the change in "Other"), *Stop*. Iterate — redraft, re-probe, show the full table again — until *Approve* or *Stop*. Never create a gate file before *Approve*.

## 4b. Quality and mutation gates — measure, propose, wait

Still nothing written in the repo. Measure the debt with the pinned tools, reports in the scratchpad, for the families that are absent:

- **Complexity, Python** (from `<python dir>`): `uv run --no-project --with ruff==0.16.10 ruff check --select C901 --config "lint.mccabe.max-complexity=10" --output-format json --exit-zero <package> > <scratchpad>/ruff.json`. The repo's own ruff configuration applies (its `exclude`), only the rule and the threshold are imposed.
- **Complexity, frontend** (from `<frontend dir>`, with the repo's own eslint and config): when `node_modules/` is absent, install from the lockfile first (`npm ci`, `pnpm install --frozen-lockfile` or `yarn install --immutable`; it writes nothing the repo tracks). Then `npx eslint --rule "complexity: [2, 10]" --format json src > <scratchpad>/eslint.json || true`.
- **Duplication**, per side: `npx --yes jscpd@5.4.0 <package or src> --format <python | typescript,tsx,javascript,jsx,scss,css> --ignore "<the default of the side's workflow>" --reporters json --output <scratchpad>/jscpd-<side> --absolute --silent`.
- The gate on each report, with no baseline (`gates="$(cat ~/.claude/claude-config.path)/gates/python/check_quality.py"`): `uv run --no-project --python 3.12 python "$gates" complexity --tool ruff|eslint --report <report> --project-dir <side dir>` and `… duplication --report <report> --project-dir <side dir>`: exit 1, and the list it prints is the debt the baseline will freeze. Exit 2 is a blind spot (a file the tool cannot parse, a report that is not the tool's): fix the run, not the repo.

**Mutation, Python side only.** mutmut refuses native Windows: nothing runs here, the PR's first run prints the baseline. Choose the target: one module of pure, deterministic logic with a dedicated test file (`tests/test_<name>.py` ↔ `<package>/…/<name>.py`), the smallest such pair; a module whose tests need a network, a database, a clock or the filesystem is a bad target, its mutants time out or flake. Draft the `[tool.mutmut]` block the header of `check_mutation.py` shows (`source_paths`, `also_copy = ["<package>"]`, `pytest_add_cli_args_test_selection = ["tests/test_<name>.py"]`).

**Show the owner, as text before the questions**: per side, the functions above 10 (count, the three highest with their file) and the clones (count, by format); the mutation target with its test file and the block; what each caller will carry. Then **AskUserQuestion**, one question per absent family:

- "Quality gates: threshold and scope?" with *10, code and styles, tests excluded* (the workflows' defaults), *15*, *Code only, no styles*, *Skip quality*;
- "Mutation gate on `<module>`?" with *Approve*, *Another module* (named in Other: redraft, ask again), *Skip mutation*.

A skipped family creates nothing. Nothing is written before the answers.

## 5. Create the declarations — once each, in final form

**Python** — `<python dir>/arch-gates.json`: the package and the approved layers, in the format the header of `check_imports.py` gives (`cat "$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"`). The root package entry covers only itself: list every top-level module and subpackage explicitly.

Then the baselines, created and never overwritten by the script itself:

```bash
gates="$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"
uv run --no-project --with grimp==3.14 python "$gates" cycles --config <python dir>/arch-gates.json --init-baseline
uv run --no-project --with grimp==3.14 python "$gates" layers --config <python dir>/arch-gates.json --init-baseline
```

Exit 2 on `layers` (a module in no layer) should not happen here: the draft was probed in step 4. If it does, the config you wrote differs from the draft: say so and go to the last rule of step 7 — the owner fixes `arch-gates.json` by hand (a human may edit it), then creates the baselines with the two `--init-baseline` commands above; list the unclassified modules and those two steps in the PR.

**Frontend** — `<frontend dir>/.dependency-cruiser.cjs` from `~/.claude/templates/gates/dependency-cruiser.cjs`: fill `LAYERS` with the approved layers (one array of path regexes per layer, matched right after `src/`, e.g. `'utils/'`, `'(App|main)\\.tsx$'`) and set `tsConfig.fileName` to the tsconfig found in step 1. Change nothing else. Then the baseline:

```bash
cd <frontend dir> && npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --config .dependency-cruiser.cjs --output-type baseline > .dependency-cruiser-known-violations.json
```

**CI** — `.github/workflows/arch-gates.yml` from `~/.claude/templates/gates/arch-gates.yml`, keeping only the job(s) of the sides the repo has, with their real paths: a side the repo lacks has no job, so nothing shows as skipped and its check cannot be skipped past. Also `.github/workflows/baseline-ratchet.yml` from `~/.claude/templates/gates/baseline-ratchet.yml` if the repo has no ratchet caller yet.

**Quality** — the two baselines per side, in final form, from the reports of step 4b (rerun a tool if a probe file of step 4 could have been in its report): the same `check_quality.py` commands with `--init-baseline`, which creates `complexity-baseline.json` and `duplication-baseline.json` in `--project-dir`. Then `.github/workflows/quality-gates.yml` from `~/.claude/templates/gates/quality-gates.yml`, only the job(s) of the sides, with the real `dir` and `package`, plus `max-complexity`, `jscpd-formats` or `jscpd-ignore` when the owner chose other than the defaults. `.quality-*` goes in `.gitignore` (a file you may edit).

**Mutation** — `.github/workflows/mutation-gate.yml` from `~/.claude/templates/gates/mutation-gate.yml` with the Python dir, and `<python dir>/mutants/` in `.gitignore`. The `[tool.mutmut]` block belongs in `<python dir>/pyproject.toml`, a section a human edits (protect-gates keeps the `[tool.*]` sections): put it in the PR body and the hand-over, never write it. No baseline here: the PR's first `mutation / mutation` run is red with the list to commit as `mutation-baseline.json`, the owner's gesture.

## 6. Prove it — green, red on the fragile case, green

Run the gates exactly as CI does (commands in step 5, without `--init-baseline`; frontend with `--ignore-known`): all green. Then replay the step 4 probes against the created files — one per invariant, plus, when no invariant crosses it, one **new** upward import through the tsconfig path alias (the edge a missing `tsConfig` would silently drop): each red with the rule named, then deleted, then green again. `rtk git status` must show no leftover.

**Quality.** Run both gates per side exactly as the workflows do, with the baselines in place: green. Then one throwaway file per side holding a function with twelve `if` branches and a copy of an existing function of eight lines or more: the complexity gate names the function, the duplication gate names the clone with its two files; delete the file, rerun, green, `rtk git status` clean.

**Mutation.** No local run on Windows: the proof is the PR's own first run (red with the list), then the owner's baseline commit (green). Say so in the PR.

**The repo's own analyzers (step 1), now that the files exist.** Run each one as its CI or hook does, with the repo's config untouched: it must report the created files (Fallow on the pilot: `unused-file` on `.dependency-cruiser.cjs`). Run it again with a **copy** of its config carrying the line announced in step 4 (`fallow -c <copy> -r .`): no finding left on those files. Both results go in the PR; the repo's config itself is never edited.

## 7. Branch, commit, PR — then hand over

- Commit only the files of step 5 on `ci/gates` (Conventional Commits, `ci(gates): …`), `.gitignore` included, `rtk git push -u origin ci/gates`, `gh pr create` with: the invariants and their evidence, the approved layer table, the limitations, the thresholds and the mutation target, the frozen debt (entries per baseline), each probe red then green, and the `[tool.mutmut]` block to paste.
- Tell the owner what only they can do:
  1. the PR's `ratchet / ratchet` check is red **by design**: every baseline is new, so it counts as growth. Setting the `baseline-update` label is how they accept the frozen debt;
  2. the line from step 4 (verified in step 6) in their analyzer's config, if any: that check stays red until they add it, and you never add it for them;
  3. for the mutation gate: paste the `[tool.mutmut]` block into `pyproject.toml` on the branch; the first `mutation / mutation` run is then red and prints `mutation-baseline.json` to commit; a test of the target module weakened on a throwaway PR is the owner's own red proof, if they want one;
  4. once the checks have run, make them required on `main`: `arch-python / python` and/or `arch-frontend / frontend`, `quality-python / python` and/or `quality-frontend / frontend`, `mutation / mutation`, and `ratchet / ratchet` — offer to do it with their OK. A caller whose check is required must have no `paths:` filter on `pull_request`: a check that never reports leaves every other PR "Expected", blocked for good;
  5. merging is theirs.
- Never merge, never set the label, never touch a gate file outside this flow.
- Whatever stops you once step 5 has begun — a red check you may not fix, the exemption gone, a question — publish what can be published: commit the created files, push, open the PR, and list what is still missing for the owner. If a hook blocks the commit itself (an analyzer in pre-commit, say), never bypass it (`--no-verify` is blocked anyway): leave the files in place, name the hook and the config line the owner adds, and say that once they have added it any session can commit and push these files — `git add` and `git commit` of a gate file are not blocked, only writing one is. Never suggest running `/init-gates` again on this branch: step 1 refuses a repo that already has a gate file.
