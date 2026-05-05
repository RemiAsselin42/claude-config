---
description: 'Analyzes and explains changes since the last commit.'
argument-hint: '[specific files to explain, or empty to explain everything]'
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read, Grep, Glob
context: fork
agent: agent
---

## Scope

"$ARGUMENTS"

## Current repository state

!`git status`

## Changes summary

!`git diff --stat`

## Objective

Provide a clear and structured explanation of recent changes to facilitate understanding and communication within the team.

## Process

### 1. Collecting changes

**a. Inspecting Git state**

```bash
rtk git diff                      # Detailed differences
rtk git log -1 --stat            # Last commit (if already committed)
```

**b. Reading context**

- Use `Read` to examine modified files
- Use `Grep` to understand usage of added functions

**c. Categorizing changes**

- **New features**: Feature additions
- **Fixes**: Bug resolutions
- **Refactoring**: Improvement of existing code
- **Style**: Formatting and conventions
- **Tests**: Addition or modification of tests
- **Documentation**: Doc updates
- **Infrastructure**: Config, build, dependencies

### 3. Report generation

Produce a structured and concise report:

```markdown
# Changes Summary

**X files modified** | +Y lines | -Z lines

## Executive summary

[2-3 sentences describing the overall goal of the changes]

## Detail by file

### src/sections/01-hero/hero.ts (+45, -12)

Adds automatic 3D model rotation animation with speed control.

### src/core/scrollManager.ts (+23, -8)

Improves scroll synchronization with progress display and smooth transitions.

### src/sections/sectionManager.test.ts (+78, -0)

Creates a complete test suite covering nominal cases and edge cases of section management.

### src/sections/01-hero/README.md (+15, -3)

Updates documentation with new animation parameters and usage examples.

### src/sections/registry.ts (+2, -1)

Registers the new hero section with its animations in the section registry.

## Significant changes

1. **New animation logic**: Added rotation control with configurable speed
2. **Scroll improvement**: Smoother synchronization with progress indicator
3. **Test coverage**: +78 lines of tests to ensure robustness
4. **Up-to-date documentation**: README enriched with practical examples

## Impact

- **Functionality**: Smoother animation and improved controls
- **UX**: More responsive and informative interface
- **Quality**: Test coverage improved to 92%
- **Maintenance**: Documentation facilitating onboarding

## Change type

[Feature | Fix | Refactor | Docs | Tests | Style | Perf | Chore]
```

## Output format

### For each file, use this concise format:

**Production files**

```
### path/to/file.ts (+XX, -YY)
[One line describing the main change]
```

**Tests**

```
### tests/file.test.ts (+XX, -YY)
[One line describing what is tested]
```

**Documentation**

```
### docs/file.md (+XX, -YY)
[One line about the doc update]
```

**Configuration**

```
### file.config.ts (+XX, -YY)
[One line about the config change]
```

**Styles**

```
### styles/file.scss (+XX, -YY)
[One line about the style changes]
```

## Writing principles

### DO

- **Clarity**: Simple and accessible language
- **Conciseness**: One line per file, short sentences
- **Context**: Explain the "why" as well as the "what"
- **Structure**: Use emojis for readability
- **Hierarchy**: Summary → Details → Impact
- **Objectivity**: Describe factually without judgment

## Examples of concise descriptions

✅ **Good descriptions (one line):**

- "Adds email validation with RFC 5322-compliant regex"
- "Fixes modal closing bug when clicking overlay"
- "Refactors useScan hook to reduce unnecessary re-renders"
- "Extracts constants to dedicated file to improve maintainability"
- "Improves button contrast for WCAG 2.1 AA accessibility"

## Tools

- `Bash`: Run git commands
- `Read`: Examine modified files if needed
- `Grep`: Understand the context of a change

## Use cases

1. **Stand-up meeting**: Quickly explain what was done
2. **Pull request**: Help reviewers understand the changes
3. **Documentation**: Prepare release notes
4. **Onboarding**: Help new members understand evolution
5. **Communication**: Share progress with non-technical stakeholders

Provide a clear, structured, and easy-to-understand explanation that allows anyone to quickly grasp the essence of the changes.
