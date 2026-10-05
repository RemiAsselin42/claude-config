---
description: 'Implements a feature end to end on a branch: plan, review of the plan by another model, acceptance tests written by another agent and seen red, code, the repo''s gates, tests verified frozen by git, adversarial review of the diff, one fix pass, report. Stops before any PR.'
argument-hint: '<spec: a sentence, or the path of a spec file>'
allowed-tools: Agent, AskUserQuestion, Read, Write, Edit, Grep, Glob, Bash(git status:*), Bash(git fetch:*), Bash(git switch:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git rev-parse:*), Bash(npm run:*), Bash(npm test:*), Bash(npx:*), Bash(uv run:*), Bash(pytest:*), Bash(graphify:*), Bash(mempalace:*), Bash(ls:*), Bash(cat:*), Bash(find:*)
# Only a human starts a feature: this chain writes code and commits on a branch.
disable-model-invocation: true
---

# Feature, end to end

Spec: "$ARGUMENTS" (a sentence, or the path of a file to read in full).

The author of the code does not write its tests and does not judge its own work. The tests come from the spec through another agent and are frozen by a commit before any code exists; two reviews run on another model with no memory of this session. What blocks is deterministic: the tests, the repo's gates, a git diff. The reviews are advisory and end in a report for the owner. This command never opens a PR and never merges.

Each step ends with one line of status to the owner. Stop and report at the first step that cannot complete; never skip a step to reach the next one.

## 1. Preconditions — read-only, stop if one fails

- `rtk git status` shows a clean tree; `rtk git fetch origin main`.
- The spec is non-empty.
- The repo has a test runner: a `test` script in `package.json`, pytest under `pyproject.toml`, or a `tests/` directory with an obvious runner. None: stop, a feature without tests has no place here.
- Slug `feat/<two to four words of the spec, kebab-case>`, absent locally and on origin.

## 2. Plan — in the scratchpad, nothing in the repo

Read `context/*.md` when present, then `graphify query` and `mempalace search --wing` as the global CLAUDE.md says, then the code the feature touches and two or three neighbouring tests for the conventions.

Write `<scratchpad>/feature-<slug>/plan.md` with these sections:

- **Spec**: verbatim.
- **Scope**: the change in five lines at most; the files to create or change, one line of why each.
- **Acceptance tests**: numbered, one sentence of observable behavior each (input → output or state), covering every requirement of the spec. No implementation detail.
- **Out of scope**: what the spec could suggest and this feature will not do.
- **Risks**: existing tests that may break, gates the change may hit (lint, types, layers, baselines), behavior changes for current callers.
- **Gates**: the exact commands step 6 will run, found now.

## 3. Review of the plan, then the owner's approval

Spawn the `plan-reviewer` agent (Agent tool, `subagent_type: plan-reviewer`) with the spec and the full plan. Revise the plan once from its findings: take what is right; under a **Review** section, note what you declined and why.

Then **AskUserQuestion**: "Approve this plan?", with the Scope, Acceptance tests and Review sections in the question, options *Approve*, *Change it* (the owner writes the change in Other: redraft, ask again), *Stop*. Nothing is written in the repo before *Approve*.

## 4. Tests from the spec, seen red, frozen by a commit

- `git switch -c feat/<slug> origin/main`.
- Spawn the `spec-tester` agent with the spec, the approved plan and the test directory. It writes test files only.
- Run the test command on those files. Every new test must fail, and for the right reason: a missing symbol or a wrong result, not a test file that does not load. A test that passes before the code exists tests nothing: send it back to `spec-tester` once with the reason; still passing, stop and report.
- Commit the test files alone: `test(<scope>): acceptance tests for <feature>`, the list of tests in the body. Keep the hash: `TESTS_COMMIT=$(git rev-parse HEAD)`.

## 5. Code

Implement the plan until the new tests pass, with the smallest change that does. Nothing checks these here, so hold to them: do not open a test file, a fixture, a baseline, a gate or lint config, a CI workflow (the hooks block most of them anyway); no skip, xfail, `noqa`, `eslint-disable`, `type: ignore`. A test that looks wrong is a line in the report, not an edit.

## 6. Gates — the repo's own, deterministic

In this order, stopping at the first red:

- `package.json` scripts, when present, among `build`, `typecheck`, `lint`, `test`: `rtk npm run <script>`.
- `pyproject.toml`, when present: `uv run ruff check .`, `uv run mypy` when configured, `uv run pytest`.
- Architecture gates, when declared: for each `arch-gates.json`, `uv run --no-project --with grimp==3.14 python "$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py" cycles --config <dir>/arch-gates.json` and the same with `layers`; in each directory holding a `.dependency-cruiser.cjs`, `npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --config .dependency-cruiser.cjs --ignore-known`.

A red gate: fix the code and rerun. A fix outside the feature's scope is reported, not made. Never the check. Keep each gate's last output for step 8.

## 7. Tests frozen — verified by git, then the implementation commit

`rtk git diff --stat "$TESTS_COMMIT" -- <every test file of step 4>` must print nothing. Anything there is a stop: the diff becomes the first line of the report, nothing is committed. The implementation may add tests of its own in other files; it may not change the acceptance tests.

Then commit the implementation, `feat(<scope>): <summary>`, per `commands/create-commit.md`; several commits when the change splits cleanly.

## 8. Adversarial review, one fix pass

Spawn the `diff-reviewer` agent with the spec, the plan, `TESTS_COMMIT`, the range `origin/main...HEAD` and the gate outputs of step 6. Judge each finding the way `/copilot-check` does: ✅ founded, ⚠️ lacks a context the repo has, ❌ wrong. Fix the ✅ ones once, in one commit `fix(<scope>): after review`, then rerun steps 6 and 7. No second review, no second fix pass: what remains goes in the report.

## 9. Report, then stop

In the owner's language:

- the branch, the commits, `TESTS_COMMIT`;
- the acceptance tests, each with the requirement it covers, and the `spec-tester`'s **Not covered** lines;
- each gate with its last result;
- the frozen-tests check: empty, or the diff;
- the review: the ✅ ⚠️ ❌ table with your justification, and what the fix pass changed;
- what you declined or could not do, and why.

The branch stays local. The owner reads, then runs `/create-pr` or drops the branch. Do not push, do not open a PR, do not merge.
