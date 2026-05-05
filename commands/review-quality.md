---
description: 'Evaluates code quality: conventions, modularity, architecture, tests, and typing.'
argument-hint: '[specific directory or file, or empty to analyze the entire project]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(wc:*), Bash(npm run test:coverage:*), Bash(npm run lint:*), Bash(npx tsc:*), Bash(npx eslint:*)
context: fork
agent: agent
---

## Analysis scope

"$ARGUMENTS"

## Objective

Produce an analysis focused on **intrinsic code quality**: conventions, modularity, architecture, test coverage, and typing. This analysis intentionally excludes functional aspects (what the code does), performance, and security.

## Process

### 0. Initial orientation

```bash
# Project structure (3 levels max)
find . -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/dist/*' -not -path '*/build/*' | sort

# Quality configuration files present
find . -maxdepth 2 -name ".eslintrc*" -o -name ".prettierrc*" -o -name "biome.json" -o -name "tsconfig*.json" -o -name ".editorconfig" -o -name "jest.config*" -o -name "vitest.config*" | grep -v node_modules
```

Also read `package.json` (or `pyproject.toml`, `Cargo.toml`, etc.) to identify available lint and test scripts.

If `$ARGUMENTS` is provided, restrict the analysis to that path.

---

### 1. Architectural pattern

**a. Pattern identification**

```bash
find . -maxdepth 2 -type d -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' | sort
```

Common patterns to detect:

| Pattern                         | Structural indicators                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------- |
| **MVC**                         | `models/`, `views/`, `controllers/` directories                                             |
| **Hexagonal / Ports-Adapters**  | `domain/`, `application/`, `infrastructure/`, `ports/`, `adapters/` directories            |
| **Feature-based**               | Directories per feature (`users/`, `orders/`, `auth/`) each with their own modules         |
| **Layered**                     | `services/`, `repositories/`, `entities/`, `dtos/` directories                             |
| **Microservices**               | Multiple `package.json` or multiple services in a monorepo                                  |
| **Unstructured monolith**       | Everything in `src/` with few subdirectories                                                |

**b. Pattern relevance evaluation**

Evaluate whether the chosen pattern is appropriate:

- **Project size**: A complex hexagonal pattern for 500 lines is over-engineered
- **Consistency**: Is the pattern applied uniformly? (no MVC + hexagonal mix)
- **Coupling**: Do layers respect the pattern's dependency rules?
- **Scalability**: Does the pattern allow healthy evolution?

```bash
# Detect layer violations (relative imports going up)
grep -rn "from '\.\.\/" src/ --include="*.ts" 2>/dev/null | grep -v node_modules | head -30
```

---

### 2. Naming conventions

**a. Linter and formatter**

Check if a linter/formatter is configured and try to run it:

```bash
rtk lint | head -50
```

**b. Conventions by symbol type**

For each language present, check convention consistency:

| Symbol                            | Expected convention                                      |
| --------------------------------- | -------------------------------------------------------- |
| Classes, Interfaces, Types, Enums | `PascalCase`                                             |
| Functions, methods, variables     | `camelCase`                                              |
| Global constants                  | `SCREAMING_SNAKE_CASE`                                   |
| Source files                      | internal consistency (kebab-case or camelCase)           |
| Test files                        | `.test.ts` / `.spec.ts` suffix or `__tests__/` directory|

```bash
# Detect single-letter names (excluding iterators i, j, k)
grep -rn "\bconst [b-hln-z]\b\|\blet [b-hln-z]\b" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -20

# Detect lowercase types/interfaces
grep -rn "^interface [a-z]\|^type [a-z]" src/ --include="*.ts" 2>/dev/null | head -20
```

**c. Inconsistencies to flag**

- Mixed styles in the same project (e.g. `getUserData` and `get_user_data`)
- Too vague names without context: `data`, `info`, `tmp`, `temp`, `obj`, `result`
- Non-standard abbreviations: `usr`, `cfg`, `mgr`, `svc`

---

### 3. File size and modularity

**a. Oversized files (> 500 lines)**

```bash
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) \
  -exec wc -l {} \; 2>/dev/null | sort -rn | head -30
```

For each file > 500 lines:

1. Read the file with `Read`
2. Identify multiple responsibilities
3. Propose a concrete modular split (suggested new files with their responsibilities)

**b. Responsibility density**

```bash
# Count exports per file
grep -rn "^export " src/ --include="*.ts" 2>/dev/null | cut -d: -f1 | sort | uniq -c | sort -rn | head -20
```

Warning signals:

- File with > 5 distinct exports (classes/functions/types)
- File with > 10 functions
- File that imports from > 10 different modules

---

### 4. Test coverage and quality

**a. Test tooling detection**

```bash
cat package.json 2>/dev/null | grep -E '"jest"|"vitest"|"mocha"|"jasmine"|"cypress"|"playwright"'
```

**b. Running coverage**

Try the following commands in order until success:

```bash
rtk npm run test:coverage | tail -30
rtk npm run coverage | tail -30
rtk jest --coverage --passWithNoTests | tail -30
rtk vitest run --coverage | tail -30
```

**c. Structural test analysis**

```bash
# Ratio of test files vs source files
echo "Test files:" && find . -not -path '*/node_modules/*' \( -name "*.test.ts" -o -name "*.spec.ts" -o -name "*.test.js" -o -name "*.spec.js" \) | wc -l
echo "Source files:" && find src/ -not -path '*/node_modules/*' \( -name "*.ts" -o -name "*.js" \) | grep -v "\.test\.\|\.spec\.\|\.d\.ts" | wc -l

# Skipped tests
grep -rn "\.skip\|xit\b\|xdescribe\b\|it\.skip\|test\.skip" . --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules | head -20
```

**d. Assertion quality**

```bash
# Overly generic assertions
grep -rn "toBeTruthy\(\)\|toBeFalsy\(\)\|toBeDefined\(\)" . --include="*.test.ts" --include="*.spec.ts" 2>/dev/null | head -20
```

---

### 5. Typing quality

#### For TypeScript

**a. Strict configuration**

```bash
cat tsconfig.json 2>/dev/null
```

Check: `"strict": true`, `"noImplicitAny": true`, `"strictNullChecks": true`, `"noUnusedLocals": true`, `"noUnusedParameters": true`.

**b. Counting typing anti-patterns**

```bash
echo "=== :any ===" && grep -rn ": any\b\|<any>" src/ --include="*.ts" 2>/dev/null | grep -v "\.d\.ts" | wc -l
echo "=== @ts-ignore ===" && grep -rn "@ts-ignore" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== @ts-nocheck ===" && grep -rn "@ts-nocheck" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== as unknown as ===" && grep -rn "as unknown as" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== Object/Function types ===" && grep -rn ": Object\b\|: Function\b" src/ --include="*.ts" 2>/dev/null | wc -l
```

```bash
# Compilation errors
rtk tsc --noEmit | tail -20
```

#### For other typed languages

- **Python**: check `mypy`/`pyright` usage, presence of type annotations
- **Go**: check for excessive `interface{}`
- **Rust**: check for excessive `unwrap()`

---

### 6. Code duplication

**a. Repeated function signatures**

```bash
grep -rn "function " src/ --include="*.ts" --include="*.js" 2>/dev/null | sed 's/.*function //' | sed 's/(.*//' | sort | uniq -d | head -20
```

**b. Duplicate constants**

```bash
grep -rn "= '" src/ --include="*.ts" 2>/dev/null | sed "s/.*= '//" | sed "s/'.*//" | sort | uniq -dc | sort -rn | head -20
```

When reading files, note manually:

- Same validation logic repeated in multiple places
- Same data transformation duplicated
- Identical imports repeated everywhere (candidates for a barrel `index.ts`)

---

### 7. General readability

**a. Excessive nesting**

```bash
# 4+ indentation levels = high complexity signal
grep -rn "^        if \|^        for \|^        while " src/ --include="*.ts" --include="*.js" 2>/dev/null | head -20
```

**b. Magic numbers and strings**

```bash
# Magic numbers (excluding 0, 1, -1, 2)
grep -rn "[^a-zA-Z0-9_][3-9][0-9]\+[^a-zA-Z0-9_]" src/ --include="*.ts" 2>/dev/null | grep -v "test\|spec" | head -20

# Hardcoded URLs and paths
grep -rn '"http\|"https\|"\/api\/' src/ --include="*.ts" 2>/dev/null | grep -v "test\|spec" | head -20
```

When reading files, identify functions > 50 lines and evaluate whether they can be broken down.

---

## Report format

```markdown
# Code Quality Report

## Dashboard

| Dimension              | Score      | Main issues |
| ---------------------- | ---------- | ----------- |
| Architecture           | ⭐⭐⭐⭐☆ | [summary]   |
| Naming conventions     | ⭐⭐⭐⭐☆ | [summary]   |
| Modularity             | ⭐⭐⭐☆☆  | [summary]   |
| Test coverage          | ⭐⭐☆☆☆   | [summary]   |
| Typing quality         | ⭐⭐⭐☆☆  | [summary]   |
| Duplication            | ⭐⭐⭐⭐☆ | [summary]   |
| Readability            | ⭐⭐⭐☆☆  | [summary]   |

**Overall score**: XX/35

---

## 1. Architecture

**Detected pattern**: [e.g. Feature-based]
**Appropriate for project**: [Yes / Partially / No]

[Description of observed pattern, consistency, possible violations]

---

## 2. Naming conventions

**Linter configured**: [Yes/No — detected tool]

### Detected inconsistencies

- [Description] — `file.ts:line`

---

## 3. Modularity

### Files > 500 lines

| File                          | Lines | Responsibilities          | Suggested split                                      |
| ----------------------------- | ----- | ------------------------- | ---------------------------------------------------- |
| `src/services/UserService.ts` | 742   | Auth + CRUD + validation  | Extract `UserValidator.ts`, `UserEmailService.ts`    |

---

## 4. Tests

**Framework**: [Jest / Vitest / Pytest / etc.]
**Global coverage**: [X% or N/A]
**Tested file ratio**: X / Y source files

### Files without tests

- `src/services/PaymentService.ts` — critical logic not covered

### Assertion quality

[Overall quality observation]

---

## 5. Typing quality

| Anti-pattern    | Occurrences | Severity |
| --------------- | ----------- | -------- |
| `: any`         | 12          | 🟡       |
| `@ts-ignore`    | 3           | 🟡       |
| `@ts-nocheck`   | 1           | 🔴       |
| `as unknown as` | 2           | 🔴       |

**tsconfig strict**: [Enabled / Disabled / Partial]
**Compilation errors**: [0 / N errors]

### Critical occurrences

- `src/api/handler.ts:45` — `as unknown as User`: dangerous cast without validation

---

## 6. Duplication

### Duplicated blocks

- **[Description]**: logic repeated in `file-a.ts:12` and `file-b.ts:87`
  - Suggestion: extract to `src/shared/[name].ts`

---

## 7. Readability

### Functions too long (> 50 lines)

| Function       | File                        | Lines | Suggestion                                      |
| -------------- | --------------------------- | ----- | ----------------------------------------------- |
| `processOrder` | `src/orders/service.ts:34`  | 87    | Extract `validateOrder()` + `applyDiscounts()`  |

### Magic numbers/strings

- `src/config.ts:23` — `3600` without named constant → `SESSION_DURATION_SECONDS`

---

## Problems by severity

### 🔴 Critical (blocking maintainability)

1. **[Problem]**
   - **Where**: `file.ts:line`
   - **Impact**: [Consequence on maintainability]
   - **Fix**: [Concrete action]

### 🟡 Moderate (significant technical debt)

1. **[Problem]**
   - **Where**: `file.ts:line`
   - **Fix**: [Concrete action]

### 🟢 Minor (cosmetic improvements)

1. **[Problem]** — `file:line` — [Quick fix]

---

## Action plan

### High priority

- [ ] [Concrete action] — `file.ts`

### Medium priority

- [ ] [Concrete action]

### Low priority

- [ ] [Concrete action]

---

## Metrics

| Metric                  | Value |
| ----------------------- | ----- |
| Source files analyzed   | N     |
| Files > 500 lines       | N     |
| Files with tests        | N / M |
| Test coverage           | X%    |
| `any` occurrences       | N     |
| TypeScript errors       | N     |
```
