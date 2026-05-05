---
description: 'Analyzes recent changes and updates documentation accordingly.'
argument-hint: '[documentation files to update, or empty to analyze everything]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Targeted files

"$ARGUMENTS"

## Objective

Update documentation to reflect recent code changes, ensuring clarity and accuracy.

## Process

### 1. Identify changes

Collect recent changes:

```bash
rtk git diff --stat           # Modified files
rtk git diff                  # Change details
```

Identify:

- New features added
- Modified or deleted functions/APIs
- Behavior changes
- New dependencies or configurations
- Architecture changes

### 2. Locate impacted documentation

Find docs to update:

- `/README.md`: Project overview
- `/docs/*.md`: Detailed documentation
- `src/features/*/README.md`: Per-feature docs
- `/CHANGELOG.md`: Version history
- `package.json`: Description and scripts
- JSDoc comments in code

### 3. Analyze the gap

For each change, check:

- ✅ Does the doc mention this feature?
- ✅ Are code examples still valid?
- ✅ Are parameters/types up to date?
- ✅ Are commands/usage correct?
- ⚠️ Are any sections obsolete?

### 4. Update

**Main README.md**

- Description of new features
- Updated usage examples
- New commands added
- Updated screenshots if UI changed

**Feature READMEs**

- Explanation of new logic
- Updated code examples
- Up-to-date parameters and options
- Added/modified use cases

**Technical documentation**

- Architecture diagrams if structural changes
- API documentation if endpoints modified
- Contribution guides if workflow changed

**CHANGELOG.md**

- Add an entry for the current version
- List changes by category (Added, Changed, Fixed, Removed)
- Use Keep a Changelog format

### 5. Quality check

Make sure:

- ✅ Examples are testable and functional
- ✅ Language is clear and accessible
- ✅ Structure is logical and easy to navigate
- ✅ Internal links work
- ✅ Screenshots are up to date
- ✅ Table of contents is correct

### 6. Update report

Provide a summary:

```markdown
## Documentation updated

### Modified files

- ✅ README.md: Added scroll-manager section
- ✅ docs/architecture.md: Updated diagram
- ✅ src/sections/01-hero/README.md: Created
- ✅ CHANGELOG.md: v1.2.0 entry

### Documented changes

1. ✅ New scroll-manager feature with examples
2. ✅ scrollManager.ts API with complete JSDoc
3. ✅ npm run dev command added
4. ✅ Troubleshooting section enriched

### Checks

- ✅ All examples tested and functional
- ✅ Internal links verified
- ✅ Screenshots updated
- ✅ Valid markdown format
```

## Writing principles

### ✅ Best practices

- **Clarity**: Simple language, concrete examples
- **Precision**: Accurate technical information
- **Completeness**: Covers all use cases
- **Maintainability**: Easy-to-update structure
- **Accessibility**: Understandable at all levels

## Feature documentation template

```markdown
# Feature Name

## Description

[One sentence describing the feature]

## Usage

\`\`\`typescript
// Concrete and functional example
\`\`\`

## API

### `functionName(params)`

- **Params**: Parameter description
- **Returns**: Return type and description
- **Throws**: Possible errors

## Configuration

[Available options]

## Examples

[Real use cases]

## Troubleshooting

[Common issues and solutions]
```

## Tools

- `Read`: Read existing documentation
- `Grep`: Find references to update
- `Edit`: Modify documentation
- `Bash`: Test examples

Produce clear, accurate, and up-to-date documentation that helps users understand and use the project effectively.
