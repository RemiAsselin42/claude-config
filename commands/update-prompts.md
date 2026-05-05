---
description: 'Adapts prompt examples to the current project by replacing generic references with real codebase examples.'
argument-hint: '[name(s) of specific prompts to adapt, or empty to adapt all of them]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Targeted prompts

"$ARGUMENTS"

## Objective

Replace generic examples or examples from other projects in prompts with real, relevant examples taken from the current project, while preserving the exact structure and formatting.

## Process

### 1. Inventory prompts

List all prompts to adapt:

```bash
ls .github/prompts/*.prompt.md
```

### 2. Analyze the current project

Collect real elements from the project:

- Structure: `src/features/*/`, `tests/`, `docs/`
- Features: Actual feature names
- Key files: Components, types, utilities
- Scripts: Available `package.json` scripts
- Tech stack: TypeScript, React, Vite, Vitest, etc.
- Conventions: Observed naming patterns

### 3. Identify examples to replace

For each prompt, look for:

- ❌ Generic feature names or names from other projects
- ❌ File paths that don't exist in the project
- ❌ npm commands not available
- ❌ Types/APIs/Tests not used in the project
- ❌ Code examples with invalid imports
- ❌ References to tools not present
- ❌ Process/step examples not aligned with the project

### 4. Replace with real examples

**For each irrelevant example:**

**Before (generic example):**

```markdown
### src/features/user-service/api.ts (+45, -12)

Adds email validation with RFC 5322-compliant regex.
```

**After (example from current project):**

```markdown
### src/features/asset-loader/loader.ts (+45, -12)

Adds SVG format handling to allow vector imports.
```

### 5. Preserve structure

**⚠️ IMPORTANT — Do NOT modify:**

- Formatting (headings, bullets, structure)
- General instructions and explanations
- Process and principle sections
- Emojis and formatting
- YAML frontmatter

**✅ Modify ONLY:**

- Example file names
- Example feature names
- Example commands
- Code examples
- References to components

### 6. Replacement examples

**Feature names:**

```diff
- ### Feature "user-authentication"
+ ### Feature "api-connector"
```

**File paths:**

```diff
- `src/api/users/controller.ts`
+ `src/features/main-feature/controller.ts`
```

**npm commands:**

```diff
- npm run deploy:prod
+ npm run build
```

**Types and APIs:**

```diff
- interface UserProfile { name: string; }
+ interface DetectionResult { issues: ScanIssue[]; }
```

**Imports and code:**

```diff
- import { validateUser } from './validation';
+ import { detectIssues } from './detection';
```

### 7. Validation

After replacement, check:

- ✅ All mentioned files exist in the project
- ✅ All types/interfaces are defined in the codebase
- ✅ All npm commands are in package.json
- ✅ Mentioned features are in `src/features/`
- ✅ Prompt structure is identical
- ✅ Examples are consistent with each other

### 8. Update report

Provide a summary:

```markdown
## Prompts updated

- create-commit.prompt.md
- review-changes.prompt.md
- apply-suggestions.prompt.md

### Total

✅ 3 prompts updated
✅ 24 examples adapted to the project
✅ 0 structure errors
```

## Principles

### ✅ DO

- Use only existing project elements
- Maintain consistency
- Keep the same level of detail
- Adapt variable names in example code
- Verify each example is realistic

## Replacement template

For each example:

1. **Identify the pattern**: What type of example (feature, file, command, type)?
2. **Find the equivalent**: Search in the current project
3. **Replace precisely**: Keep the same context and level of detail
4. **Check consistency**: Does the example still make sense?

## Tools

- `Glob`: Explore `src/features/`, `tests/`
- `Read`: Read package.json, types, examples
- `Grep`: Find patterns in code
- `Edit`: Replace examples

Adapt prompts precisely so they perfectly reflect the current project, making examples immediately applicable and relevant.
