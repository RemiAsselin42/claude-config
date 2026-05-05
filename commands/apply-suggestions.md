---
description: 'Applies code change recommendations, validates integration, and runs tests. Use when: applying suggestions, implementing recommendations, fixing identified issues, apply changes, implement suggestions.'
argument-hint: '[recommendations to apply or reference to a previous analysis]'
allowed-tools: Read, Edit, Bash, Grep, Glob, TodoWrite
context: fork
agent: agent
---

## Context

This prompt is used **after** an analysis or code review phase that identified problems, dead code, comment issues, performance problems, architecture concerns, quality issues, or improvements to make. Take the previously made recommendations and implement them rigorously.

$ARGUMENTS

## Automatic source detection

This prompt runs in an isolated context (`fork`) — it does not see stdout from previous commands.

**If `$ARGUMENTS` is empty**, apply this strategy in order:

1. **Re-run the analysis**: detect the project type (Shell/TS/JS/Python…) and run the appropriate analysis command to get up-to-date recommendations:
   - Dead code → re-run `/find-dead-code` by reading files directly
   - Quality → grep for suspicious patterns in sources
2. **Ask**: if you can't infer the scope, ask a precise question: _"What type of analysis to apply, and in which directory?"_

**Never respond "no analysis visible"** without first attempting detection.

## Recognized analysis sources

### `/find-dead-code` report

Output format: sections `🔴 Certain`, `🟡 Probable`, `🟢 Suspect` with entries `### file — line(s)`.

Mapping to internal priorities:

| `/find-dead-code` severity | `apply-suggestions` priority |
| -------------------------- | ----------------------------- |
| 🔴 Certain                 | **Critical** — apply first |
| 🟡 Probable                | **Important** — apply after verification |
| 🟢 Suspect                 | **Minor** — apply if confirmed |

For each 🟡 Probable entry, verify there are no dynamic calls before deleting (grep the symbol across the entire project).

### `/review-quality`, `/review-comments`, `/review-documentation` reports

These reports use numbered sections or recommendation lists — extract each item as a change to apply.

## Typical use cases

1. **After a code review**: Implement a reviewer's suggestions
2. **After an audit**: Fix detected quality issues
3. **After an architecture recommendation**: Refactor to best practices
4. **After a security analysis**: Fix vulnerabilities
5. **After an optimization**: Apply performance improvements
6. **After a dependency analysis**: Update versions and fix related issues
7. **After a coverage analysis**: Add missing tests
8. **After a style analysis**: Fix linting issues
9. **After a documentation analysis**: Update comments and documentation
10. **After a performance analysis**: Optimize the identified slow parts

## Process

### 1. Recommendations summary

Start by listing clearly:

- Problems identified in the previous analysis
- Recommended solutions for each problem
- Priority of each change (critical, important, minor)
- Files to modify

**If recommendations come from `/find-dead-code`**, use the mapping table above to assign priorities automatically — no need to ask.

**If recommendations are unclear or an architectural choice is needed**, ask for clarification.

### 2. Impact analysis

Before any change, evaluate:

- **Architecture**: How do these changes fit into the current structure?
- **Dependencies**: What other modules/components are affected?
- **Standards**: What coding conventions must be followed?
- **Tests**: What tests need to be added or modified?

### 3. Change planning

Organize changes in logical order:

1. Infrastructure/types/interfaces changes (base)
2. Business logic changes
3. UI/component changes
4. Adding/updating tests
5. Documentation updates

**Use `TodoWrite` to track progress.**

### 4. Applying changes

For each change:

**a. Read the existing context**

- Use `Read` to understand the current code
- Identify patterns and conventions used
- Note existing imports, types, and dependencies

**b. Implement the change**

- Use `Edit` to apply changes
- Respect existing code style (indentation, naming, structure)
- Add comments if logic is complex
- Ensure consistency with the project's TypeScript/React conventions

**c. Check for errors**

- Use `Bash` to run `rtk lint` and detect errors
- Fix detected issues immediately
- Continue until zero errors

### 5. Integration verification

After each series of changes:

**a. Architectural consistency**

- Do new components follow established patterns?
- Are imports organized correctly?
- Are types consistent with the rest of the project?

**b. Code standards**

- Check for absence of `any` types
- Check that React hooks are used correctly
- Check that file names follow project conventions
- Check accessibility (aria-labels, roles, etc.)

**c. Error analysis**

```bash
rtk lint                 # Check linting
rtk npm run type-check   # Check TypeScript types (if available)
```

### 6. Functional validation

**a. Run existing tests**

```bash
rtk npm test                    # All tests
rtk npm test -- --coverage      # With coverage
rtk npm test -- <file>          # Specific tests
```

**b. Manual tests if needed**

- Describe manual test scenarios to perform
- Note expected behaviors
- Document observed results

**c. Check side effects**

- Do existing features still work?
- Have the changes introduced new warnings?
- Is performance affected?

### 7. Adding/Updating tests

If tests need to be created or modified:

**a. Unit tests**

- Create tests for new functions/components
- Cover nominal cases and error cases
- Aim for > 80% coverage on modified code

**b. Integration tests**

- Test interactions between modified components
- Verify data flows

**c. Run and validate**

```bash
rtk npm test -- --run           # Vitest
rtk npm test -- --watch         # Watch mode for iteration
```

### 8. Documentation

Update documentation if needed:

- README.md if public API has changed
- README.md files for modified features
- JSDoc comments for public functions
- CHANGELOG.md if applicable

### 9. Final report

Provide a structured summary:

```markdown
## ✅ Changes applied

### Modified files

- `src/sections/01-hero/hero.ts`: Description of change
- `src/sections/sectionManager.test.ts`: Tests added

### Problems fixed

1. ✅ [Problem 1]: Solution applied
2. ✅ [Problem 2]: Solution applied

### Tests

- ✅ All tests pass (X/X)
- ✅ Coverage: XX%
- ✅ No TypeScript errors
- ✅ No ESLint errors

### Checks

- ✅ Architectural integration compliant
- ✅ Code standards respected
- ✅ No regressions detected
- ✅ Documentation updated

### Remaining changes (if applicable)

- [ ] Optional change not applied: reason
```

## Guiding principles

### ✅ DO

- **Read before writing**: Understand the existing context
- **Incremental changes**: Apply in small testable batches
- **Continuous verification**: Use `get_errors` frequently
- **Systematic tests**: Run tests after each change
- **Communication**: Explain what is being done and why
- **Consistency**: Respect project patterns and conventions

## Problem handling

### If a change fails

1. Analyze the error with `Bash` (lint/type-check)
2. Revert the change if needed
3. Propose an alternative solution
4. Document why the initial recommendation could not be applied

### If tests fail

1. Identify the failing test
2. Understand why (regression vs obsolete test)
3. Fix the code or adapt the test accordingly
4. Re-run until success

### If integration causes issues

1. Identify conflicts with the existing architecture
2. Propose adjustments
3. Ask for validation if the change is significant

## Recommended tools

- `Read`: Read existing code
- `Edit`: Apply changes
- `Bash`: Run tests and validation commands
- `TodoWrite`: Track change progress
- `Grep`: Find pattern occurrences in the code
- `Glob`: Explore project structure

## Example flow

```
User: "Apply the refactoring suggestions you made"