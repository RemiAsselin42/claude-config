---
description: 'Analyzes and evaluates a freshly cloned repository: project purpose, features, code quality, issues, and recommendations.'
argument-hint: '[specific focus or aspect to deepen, or empty for a complete review]'
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git branch:*), Bash(git tag:*), Bash(find:*), Bash(cat:*), Bash(wc:*)
context: fork
agent: agent
---

## Analysis scope

"$ARGUMENTS"

## Objective

Produce a complete review of a codebase discovered for the first time: understand what the project does, evaluate code quality, identify implemented features, spot problems, and formulate actionable recommendations.

## Process

### 1. Initial orientation

**a. Repository structure**

```bash
find . -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' | sort
```

**b. Entry and configuration files**

- Read `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` if present
- Read root config files: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`, `docker-compose.yml`, etc.
- Read build/CI configs: `.github/workflows/`, `Dockerfile`, `.env.example`

**c. Git history**

```bash
rtk git log --oneline -30
rtk git branch -a
git tag --sort=-creatordate | head -10
```

**d. Raw metrics**

```bash
# File count by type
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20

# Code volume
wc -l $(find . -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null) 2>/dev/null | tail -1
```

### 2. Understanding the project

**a. Purpose and domain**

- What problem does the project solve?
- Who are the target users?
- What is the main data model?

**b. General architecture**

- Identify the architectural pattern (MVC, hexagonal, microservices, monolith, etc.)
- Map the main modules/packages and their responsibilities
- Identify entry points (main, index, app, server, etc.)
- Identify major external dependencies and their role

**c. Tech stack**

- Language(s) and version(s)
- Main framework(s)
- Database / storage
- Infrastructure / deployment
- Build, test, lint tools

### 3. Feature inventory

For each significant module/directory, identify:

**a. Implemented and operational features**

- Complete features with code, tests, and documentation
- Exposed endpoints / commands / interfaces

**b. Partially implemented features**

- Code present but incomplete (TODO, FIXME, stubs, placeholders)
- Features mentioned in README but absent from code
- Never-reached code branches

**c. Missing or abandoned features**

- Commented code
- Empty files or skeletons
- References to non-existent modules

### 4. Code quality

**a. Readability and conventions**

- Are names (variables, functions, modules) explicit?
- Is the style consistent throughout the project?
- Is a linter/formatter configured and used?
- Are language conventions respected?

**b. Architecture and design**

- Does the code respect the single responsibility principle?
- Is there tight coupling or circular dependencies?
- Are abstractions at the right level?
- Is there significant code duplication?

**c. Robustness**

- Is error handling consistent and complete?
- Are edge cases handled?
- Are there magic numbers or hardcoded values?
- Are external inputs (API, users, files) validated?

**d. Security**

- Secrets or credentials exposed in code or Git history
- Potential injections (SQL, shell commands, XSS)
- Authentication / authorization correctly implemented
- Dependencies with known vulnerabilities

**e. Performance**

- Algorithms with problematic complexity
- N+1 queries or network calls in loops
- Missing cache where relevant
- Potential memory leaks

**f. Tests**

- Presence and location of tests
- Test types (unit, integration, e2e)
- Estimated coverage
- Assertion quality (too permissive, trivial cases)
- Flaky or skipped tests

**g. Documentation**

- README: present, up-to-date, useful?
- Comments: absent, redundant, or genuinely explanatory?
- API or configuration documentation
- Usage examples

### 5. Problem identification

Classify each problem found by severity:

**🔴 Critical**

- Proven functional bugs (incorrect logic, probable crash)
- Security vulnerabilities
- Possible data loss
- Project cannot start or function

**🟡 Moderate**

- Technical debt blocking evolution
- Missing tests on critical paths
- Missing error handling on risky operations
- Tight coupling making changes dangerous

**🟢 Minor**

- Conventions not respected
- Insufficient documentation
- Dead or commented code
- Cosmetic improvement opportunities

### 6. Strengths

Identify and highlight what is done well:

- Elegant and idiomatic patterns
- Well-thought-out architecture
- Complete and relevant tests
- Clear documentation
- Robust error handling
- Security taken into account

## Report format

```markdown
# Codebase Review: [Project Name]

## Overview

**Purpose**: [What the project does in 1-2 sentences]
**Domain**: [e.g. REST API, CLI, library, web application, etc.]
**Stack**: [Language, framework, DB, infra]
**Estimated maturity**: [Prototype / In development / Stable / Actively maintained]

---

## Architecture

[Description of code organization, main modules and their interactions]

### Main modules

| Module      | Responsibility       | Estimated quality |
| ----------- | -------------------- | ----------------- |
| `src/auth/` | JWT Authentication   | ✅ Good           |
| `src/api/`  | REST Endpoints       | ⚠️ Incomplete     |
| `src/db/`   | Data access          | ✅ Good           |

---

## Features

### Implemented and operational

- ✅ **[Feature A]**: [Description, where it is in the code]
- ✅ **[Feature B]**: [Description]

### Partially implemented

- ⚠️ **[Feature C]**: [What is missing, `file.ts:42` — TODO present]
- ⚠️ **[Feature D]**: [Stub without implementation]

### Missing or abandoned

- ❌ **[Feature E]**: Mentioned in README, no code found
- ❌ **[Feature F]**: Commented code in `legacy/old.ts`

---

## Strengths

### Architecture and design

- ✅ **[Strength]**: [Why it's good]

### Code quality

- ✅ **[Strength]**: [Why it's good]

### Tests

- ✅ **[Strength]**: [Why it's good]

---

## Identified problems

### 🔴 Critical

1. **[Problem]**
   - **Where**: `src/auth/middleware.ts:87`
   - **Impact**: [Concrete consequence]
   - **Suggestion**: [Recommended fix]

### 🟡 Moderate

1. **[Problem]**
   - **Where**: [File:line]
   - **Impact**: [Consequence]
   - **Suggestion**: [Fix]

### 🟢 Minor

1. **[Problem]** — `[file:line]` — [Quick fix]

---

## Overall quality

| Dimension      | Score      | Comment       |
| -------------- | ---------- | ------------- |
| Readability    | ⭐⭐⭐⭐☆ | [Comment]     |
| Architecture   | ⭐⭐⭐☆☆  | [Comment]     |
| Tests          | ⭐⭐☆☆☆   | [Comment]     |
| Security       | ⭐⭐⭐⭐☆ | [Comment]     |
| Documentation  | ⭐⭐⭐☆☆  | [Comment]     |
| Maintainability| ⭐⭐⭐☆☆  | [Comment]     |

---

## Recommendations

### High priority (do before any development)

- [ ] [Concrete action] — `[file]`
- [ ] [Concrete action]

### Medium priority (plan it)

- [ ] [Concrete action]
- [ ] [Concrete action]

### Low priority (continuous improvements)

- [ ] [Concrete action]
- [ ] [Concrete action]

---

## Metrics

| Metric                  | Value |
| ----------------------- | ----- |
| Source files            | N     |
| Lines of code (est.)    | N     |
| Test files              | N     |
| Direct dependencies     | N     |
| Commits                 | N     |
| Contributors            | N     |
```
