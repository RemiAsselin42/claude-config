---
description: 'Finds dead code (unreachable, unused, deprecated) in the project.'
argument-hint: '[language] [path] — e.g. shell, typescript src/, python, javascript src/utils.js'
allowed-tools: Read, Grep, Glob, Bash(npm run type-check:*), Bash(npx tsc:*)
context: fork
agent: agent
---

## Arguments

"$ARGUMENTS"

Parse `$ARGUMENTS`:
- **Language** (required): first word — e.g. `shell`, `typescript`, `javascript`, `python`, `go`, `rust`…
- **Path** (optional): second argument — otherwise scan the entire project

If the language is absent, auto-detect from project files (e.g. presence of `package.json` → likely JavaScript/TypeScript).

---

## Objective

Identify all dead code within the given scope: unreachable branches, functions/symbols never used, variables declared but ignored, conditions always true/false.

---

## Process

### 1. Scope discovery

List source files for the target language at the specified path (or entire project). Adapt extensions and directories to exclude based on language (e.g. `node_modules/`, `dist/`, `*.d.ts`, `__pycache__/`…).

### 2. Universal dead code categories

For **each** category below, adapt detection tools and patterns to the target language:

#### A. Symbols defined but never used

Functions, methods, classes, constants, types defined in code but with no call or reference found anywhere in the project.

- Grep the symbol name across the entire project (excluding its own definition)
- Account for public exports that may be dynamically consumed (→ Probable, not Certain)

#### B. Code after an unconditional exit point

Any statement after an unconditional `return` / `exit` / `throw` / `break` / `continue` — the next line can never be reached.

- Read each file, trace control flow
- Look for non-empty, non-comment lines after a guaranteed exit point

#### C. Logically unreachable conditional branches

Conditions whose value is statically determinable at the evaluation point:

- Variable assigned to a fixed value just before the test
- Explicit `if (true)` / `if (false)` or equivalents
- `else` / `default` after an `if`/`switch`/`case` that exhaustively covers all possible cases
- Early return on a condition, followed by a redundant test on the same condition

#### D. Variables assigned but never read

Local variable declared and assigned, but `$var` / `var` / `self.var` never read within its lifetime scope.

#### E. Unused imports / includes / sources

Module imported, file sourced, header included, whose no symbol is referenced in the importing file.

#### F. Code marked as abandoned

```
TODO: remove
FIXME: dead
DEPRECATED
unused
```

Grep these patterns within the scope — often self-documented dead code.

### 3. File-by-file analysis

For each file in scope:

1. **Read** with `Read`
2. **Exported symbols** → grep their usage across the entire project
3. **Control flow** → identify guaranteed exits, fixed conditions
4. **Local variables** → trace their lifecycle within scope

### 4. Severity criteria

| Severity    | Criterion                                                                      |
| ----------- | ------------------------------------------------------------------------------ |
| 🔴 Certain  | Unreachable by pure static reasoning                                           |
| 🟡 Probable | No usage found, but dynamic call / reflection / eval possible                  |
| 🟢 Suspect  | Logically difficult to trigger, but an execution path remains open             |

---

## Report format

````markdown
# Report: Dead Code — <Language> — <Path>

## Summary

- **Files analyzed**: N
- **Occurrences**: X certain, Y probable, Z suspect

---

## 🔴 Certain

### `path/file.ext` — line(s) N-M

**Type**: <category>
**Reason**: <explanation of the flow that makes this code unreachable>

**Dead code**:
```
<excerpt>
```

**Fix**: <concrete action>

---

## 🟡 Probable

### `path/file.ext` — `<symbol>`

**Reason**: No call found in the project.
**Caveat**: <reason why a dynamic usage remains possible>

---

## 🟢 Suspect

### `path/file.ext` — line N

**Type**: <category>
**Reason**: <why it's suspect without being certain>

---

## Recommended actions

- [ ] Delete certain dead blocks
- [ ] Verify probable symbols before deletion
- [ ] Annotate intentionally exhaustive cases
````
