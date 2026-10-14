---
description: 'Statement ablation audit of one TypeScript source under Vitest: a script neutralizes each statement in a throwaway copy and records which tests fail; two read-only auditors interpret the facts; what they disagree on is left to the owner. Changes nothing.'
argument-hint: '<source file> [test files…]'
allowed-tools: Agent, Read, Grep, Glob, Bash(node ~/.claude/scripts/test-ablation.cjs:*)
# A run takes minutes: the owner starts it.
disable-model-invocation: true
---

# Audit the tests of one source file

Arguments: "$ARGUMENTS", the source file first, then the test files, if any (default: every test file that imports the source).

The measure is deterministic and done by `~/.claude/scripts/test-ablation.cjs` (the deployed copy of `scripts/test-ablation.cjs`); the AI only interprets what the measure cannot settle. Nothing here edits a file, writes a file or runs tests outside the script: the owner decides what to do with the findings. The command runs in the main context because it spawns agents.

## 1. The language

`.ts`, `.tsx`, `.mts`, `.cts` → this script. `.py` → say "Python not supported yet" and stop. Anything else → say so and stop.

## 2. Dry run

```bash
node ~/.claude/scripts/test-ablation.cjs --source <source> [--tests <test files…>] --dry-run
```

Exit 2 → print the script's stderr line verbatim and stop. Otherwise one line to the owner: the number of units and the estimate the script printed.

## 3. Full run

```bash
node ~/.claude/scripts/test-ablation.cjs --source <source> [--tests <test files…>]
```

Exit 2 → print the script's stderr line verbatim and stop. Keep the stdout: the counts, and the report path on the last line.

## 4. The report

Read the report at that path (Read). Its `facts` are the five lists to interpret: `survived_reached`, `unreached`, `crash_only`, `never_failing_tests`, `orphan_tests`. The auditors are spawned whenever at least one list has an id; only when all five are empty is there nothing to classify: print the counts, say so, stop.

## 5. Two auditors, one message

Spawn `test-auditor` **twice in the same message** (two Agent calls, `subagent_type: test-auditor`, in parallel) with the same task message: the full report JSON, the source path, the test paths. The agents have no shell and no write tool; they read the source and the tests with Read.

## 6. Merge

For each id of `facts`, compare the two verdicts: identical → kept, with the evidence of the first; different → `disputed`, both verdicts and both evidences kept, for the owner to decide. A child an auditor grouped under its parent takes the parent's verdict for the comparison. An id one auditor did not cover is `disputed` with `absent` as that auditor's verdict. A "Missing tests" line is kept when both auditors propose one for the same unit; otherwise it is listed as proposed by one.

## 7. Report, then stop

In the owner's language:

- the script's counts, as printed;
- one table per verdict (`test-gap`, `equivalent`, `untestable`, `dead-code`, `weak-check`, `useless`, `other-target`, `orphan`, `unknown`): id, evidence;
- the disputed items, both verdicts;
- the "Missing tests" list, in one block the owner can paste as a spec: one line says it can feed `/feature`.

Nothing to fix here, nothing to write: the owner decides.
