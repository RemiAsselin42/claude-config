---
description: 'Analyzes code comments: presence, relevance, quality, language, and technical debt.'
argument-hint: '[specific directory or file, or empty to analyze the entire project]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(wc:*), Bash(git log:*)
context: fork
agent: agent
---

## Analysis scope

"$ARGUMENTS"

## Objective

Produce a complete audit of project comments: their presence, actual utility, editorial quality, languages used, documented debt (TODO/FIXME), and dead code hidden by comments. This analysis does not judge code logic — only what is written _about_ the code.

## Process

### 0. Scope collection

```bash
# Source files to analyze
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \) \
  | sort

# Total line volume
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" \) \
  -exec wc -l {} \; 2>/dev/null | tail -1
```

If `$ARGUMENTS` is provided, restrict the analysis to that path.

---

### 1. Comment presence and density

**a. Global comments / code ratio**

```bash
# Comment lines (// and #)
grep -rn "^\s*//" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
grep -rn "^\s*#" src/ --include="*.py" 2>/dev/null | wc -l

# Comment blocks /* ... */
grep -rn "^\s*/\*" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l

# Total source code lines (excluding comments and blank lines)
grep -rn "^\s*[^/# \t]" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
```

**b. Distribution by file**

For each file, calculate the comment/code ratio. Identify:

- **Over-commented** files (> 40% comments, often dead code or redundancy)
- **Under-commented** files (0% comments despite visible complexity)

```bash
# Files with no comment lines
for f in $(find src/ -name "*.ts" -not -name "*.d.ts" 2>/dev/null); do
  count=$(grep -c "^\s*//" "$f" 2>/dev/null || echo 0)
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ] && [ "$lines" -gt 30 ]; then
    echo "$lines lines, 0 comments: $f"
  fi
done
```

**c. Critical silent zones**

When reading files, note functions > 20 lines with no comments AND whose logic is non-trivial. These are priority candidates for documentation.

---

### 2. Relevance and utility

For a representative sample of comments (read the most commented files), classify each comment:

| Category      | Definition                                                  | Example                                                                    |
| ------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Useful**    | Explains the _why_, a non-obvious choice, a workaround      | `// Cache disabled here — the third-party API returns stale data`          |
| **Redundant** | Paraphrases what the code already says                      | `// Increment counter` in front of `counter++`                             |
| **Obsolete**  | References deleted code, closed tickets, non-existent API   | `// cf. issue #234` when the ticket no longer exists                       |
| **Misleading**| Contradicts what the code actually does                     | `// Returns null on error` when the function throws                        |

```bash
# Look for indicators of stale comments
grep -rn "TODO\|FIXME\|deprecated\|old\|legacy\|remove\|dead\|unused" src/ \
  --include="*.ts" --include="*.js" -i 2>/dev/null | grep "//" | head -30

# Look for very short single-line comments (potentially redundant)
grep -rn "^\s*//.\{1,15\}$" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -30
```

When reading files, manually evaluate the relevance of found comments.

---

### 3. Editorial quality

**a. Style and consistency**

```bash
# Proportion of //  vs /* */ vs /** */ (JSDoc)
echo "// inline:" && grep -rn "^\s*//" src/ --include="*.ts" 2>/dev/null | grep -v "^\s*///" | wc -l
echo "/** JSDoc:" && grep -rn "^\s*/\*\*" src/ --include="*.ts" 2>/dev/null | wc -l
echo "/* block :" && grep -rn "^\s*/\*[^*]" src/ --include="*.ts" 2>/dev/null | wc -l
```

Detect inconsistencies: same type of element (utility function) documented with `//` in one file and `/** */` in another.

**b. Quick note quality**

```bash
# Vague single-line comments (low-quality signals)
grep -rn "^\s*// \(fix\|temp\|old\|test\|todo\|hack\|wip\|remove\|check\|wtf\|idk\|????\|!!!\)" \
  src/ --include="*.ts" --include="*.js" -i 2>/dev/null | head -30
```

**c. Completeness of formal documentation (JSDoc/TSDoc)**

```bash
# Exported functions/methods without JSDoc
grep -rn "^export function\|^export const.*=.*(" src/ --include="*.ts" 2>/dev/null | head -40
```

For each exported public function/class, check if it is preceded by a `/** */` block. Evaluate completeness:

- `@param` present for each parameter?
- `@returns` present if the function returns a non-trivial value?
- `@throws` present if the function can throw?
- `@example` present for complex utilities?

---

### 4. Language(s) used

**a. Language detection**

Analyze text comments to identify the language(s) used. Indicative patterns:

```bash
# Common French words in comments
grep -rn "//.*\b\(le\|la\|les\|de\|du\|des\|et\|est\|un\|une\|pour\|avec\|sur\|dans\|par\|qui\|que\)\b" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l

# Common English words in comments
grep -rn "//.*\b\(the\|this\|that\|with\|from\|when\|where\|should\|return\|handle\|check\|get\|set\)\b" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
```

**b. Multilingual files**

When reading files, identify those containing comments in multiple languages — often a sign of contributions from different developers without an established convention.

**c. Inventory and recommendation**

Produce a table:

| Language | Estimated (%) | Main files                     |
| -------- | ------------- | ------------------------------ |
| English  | X%            | `src/api/...`, `src/core/...`  |
| French   | Y%            | `src/services/...`             |
| Other    | Z%            |                                |

Propose the target normalization language considering the current proportion and project context (team, documentation audience).

---

### 5. TODOs / FIXMEs / HACKs (documented debt)

**a. Exhaustive inventory**

```bash
# All debt markers
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|TEMP\|NOTE:" \
  src/ --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --include="*.py" --include="*.go" 2>/dev/null | grep -v node_modules | sort
```

**b. Dating via Git**

For critical markers (`FIXME`, `BUG`, `HACK`), try to estimate their age:

```bash
# Date of last commit touching these lines (requires git)
rtk git log --all -p --follow -- src/ | grep -A2 "FIXME\|BUG\|HACK" | head -40
```

**c. Classification by criticality**

| Level      | Markers                  | Suggested action                    |
| ---------- | ------------------------ | ----------------------------------- |
| 🔴 Critical | `FIXME`, `BUG`          | Fix before any prod merge           |
| 🟡 Moderate | `HACK`, `XXX`           | Plan in backlog                     |
| 🟢 Minor    | `TODO`, `NOTE:`, `TEMP` | To do but not blocking              |

---

### 6. Commented code (hidden dead code)

**a. Detecting commented code blocks**

```bash
# Multiple consecutive commented lines with code (presence of ; or () or =)
grep -rn "^\s*//.*[;(){}\[\]=]" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -40

# Same for Python
grep -rn "^\s*#.*[()=:\[\]]" src/ --include="*.py" 2>/dev/null | head -20
```

When reading files, identify commented code blocks (consecutive lines starting with `//` or `#` containing code syntax, not text).

**b. Classification by size**

- **🔴 > 10 lines**: Deletion strongly recommended — git history preserves the code
- **🟡 3-10 lines**: Delete or convert to disabled test (`it.skip`)
- **🟢 1-2 lines**: Watch, often a forgotten debug statement

---

## Report format

```markdown
# Comment Analysis Report

## Dashboard

| Dimension              | Score      | Summary  |
| ---------------------- | ---------- | -------- |
| Presence and density   | ⭐⭐⭐☆☆  | [summary]|
| Relevance and utility  | ⭐⭐⭐⭐☆ | [summary]|
| Editorial quality      | ⭐⭐☆☆☆   | [summary]|
| Language consistency   | ⭐⭐⭐☆☆  | [summary]|
| Debt (TODOs/FIXMEs)    | ⭐⭐⭐☆☆  | [summary]|
| Commented code         | ⭐⭐⭐⭐☆ | [summary]|

**Overall score**: XX/30

---

## 1. Presence and density

**Global ratio**: ~X% of lines are comments

### Under-documented zones (complex files without comments)

| File                 | Lines | Comments | Estimated complexity |
| -------------------- | ----- | -------- | -------------------- |
| `src/core/parser.ts` | 312   | 0        | High                 |

### Over-commented zones (> 40%)

| File                    | Lines | % Comments | Probable cause |
| ----------------------- | ----- | ---------- | -------------- |
| `src/legacy/old-api.ts` | 180   | 55%        | Commented code |

---

## 2. Relevance and utility

### Useful comments (notable examples)

- `src/auth/jwt.ts:34` — Explains why the token is verified twice (known race condition)

### Redundant comments

- `src/utils/format.ts:12` — `// format the date` in front of `formatDate(date)` — remove

### Obsolete comments

- `src/api/user.ts:78` — References `#issue-123` and `OldUserAPI` that no longer exist

### Misleading comments

- `src/db/query.ts:45` — Says `// returns null if not found` but the function throws

---

## 3. Editorial quality

**Dominant style**: `//` inline (X%), `/** JSDoc */` (Y%), `/* block */` (Z%)

### Style inconsistencies

- `src/services/`: mixes `//` and `/** */` for the same types of functions

### Vague notes identified

| Comment  | File                    | Problem                    |
| -------- | ----------------------- | -------------------------- |
| `// fix` | `src/api/handler.ts:23` | No context                 |
| `// temp`| `src/cache/index.ts:67` | Since when?                |

### JSDoc coverage of public exports

- **Exported functions with JSDoc**: X / Y (Z%)
- **Without @param**: N occurrences
- **Without @returns**: N occurrences

---

## 4. Language(s) used

| Language | Estimated | Files                         |
| -------- | --------- | ----------------------------- |
| English  | 65%       | `src/core/`, `src/api/`       |
| French   | 33%       | `src/services/`, `src/utils/` |
| Mixed    | 2%        | `src/legacy/`                 |

**Recommendation**: Normalize to **[English / French]**
**Reason**: [majority language / team language / project convention]

### Multilingual files to prioritize

- `src/services/UserService.ts` — 12 FR comments, 8 EN comments in the same file

---

## 5. TODOs / FIXMEs / HACKs

**Total**: N markers (X critical, Y moderate, Z minor)

### 🔴 Critical (FIXME / BUG)

| Marker  | File                     | Content                                        | Estimated age |
| ------- | ------------------------ | ---------------------------------------------- | ------------- |
| `FIXME` | `src/auth/session.ts:34` | `// FIXME: session expires too early on mobile` | ~6 months    |

### 🟡 Moderate (HACK / XXX)

| Marker | File                | Content                                 |
| ------ | ------------------- | --------------------------------------- |
| `HACK` | `src/db/pool.ts:12` | `// HACK: workaround for pg driver bug` |

### 🟢 Minor (TODO / NOTE)

- `src/utils/date.ts:56` — `// TODO: add timezone support`
- `src/api/routes.ts:23` — `// TODO: add rate limiting`

---

## 6. Commented code

### 🔴 Blocks > 10 lines (delete)

- `src/legacy/old-api.ts:45-67` — 23 lines of commented code (`OldApiClient`)
  - Action: delete — code is in git history

### 🟡 Blocks 3-10 lines

- `src/utils/cache.ts:12-15` — 4 lines of commented alternative implementation

### 🟢 Isolated lines

- `src/api/handler.ts:89` — `// console.log(response)` — forgotten debug

---

## Action plan

### High priority

- [ ] Handle the N `FIXME`/`BUG` — see section 5
- [ ] Delete commented code blocks > 10 lines — see section 6
- [ ] Fix misleading comments — see section 2

### Medium priority

- [ ] Normalize language to [English/French] in multilingual files
- [ ] Add JSDoc to N undocumented public functions
- [ ] Delete or complete vague notes (`// fix`, `// temp`)

### Low priority

- [ ] Harmonize comment style (`//` vs `/** */`)
- [ ] Handle minor TODOs in backlog

---

## Metrics

| Metric                               | Value     |
| ------------------------------------ | --------- |
| Files analyzed                       | N         |
| Comment/code ratio                   | X%        |
| Files without comments (> 30 lines)  | N         |
| TODOs/FIXMEs total                   | N         |
| Commented code blocks                | N         |
| Detected languages                   | [FR, EN]  |
| Public exports without JSDoc         | N / M     |
```
