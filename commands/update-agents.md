---
description: 'Updates the AGENTS.md file with critical project directives.'
argument-hint: '[specific standards or conventions to add, or empty for a complete update]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Specific directives

"$ARGUMENTS"

## Objective

Maintain an AGENTS.md file that is **concise** (<200 lines) with only the CRITICAL directives for working effectively on the project.

## AGENTS.md principles

### What MUST be in it

**Only critical elements not quickly discoverable:**

- Project-specific code standards (non-standard)
- Particular naming conventions
- Essential commands and their usage
- Project structure if non-obvious
- Pitfalls to absolutely avoid
- Required response format for certain tasks
- Critical dependencies and their role

### What must NOT be in it

- Long explanations discoverable by code analysis
- Exhaustive documentation (→ README.md)
- Project history
- Detailed tutorials
- Information redundant with other docs
- Generic standards (TypeScript, React standard)

## Recommended structure

```markdown
# Agent Guide - [Project Name]

> Quick reference guide (<200 lines). For full documentation: README.md

## Architecture

- **Stack**: [Main technologies]
- **Structure**: [Specific organization if non-obvious]
- **Main pattern**: [e.g. Feature-based, Registry pattern]

## Critical standards

### Naming

- Sections: `kebab-case` (hero, face-vader, thematic-objects)
- Components: `camelCase` (glbModel, scrollManager)
- Controllers: `camelCase` suffixed `Controller` (modelRotationController)
- Tests: `*.test.ts` co-located

### Types

- Strictly typed, zero `any`
- Shared types: `src/sections/types.ts`
- Core types: `src/core/*.ts`

### Imports

- Absolute imports allowed with `@/` alias
- Order: Three.js → libs → local
- Barrel exports in `index.ts` if needed

## Essential commands

\`\`\`bash
npm run dev # Dev with HMR
npm test # Vitest watch mode
npm run test:ci # CI tests (coverage)
npm run build # Production build
npm run lint # ESLint + fix
...
\`\`\`

## Tests

- **Minimum coverage**: 80%
- **Co-location**: `*.test.ts` next to the tested file
- **Three.js mocks**: Use `vitest` to mock imports
- **Convention**: `describe()` → function/class name, `it()` → behavior

## Adding a section

1. Create `src/sections/XX-section-name/`
2. Required files: `index.ts` or `name.ts`, `README.md`
3. Register in `src/sections/registry.ts`
4. Add tests in `src/sections/*.test.ts`
5. Document in section README

## Pitfalls to avoid

- ❌ Forgetting to dispose Three.js objects (memory leaks)
- ❌ Heavy operations in the render loop
- ❌ console.log in production (use telemetry `core/telemetry.ts`)
- ❌ Circular imports (especially in `registry.ts`)

## Internal tools

- **Telemetry**: `src/core/telemetry.ts` - Analytics and logging
- **Common types**: `src/sections/types.ts` - SectionContext, SectionLifecycle
- **Asset Loader**: `src/core/assetLoader.ts` - 3D model loading
- **Scroll Manager**: `src/core/scrollManager.ts` - Scroll management

## Response format

When modifying code:

1. Read context with `Read`
2. Use `Edit` for changes
3. Use `Bash` to run lint and tests
4. Summarize changes briefly

## References

- Detailed architecture: `/docs/architecture.md` (if exists)
- Contribution: `/docs/CONTRIBUTING.md` (if exists)
- Three.js: Official documentation
```

## Update process

### 1. Analyze current state

Read the existing AGENTS.md:

- Count lines (must be <200)
- Identify issues agents currently face that could be resolved by a guide update
- Identify obsolete sections
- Note missing critical information

### 2. Scan the project

Identify current critical elements:

```bash
# Project structure
rtk ls src/

# Available scripts
cat package.json | grep scripts

# Current naming conventions
find src/ -type f -name "*.ts" -o -name "*.tsx"

# Test patterns
find tests/ -type f -name "*.test.ts"
```

### 3. Identify critical changes

Check if these elements have changed:

- New important npm commands
- New code standards adopted
- Significant architecture changes
- New pitfalls discovered
- Internal tools added/modified

### 4. Update minimally

**Add only if:**

- Not quickly discoverable by the agent
- Critical to avoid serious errors
- Project-specific (not generic)
- Frequently changes workflow

**Remove if:**

- Has become obsolete
- Redundant with other documentation
- Too detailed (move to README)
- Generic (universal standards)

### 5. Verify conciseness

After modification:

- Count lines: **<200 lines**
- Check density: each line adds value
- Eliminate verbosity: short sentences, prefer bullets
- Eliminate unnecessary textual elements like emojis or excessive formatting
- Clear structure: well-delimited sections

### 6. Update report

```markdown
## AGENTS.md updated

### Changes applied

✅ Added "Available new hooks" section
✅ Updated npm commands (added test:watch)
✅ Removed obsolete "Webpack Configuration" section
✅ Condensed "TypeScript Standards" section (15→8 lines)

### Metrics

- **Lines**: 187/200 ✅
- **Sections**: 9
- **Density**: Optimal

### Validation

✅ All commands tested and valid
✅ Standards match current code
✅ No redundancy with README.md
✅ Guide immediately usable
```

## Minimal template

If creating from scratch, use this ultra-concise structure:

```markdown
# Agent Guide - [Project]

## Stack

[List technologies]

## Standards

- Naming: [Project-specific convention]
- Types: [Project's strict rules]
- Tests: [Required coverage]

## Commands

\`\`\`bash
[3-5 essential commands max]
\`\`\`

## Pitfalls

- ❌ [Critical error to avoid 1]
- ❌ [Critical error to avoid 2]

## Adding feature

1. [Step 1]
2. [Step 2]
3. [Step 3]

## Internal tools

- [Critical tool 1]: [Usage in 1 line]
```

## Golden rules

1. **<200 lines mandatory**
2. **Quick reference, not tutorial**
3. **Critical only, not nice-to-know**
4. **Short sentences, bullets preferred**
5. **Update only on major changes**

Maintain a laser-focused AGENTS.md that allows an agent to start effectively after 2 minutes of reading.
