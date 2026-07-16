---
description: Analyze Copilot review feedback on a PR and judge each point (good practice / lacks context / wrong) before applying anything
argument-hint: "[PR number(s)]  — empty = PR of the current branch"
allowed-tools: Bash(gh pr view:*), Bash(gh api:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Read, Grep, Glob, Edit
---

You analyze **GitHub Copilot** review feedback on a Pull Request of this repo, then judge every point before any modification. Report language: **French**.

## 1. Target the PR

Provided argument: `$ARGUMENTS`

- If a number is provided → it is the PR number (`N`).
- If several numbers are provided (e.g. after `/create-pr` created several PRs) → process each PR one after the other (steps 2 to 4 for each, separate report per PR).
- Otherwise → fetch the PR of the current branch:
  `gh pr view --json number,title,headRefName`
  (if no PR exists for the branch, stop and say so clearly.)

## 2. Fetch Copilot feedback

Copilot writes both **inline comments** (the most useful) and a **review summary**. Fetch both (`{owner}/{repo}` are resolved automatically by `gh` inside the repo):

Inline comments:
```
gh api repos/{owner}/{repo}/pulls/<N>/comments --paginate \
  -q '.[] | select(.user.login | test("copilot";"i")) | "[\(.path):\(.line // .original_line)]\n\(.body)\n---"'
```

Review summaries:
```
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  -q '.[] | select(.user.login | test("copilot";"i")) | .body'
```

If there is no Copilot feedback: say so and stop (Copilot may not have finished its review yet).

## 3. Judge every point — NEVER apply blindly

For **each** Copilot remark:

1. **Read the CURRENT state of the file** (`path:line`). Many remarks target an intermediate state **already fixed** by a later commit/PR → mark as "already resolved".
2. Confront the remark with the project rules (`CLAUDE.md`, `docs/`, strict DS, RLS/JWT, strict types, rules-engine business logic).
3. **Copilot is sometimes wrong** — it lacks project context. Real example: it wrongly claimed Zod v4 does not support `z.number({ error })` (that is the v3 API). So classify, don't follow.
4. **Skeptical by default**: a remark is classified ✅ only if you can justify it yourself after reading the code — never because "Copilot said so". When in doubt → ⚠️, not ✅.

Classify each point:
- ✅ **Good practice** — valid remark, to apply.
- ⚠️ **Lacks context** — Copilot is right "in the absolute" but ignores a project constraint/convention that justifies the current code → leave as is, with the justification.
- ❌ **Wrong** — Copilot is technically mistaken → ignore, with the explanation.
- 🔁 **Already resolved** — fixed since the targeted commit.

## 4. Report

Produce a recap table: `file:line` · remark (summarized) · verdict · short justification.

Then: for ✅ points only, propose the fixes. **Ask for validation before editing** (unless the user already said to apply directly). Work in PRs / commits grouped by theme (see the `/create-pr` command), never an unrequested commit/push. Validated fixes are applied as new commits on the branch of the affected PR.
