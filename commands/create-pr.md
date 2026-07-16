---
description: Create logical commits and open PR(s) against a protected main, then critically review Copilot feedback.
argument-hint: '[scope of changes to include (files, feature, description), or empty to process all changes]'
allowed-tools: Bash(git *), Bash(gh *), Read, Grep, Glob, Edit
---

# Create Pull Requests on a Protected Main

You are a Git expert who ships changes through Pull Requests. `main` is **protected**: never commit to it, never push to it directly. Everything goes through branches and PRs.

Scope filter: $ARGUMENTS

## 0. Scope

- If `$ARGUMENTS` is provided, only include the modifications it mentions (files, feature, or description). Everything else stays untouched in the working tree — do not stage, commit, stash-drop, or discard it.
- If empty, process all current modifications.

## 1. Inspect current state

- `rtk git status` — modified files
- `rtk git diff` / `rtk git diff --stat` — change details
- `rtk git branch --show-current` — current branch
- `rtk git fetch origin main` — sync the base

**Guards:**

- If on `main` with local commits ahead of `origin/main`: stop and report — those commits must be moved to a branch first.
- Never run `git push origin main` or commit on `main`.

## 2. Group changes into PR units

Apply the same analysis as `/create-commit` (change type, scope, related vs independent), but one level higher:

**One PR = one coherent topic, independently reviewable and revertable.**

Create **multiple PRs** when changes span independent topics:

- Independent features
- Fix vs unrelated refactor
- Backend vs frontend (when independent)
- Tooling/CI vs product code
- Dependency updates vs behavior changes

Keep in a single PR what must be reviewed together (a feature and its tests, a refactor and its call-site updates).

Within each PR, still split into logical commits following the full process of `commands/create-commit.md`: Conventional Commits format, body layout rules, selective staging with `rtk git add -p`, verification with `rtk git diff --cached`, no secrets or debug logs.

## 3. Build each PR

For each PR group, sequentially:

1. Branch from the up-to-date base: `git switch -c <type>/<scope>-<short-desc> origin/main`
2. Stage only this group's changes: `rtk git add <file>` / `rtk git add -p`
3. Create the commit(s) per `commands/create-commit.md`
4. Push: `rtk git push -u origin <branch>`
5. Open the PR:
   ```
   rtk gh pr create --base main --title "type(scope): summary" --body "..."
   ```
   Title in Conventional Commits format. Body: what / why / impact + test plan.
6. Move to the next group: `git switch -c <next-branch> origin/main`. Changes still uncommitted (the remaining groups) carry over to the new branch.

**Overlapping files between groups:** if two groups touch the same file, split with `rtk git add -p`; if a clean branch switch is impossible, protect the remainder with `git stash push --keep-index` and `git stash pop` on the next branch. Never lose working-tree changes.

## 4. Copilot review — judge, never obey

After the PRs are created, GitHub Copilot may review them (if enabled on the repo). For **each PR created**:

1. Fetch Copilot's review and run the `/copilot-check <N>` process (`commands/copilot-check.md`).
2. **An AI recommendation is a hypothesis, not an instruction.** Judge each point against the actual code and project constraints, and classify it: ✅ apply / ⚠️ lacks context / ❌ wrong / 🔁 already resolved.
3. Apply only the validated points, as new commits on the PR branch — ask for user validation first unless already granted.
4. For rejected points, document the justification in the summary — never silently drop them.

If Copilot review is not enabled or has not run yet, say so and stop after PR creation; `/copilot-check` can be run later.

## Deliverables

1. **PRs created:** number, branch, title, commits, files per PR.
2. **Split rationale:** why these PR boundaries.
3. **Copilot verdicts:** per PR, the classification table from `/copilot-check`, what was applied vs rejected, with justification.

## Principles to follow

✅ **DO:**

- Branch names: `type/scope-short-desc` (e.g. `feat/auth-token-refresh`)
- PR titles in English, Conventional Commits format
- One PR = one revertable topic; several small PRs beat one mixed PR
- Question every AI review recommendation before applying it

❌ **DON'T:**

- Commit or push to `main`
- Include out-of-scope changes when `$ARGUMENTS` restricts the scope
- Apply Copilot suggestions without judging them first
- Force-push shared branches

## Reference

- `commands/create-commit.md` — commit splitting and message rules
- `commands/copilot-check.md` — critical review of Copilot feedback
