---
description: 'Analyzes and evaluates changes since the last commit.'
argument-hint: '[specific files or features to analyze, or empty to analyze everything]'
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read, Grep, Glob
context: fork
agent: agent
---

## Analysis scope

"$ARGUMENTS"

## Current repository state

!`git status`

## Changes summary

!`git diff --stat`

## Objective

Provide a critical and constructive analysis of recent changes to ensure quality, maintainability, and healthy project evolution.

## Evaluation process

### 1. Collecting changes

**a. Inspecting Git state**

```bash
rtk git diff                      # Detailed differences
rtk git log -1 --stat            # Last commit (if already committed)
```

**b. Reading context**

- Use `Read` to examine modified files
- Use `Grep` to understand usage of added functions
- Use `Glob` to explore project structure

**c. Categorizing changes**

- **New features**: Feature additions
- **Fixes**: Bug resolutions
- **Refactoring**: Improvement of existing code
- **Style**: Formatting and conventions
- **Tests**: Addition or modification of tests
- **Documentation**: Doc updates
- **Infrastructure**: Config, build, dependencies

### 2. Analyzing significant changes

For each modified file, identify:

**a. Nature of changes**

- Added vs deleted lines
- Complexity (simple formatting vs complex business logic)
- Scope (local vs global impact)
- Code type (production, tests, config)

**b. Functional impact**

- New behaviors introduced
- Existing behaviors modified
- Removed functionality
- Changed APIs (breaking changes?)

**c. Technical impact**

- Architecture: New patterns, module dependencies
- Performance: Potential optimizations or degradations
- Security: New vulnerabilities or fixes
- Maintainability: Readability, complexity, duplication

### 3. Qualitative evaluation

**a. Architectural integration**

- ✅ Do the changes follow the existing architecture?
- ✅ Are new modules/components well-placed?
- ✅ Are dependencies managed correctly?
- ✅ Is excessive coupling introduced?
- ⚠️ Are abstractions missing?

**b. Code quality**

- ✅ Is the code readable and understandable?
- ✅ Are names explicit and consistent?
- ✅ Is complexity under control?
- ✅ Is there code duplication?
- ✅ Are TypeScript types used correctly?
- ⚠️ Presence of `any`, magic numbers, dead code?

**c. Tests and validation**

- ✅ Do tests accompany new code?
- ✅ Is test coverage maintained/improved?
- ✅ Are tests relevant and complete?
- ⚠️ Are there untested edge cases?

**d. Documentation**

- ✅ Is the code self-documenting?
- ✅ Do comments explain complex logic?
- ✅ Is external documentation up to date?
- ⚠️ Do any READMEs need updating?

### 4. Risk identification

Systematic analysis of potential risks:

**🔴 Critical risks**

- Undocumented breaking changes
- Introduced security vulnerabilities
- Memory leaks or severe performance issues
- Possible data loss or corruption
- Regression of existing functionality

**🟡 Moderate risks**

- Excessive complexity in business logic
- Circular dependencies
- Tight coupling between modules
- Increased technical debt
- Insufficient tests for new code
- Large file (>500 lines) hard to maintain

**🟢 Minor attention points**

- Inconsistent naming conventions
- Non-standard formatting
- Missing comments
- Incomplete documentation
- Missed optimization opportunities

### 5. Identifying positives

Recognize good practices:

- Well-thought-out and extensible architecture
- Elegant and idiomatic code
- Complete tests with good coverage
- Clear and comprehensive documentation
- Optimized performance
- Accessibility considered
- Robust error handling

- Refactoring that improves readability
- Bug fixes with non-regression tests
- Respect for project conventions
- Improved maintainability
- Reduced complexity

### 6. Improvement suggestions

Propose concrete and actionable improvements:

**Priority improvements**

- Critical risk fixes
- Adding missing tests
- Refactoring overly complex code
- Documenting unclear points

**Secondary improvements**

- Extracting functions to reduce complexity
- Adding stricter types
- Improving error handling
- Performance optimizations
- Reducing duplication

**Recommended improvements**

- Cosmetic refactoring
- Adding useful comments
- Style harmonization
- Accessibility improvements

## Report format

Generate a structured and actionable report:

````markdown
# Change Evaluation

## Files analyzed

### `src/sections/01-hero/hero.ts` (+45, -12)

**Type**: New feature
**Changes**: Added automatic 3D model rotation animation
**Impact**: Major - Improves visual experience of hero section

### `src/sections/sectionManager.test.ts` (+78, -0)

**Type**: Tests
**Changes**: Complete test suite for section management
**Impact**: Positive - 95% coverage

---

## Strengths

### Architecture and design

- ✅ **Consistent patterns**: Uses same patterns as other existing features

### Code quality

- ✅ **Strict types**: Excellent TypeScript usage with zero `any`
- ✅ **Readability**: Explicit function names and self-documenting code
- ✅ **Error handling**: Appropriate try/catch with clear messages

### Tests and validation

- ✅ **Excellent coverage**: 95% coverage on new code
- ✅ **Relevant tests**: Covers nominal cases and edge cases
- ✅ **Appropriate mocks**: Three.js objects properly mocked

### Documentation

- ✅ **README.md up to date**: Clear documentation of new feature
- ✅ **Useful comments**: Explanations of complex logic

---

## Risks and attention points

### 🔴 Critical risks

- **Potential vulnerability**: Rendering complex 3D objects could cause lag on low-end configs

### 🟡 Moderate risks

1. **Potential performance**
   - **Where**: `scrollManager.ts:45-67` - Animation calculations on each frame
   - **Impact**: Possible framerate degradation on complex scenes (>500 objects)
   - **Mitigation**: Add LOD system or optimize calculations
2. **Coupling with Three.js API**
   - **Where**: `glbModel.ts:23` - Direct dependency on Three.js internals
   - **Impact**: Risk of breaking change if Three.js modifies its API
   - **Mitigation**: Add abstraction layer or guards

### 🟢 Minor attention points

1. **Inconsistent formatting**
   - Mix of single and double quotes in `scrollManager.ts`
   - Suggestion: Run Prettier on the file

2. **Missing edge case test**
   - Untested case: Section with deltaTime=0 AND infinite scroll
   - Suggestion: Add test `shouldHandleZeroDelta()`

---

## Improvement suggestions

### High priority (recommended to implement)

1. **Limit render complexity**

   ```typescript
   // In scrollManager.ts
   function updateSection(
     section: SectionLifecycle,
     deltaTime: number,
     maxDelta: number = 0.1
   ) {
     if (deltaTime > maxDelta) {
       console.warn('Delta too high, clamping to', maxDelta);
       deltaTime = maxDelta;
     }
     section.update(deltaTime, this.elapsedTime);
   }
   ```

2. **Add abstraction layer for Three.js**
   ```typescript
   // New file: src/core/objectHelpers.ts
   export const getObjectVisibility = (object: THREE.Object3D): boolean => {
     return object.visible && (object.userData.opacity ?? 1) > 0;
   };
   ```

### Medium priority (quality improvement)

3. **Extract scoring logic**
   - Score calculation is duplicated in several places
   - Suggestion: Centralize in `shared/score.ts`

4. **Improve error messages**
   - Current errors are generic
   - Suggestion: Add context (node name, type)

5. **Add performance tests**
   - Create benchmarks for complex scenes
   - Suggested file: `tests/performance/rendering.bench.ts`

### Low priority (nice-to-have)

6. **Harmonize code style**
   - Run Prettier with `--write` on all modified files

7. **Improve interface accessibility**
   - Add `aria-label` to interactive controls
   - Add `role="status"` to loading indicators

8. **Technical documentation**
   - Add sequence diagram for detection flow
   - Document algorithmic complexity of traversal

---

## Recommended actions

### Before merging

- [ ] Implement deltaTime clamping (moderate risk)
- [ ] Add missing edge case test (null deltaTime)
- [ ] Run Prettier on modified files

### After merge

- [ ] Create issue for Three.js abstraction layer
- [ ] Implement performance tests (benchmark)
- [ ] Update architecture diagram in `/docs`

### Optional

- [ ] Scoring system refactoring (can be done later)
- [ ] Accessibility improvements (progressive)

---

## Metrics

| Metric                  | Before | After  | Evolution    |
| ----------------------- | ------ | ------ | ------------ |
| Lines of code           | 2,345  | 2,468  | +123 (+5.2%) |
| Test coverage           | 87%    | 91%    | +4% ✅       |
| Cyclomatic complexity   | 245    | 267    | +22 ⚠️       |
| Files                   | 42     | 45     | +3           |
| Dependencies            | 18     | 18     | =            |
````
