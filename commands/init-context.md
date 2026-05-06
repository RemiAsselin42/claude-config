---
description: 'Analyzes the current repo and fills context/*.md files with real project-specific content (architecture decisions, code patterns, technical constraints).'
argument-hint: '[architecture|patterns|constraints, or empty to fill all three]'
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(find:*), Bash(cat:*), Bash(git log:*), Bash(git diff:*), Bash(wc:*), Bash(graphify:*)
context: fork
agent: agent
---

## Target files

"$ARGUMENTS"

## Objective

Fill `context/architecture.md`, `context/patterns.md`, and `context/constraints.md` with accurate, repo-specific content derived from reading the actual codebase — not generic examples.

If `$ARGUMENTS` specifies a single file (e.g. `patterns`), only fill that one.

## Preparation

### 1. Locate existing context files

```bash
find . -path './context/*.md' | sort
```

For each file found, read it and check:
- If it contains only the template placeholder comments (`<!--`) with no real content → **fill it**
- If it already has real content → **skip it** (do not overwrite unless the file is explicitly listed in $ARGUMENTS)

If `context/` doesn't exist, create it:
```bash
mkdir -p context
```
Then copy the templates from `~/.claude/templates/context/` if they exist, otherwise start from scratch.

### 2. Read the knowledge graph if available

```bash
graphify query "architecture patterns decisions" 2>/dev/null || true
```

If `graphify-out/GRAPH_REPORT.md` exists, read it for god nodes (highest-centrality files) — these reveal the true architectural core.

### 3. Explore the repo structure

```bash
find . -maxdepth 3 \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/graphify-out/*' \
  | sort
```

Read key files: `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod`, `README.md`, main config files, CI/CD files.

---

## Filling architecture.md

Analyze to identify **real decisions that were made** — not what could be done differently, but what was chosen and why.

Look for:
- Framework / library choices (why this ORM, why this state manager, why this test runner)
- Monorepo vs. polyrepo structure
- API style (REST vs. tRPC vs. GraphQL vs. gRPC)
- Auth approach (JWT, sessions, OAuth)
- Data model structure (normalized vs. denormalized, which DB)
- Module boundaries and separation strategy
- Service communication patterns

**Extract evidence from:**
- `package.json` dependencies (reveals choices)
- Directory structure (reveals separation strategy)
- Config files (reveals constraints)
- Git log for ADR commits or architecture-related messages:
  ```bash
  git log --oneline --grep="arch\|refactor\|migrat\|replac\|rewrite\|design" | head -20
  ```
- Any `docs/`, `ADR/`, `decisions/` directories
- Comments in key files that explain choices

**Write format:**

```markdown
# Architecture Decisions

## [Decision title]

**Decision:** [What was chosen — be specific, use actual package/pattern names]
**Rationale:** [Why — extracted from code evidence, not guessed]
**Constraints:** [Any non-obvious constraints this decision imposes on future work]
```

Only include decisions that are **non-obvious from the code alone** — don't document "we use React" if any reader can see it in package.json. Document *why* React over Vue, *why* this folder structure, *why* this auth pattern.

---

## Filling patterns.md

Identify **recurring patterns** that appear in 3+ places and would take time to discover by reading code.

Look for:
- How errors are handled (try/catch patterns, Result types, error boundaries)
- How components/modules are structured (file naming, co-location rules)
- How state is managed (where mutations happen, how updates propagate)
- How async operations are handled (async/await patterns, loading states)
- How the data layer is accessed (repository pattern, direct calls, hooks)
- How tests are organized and what patterns they follow
- Any custom abstractions (base classes, higher-order functions, decorators) that appear repeatedly

**Extraction method:**
- Read 3-5 representative files from core directories
- Look for repeated structural patterns across files
- Check test files for patterns in how tests are written

**Write format:**

```markdown
# Code Patterns

## [Pattern name]

[One paragraph max. State the pattern precisely, include the actual file path(s) where it appears as examples. Focus on what would surprise a new contributor.]
```

Only document patterns that are **not standard for the framework** — skip "we use hooks" in a React app. Document custom conventions, non-obvious choices, team-specific patterns.

---

## Filling constraints.md

Identify **hard constraints** — things that will cause silent failures, performance issues, or security problems if violated.

Look for:
- Performance budgets (bundle size targets in config, chunk limits, build warnings)
- Security invariants (data that must always be sanitized, fields never logged)
- Node.js / runtime version requirements (check `engines` field, `.nvmrc`, `.node-version`)
- Browser/platform targets (`.browserslistrc`, `tsconfig.target`)
- Known gotchas discovered from git history or comments:
  ```bash
  git log --oneline --grep="fix\|workaround\|gotcha\|bug\|FIXME\|careful\|don't\|never" | head -30
  git diff HEAD~50..HEAD -- '*.ts' '*.js' '*.py' | grep -i "FIXME\|HACK\|XXX\|workaround\|careful" | head -20
  ```
- Type coercions or data type surprises (IDs that look numeric but are strings, dates that aren't Date objects, etc.)
- External API quirks that required workarounds

**Write format:**

```markdown
# Technical Constraints

## [Category: Performance | Security | Compatibility | Known Gotchas]

- [Constraint stated as a rule. Include the consequence of violating it. Reference file/line if relevant.]
```

Only include constraints that are **not self-evident** — skip "validate user input" (everyone knows this). Document the specific invariant that isn't obvious, with the consequence of breaking it.

---

## Output

After writing the files, report:

```
## context/ initialized

- architecture.md: [N decisions documented]
- patterns.md: [N patterns documented]
- constraints.md: [N constraints documented]

Key findings:
- [Most non-obvious thing found]
- [Most important constraint]
- [Most team-specific pattern]
```

Keep the context files concise — 50-150 lines each. Claude reads these at every session start; verbose files waste context.
