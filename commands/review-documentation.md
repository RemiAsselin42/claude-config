---
description: 'Checks consistency between documentation and code.'
argument-hint: '[specific sections or files to check, or empty to audit everything]'
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: agent
---

## Verification scope

"$ARGUMENTS"

## Objective

Identify inconsistencies between what the documentation says and what the code actually does, then propose corrections.

## Process

### 1. Documentation inventory

List all documentation files:

```bash
find . -type f -name "*.md" -o -name "*.mdx" -o -name "package.json" -o -name "CHANGELOG.md"
```

Sources to check:

- `/README.md`
- `/docs/*.md`
- `src/*/README.md`
- JSDoc comments
- `package.json` (scripts, description)
- `CHANGELOG.md`

### 2. Verification by category

**A. Documented vs implemented features**

- Does the feature exist in the code?
- Do the documented parameters match?
- Is the described behavior correct?

**B. API and signatures**

- Documented types vs actual types
- Required/optional parameters
- Return values
- Possible errors

**C. Code examples**

- Are examples syntactically correct?
- Do they use the right APIs?
- Do they actually work?

**D. Commands and scripts**

- Do the `npm run` commands exist?
- Are the documented options valid?
- Are the expected results correct?

**E. Configuration**

- Do the mentioned config files exist?
- Are the documented options supported?
- Are the default values accurate?

### 3. Gap identification

For each inconsistency found, note:

- **Type**: Missing feature, broken example, changed API, obsolete config
- **Severity**: 🔴 Critical (false information) | 🟡 Moderate (incomplete) | 🟢 Minor (detail)
- **Location**: File and line
- **Impact**: Who is affected (users, contributors, deployment)

### 4. Report generation

Produce an audit report:

```markdown
# Documentation vs Code Audit

## Summary

- **Files checked**: X docs, Y code files
- **Gaps found**: Z problems
- **Severity**: A critical 🔴, B moderate 🟡, C minor 🟢

---

## 🔴 Critical gaps

### 1. "scroll-manager" section not documented

- **Doc**: No mention in README.md
- **Code**: `src/core/scrollManager.ts` exists and is functional
- **Impact**: Users don't know the feature exists
- **Fix**: Add section to README.md with usage

### 2. `updateSection()` API — obsolete parameters

- **Doc**: `updateSection(section: SectionLifecycle)`
- **Code**: `updateSection(section: SectionLifecycle, options?: UpdateOptions)`
- **Impact**: Examples don't compile with new options
- **Fix**: Update JSDoc and README with options param

---

## 🟡 Moderate gaps

### 3. Missing npm run test script

- **Doc**: README mentions `npm run test`
- **Code**: package.json has this script
- **Impact**: None — the script exists
- **Fix**: No correction needed

---

## 🟢 Minor gaps

### 4. Outdated UI screenshot

- **Doc**: Screenshot shows old design
- **Code**: UI has been redesigned
- **Impact**: Minor visual confusion
- **Fix**: Update screenshot

---

## Recommended actions

### Priority 1 (Critical)

1. [ ] Document scroll-manager section in README.md
2. [ ] Fix updateSection() signature in docs and JSDoc

### Priority 2 (Moderate)

3. [ ] Add test script or remove from docs
4. [ ] Verify all code examples compile

### Priority 3 (Minor)

5. [ ] Update UI screenshots
6. [ ] Harmonize example formatting

---

## Proposed corrections

### README.md

\`\`\`diff

- ## Scroll Manager
- Synchronizes page scroll with 3D animations.
-
- \`\`\`typescript
- import { ScrollManager } from './core/scrollManager';
- const manager = new ScrollManager({ smooth: true });
- \`\`\`
  \`\`\`

### src/core/scrollManager.ts

\`\`\`diff
/\*\*

- - - Synchronizes a section with scroll
- - - @param section - The section to update
- - - @param options - Update options (optional)
- - - @param options.smooth - Enable smooth scroll
      \*/
      \`\`\`
```

### 5. Validation

After corrections, verify:

- ✅ All doc examples compile
- ✅ All documented commands work
- ✅ Screenshots match current UI
- ✅ Documented types match the code
- ✅ No undocumented features

## Verification checklist

### General documentation

- [ ] README.md reflects current features
- [ ] Table of contents is up to date
- [ ] Badges (CI, coverage) are correct
- [ ] Installation/setup is valid
- [ ] Examples work

### Technical documentation

- [ ] Architecture diagrams are up to date
- [ ] API docs match the code
- [ ] Types/interfaces are documented
- [ ] Contribution guides are valid

### Code examples

- [ ] Correct syntax
- [ ] Valid imports
- [ ] Existing APIs used
- [ ] Expected results are correct

### Configuration

- [ ] Documented npm scripts exist
- [ ] Config options are supported
- [ ] Default values are accurate
- [ ] Referenced files exist

## Tools

- `Grep`: Find mentions and patterns in code
- `Read`: Examine docs and code
- `Glob`: List documentation files
- `Bash`: Test documented commands

Provide a complete, actionable audit that facilitates bringing documentation in line with the actual code.
