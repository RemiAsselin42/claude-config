---
description: 'Audit of the technology stack: languages, dependencies, versions, APIs, tools, and synergy.'
argument-hint: '[specific aspect to analyze, or empty for a complete audit]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(cat:*), Bash(npm outdated:*), Bash(npm audit:*), Bash(npm ls:*)
context: fork
agent: agent
---

## Analysis scope

"$ARGUMENTS"

## Objective

Produce a complete audit of the project's technology stack: language relevance, dependency quality and state, documentation consistency, external integrations, build tools, and overall synergy. This analysis focuses on technology choices themselves, not business logic.

## Process

### 0. Initial orientation

```bash
# Dependency manifest files present
find . -maxdepth 2 -not -path '*/node_modules/*' \
  \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" \
     -o -name "go.mod" -o -name "pom.xml" -o -name "build.gradle" \
     -o -name "requirements*.txt" -o -name "Gemfile" \) | sort

# Runtime version
node --version 2>/dev/null
python --version 2>/dev/null
go version 2>/dev/null
```

Read `package.json` (or equivalent) for the complete dependency list before continuing.

If `$ARGUMENTS` is provided, focus the analysis on that aspect or subsystem.

---

### 1. Languages used

**a. Detection and proportion**

```bash
# Count files by extension (excluding node_modules, dist, build)
find . -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/.git/*' -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20
```

**b. Language value-add**

Evaluate whether the chosen language provides real value in the project context:

| Situation                                                        | Signal              | Recommendation                  |
| ---------------------------------------------------------------- | ------------------- | ------------------------------- |
| `.js` and `.ts` files coexist without reason                     | Inconsistent mix    | Migrate to full TypeScript       |
| TypeScript present but `strict: false` and `any` everywhere      | TS underused        | Enable strict progressively      |
| Python without type annotations on project > 500 lines           | Missing typing      | Add mypy / pyright               |
| Complex shell scripts that could be TypeScript/Python            | Wrong tool          | Consider rewriting               |

```bash
# Detect .js files next to .ts (mix)
find src/ -name "*.js" -not -name "*.config.js" -not -name "*.test.js" 2>/dev/null | head -20
```

**c. Runtime version**

Check declared version in `.nvmrc`, `engines` in `package.json`, `.python-version`, etc.:

```bash
cat .nvmrc 2>/dev/null
cat .node-version 2>/dev/null
```

- Current Node.js LTS: v20 / v22 (2025). Versions < 18 = EOL.
- Current Python LTS: 3.11+. Versions < 3.9 = end of support.

---

### 2. Direct dependencies — relevance and redundancy

**a. Complete list**

```bash
# npm dependencies (production + dev)
cat package.json 2>/dev/null | grep -A200 '"dependencies"'
```

**b. Unused dependencies**

For each listed dependency, check if it is actually imported in the source code:

```bash
# Check if a package is imported in the code
# (run for each package listed in dependencies)
grep -rn "from '[PACKAGE_NAME]'\|require('[PACKAGE_NAME]')" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -5
```

Identify packages in `package.json` with no import occurrences in `src/`.

**c. Redundant dependencies**

Look for functional overlaps:

| Category         | Signs of redundancy             |
| ---------------- | ------------------------------- |
| HTTP client      | `axios` + `node-fetch` + `got`  |
| Dates            | `moment` + `date-fns` + `dayjs` |
| State management | `redux` + `zustand` + `jotai`   |
| Validation       | `joi` + `zod` + `yup`           |
| ORM              | `prisma` + `typeorm`            |
| Utilities        | `lodash` + `ramda`              |

```bash
# Look for competing library imports
grep -rn "from 'axios'\|from 'node-fetch'\|from 'got'\|from 'ky'" src/ --include="*.ts" --include="*.js" 2>/dev/null
grep -rn "from 'moment'\|from 'date-fns'\|from 'dayjs'" src/ --include="*.ts" --include="*.js" 2>/dev/null
```

**d. Replaceable by native APIs**

Identify superfluous dependencies given available modern APIs:

| Package              | Native alternative                              |
| -------------------- | ----------------------------------------------- |
| `lodash.clonedeep`   | `structuredClone()` (Node 17+)                  |
| `lodash.isequal`     | Native comparison or `JSON.stringify`           |
| `moment`             | `Intl.DateTimeFormat`, `date-fns` (lighter)     |
| `request` (deprecated) | `fetch` native (Node 18+)                     |
| `uuid`               | `crypto.randomUUID()` (Node 14.17+)             |
| `mkdirp`             | `fs.mkdir({ recursive: true })`                 |

**e. Misclassified dependencies (dev vs prod)**

```bash
cat package.json 2>/dev/null
```

Flag:

- Build tools (`typescript`, `vite`, `esbuild`) in `dependencies` → should be `devDependencies`
- Types (`@types/*`) in `dependencies` → should be `devDependencies`
- Runtime libraries (`express`, `zod`) in `devDependencies` → should be `dependencies`

---

### 3. Versions, updates, and lifecycle

**a. Outdated dependencies**

```bash
rtk npm outdated
```

**b. Vulnerability audit**

```bash
rtk npm audit
```

**c. Abandoned or deprecated dependencies**

```bash
# Check for deprecation messages in npm
rtk npm ls | grep -i "deprecated\|WARN"
```

When analyzing, flag packages:

- Without updates for > 2 years and with little activity (replace)
- Marked `deprecated` on npm
- Whose maintainer has announced end of maintenance (e.g. `node-sass`, `request`, `tslint`)

**d. Version lag classification**

| Lag                                  | Severity | Action                                             |
| ------------------------------------ | -------- | -------------------------------------------------- |
| Major version (e.g. v1 → v3)         | 🔴       | Planned update — risk of breaking changes          |
| Minor version (e.g. v3.1 → v3.4)     | 🟡       | Update recommended                                 |
| Patch version (e.g. v3.4.0 → v3.4.2) | 🟢       | Simple update                                      |

---

### 4. Dependency security

```bash
rtk npm audit --json | head -100
```

Classify vulnerabilities by severity:

| Level              | Action                                    |
| ------------------ | ----------------------------------------- |
| 🔴 Critical / High | Fix immediately (`npm audit fix`)          |
| 🟡 Moderate        | Plan the update                           |
| 🟢 Low             | Monitor                                   |

For each critical vulnerability, indicate: affected package, CVE, available fixed version, fix command.

---

### 5. Documentation alignment

**a. Stack declared in documentation**

```bash
# Read main documentation files
cat README.md 2>/dev/null | head -100
find . -maxdepth 2 -name "CONTRIBUTING.md" -o -name "ARCHITECTURE.md" -o -name "TECH_STACK.md" 2>/dev/null | xargs cat 2>/dev/null | head -100
```

Extract the list of technologies explicitly mentioned.

**b. Documentation vs reality comparison**

| Situation                                                             | Severity                              |
| --------------------------------------------------------------------- | ------------------------------------- |
| Technology in docs but no trace in code                               | 🔴 False or obsolete documentation    |
| Technology used intensively but not mentioned in docs                 | 🟡 Incomplete documentation           |
| Mentioned version different from installed version                    | 🟢 Documentation needs refreshing     |

---

### 6. External APIs and services

**a. Integration identification**

```bash
# Environment variables used (indicator of external integrations)
grep -rn "process\.env\." src/ --include="*.ts" --include="*.js" 2>/dev/null | sed 's/.*process\.env\.\([A-Z_]*\).*/\1/' | sort -u

# .env.example file
cat .env.example 2>/dev/null

# External URLs in code
grep -rn "https://" src/ --include="*.ts" --include="*.js" 2>/dev/null | grep -v "test\|spec\|\.d\.ts" | head -30
```

**b. Integration quality evaluation**

For each identified external service, check:

- **Official SDK used**? (e.g. `@aws-sdk/*`, `firebase`, `stripe`) or raw HTTP client without abstraction?
- **Error handling**: Are third-party API errors intercepted and transformed?
- **Centralized configuration**: Are keys/URLs in dedicated config files or scattered?
- **Hardcoded keys**:

```bash
# Potentially hardcoded API keys
grep -rn "sk_\|pk_\|api_key\|apiKey\|Bearer\|token.*=.*['\"]" src/ --include="*.ts" --include="*.js" 2>/dev/null | grep -v "process\.env\|\.env\|test\|spec" | head -20
```

---

### 7. Build tools and development chain

**a. Chain identification**

```bash
cat package.json 2>/dev/null | grep -A30 '"scripts"'
find . -maxdepth 2 -not -path '*/node_modules/*' \
  \( -name "vite.config*" -o -name "webpack.config*" -o -name "rollup.config*" \
     -o -name "jest.config*" -o -name "vitest.config*" -o -name ".eslintrc*" \
     -o -name "biome.json" -o -name ".prettierrc*" -o -name "babel.config*" \
     -o -name "tsconfig*.json" \) | sort
```

**b. Chain consistency and modernity**

Evaluate each tool:

| Role        | Preferred modern tool     | Legacy tools to flag               |
| ----------- | ------------------------- | ---------------------------------- |
| Bundler     | Vite, esbuild, Rollup     | Webpack 4 (slow, complex config)   |
| TS compiler | tsc, SWC                  | Babel alone without tsc for types  |
| Linter      | ESLint + TS rules, Biome  | TSLint (deprecated), JSHint        |
| Formatter   | Prettier, Biome           | No formatter at all                |
| Test runner | Vitest, Jest              | Mocha alone without assertion lib  |

Flag redundancies: Babel + SWC at the same time, ESLint + Biome both configured, etc.

**c. Missing scripts**

Check for essential scripts in `package.json`:

- `build` — production compilation
- `test` — test execution
- `lint` — style checking
- `dev` or `start` — development startup
- `type-check` — TypeScript check without emit

---

### 8. Stack synergy and consistency

**a. Responsibility overlaps**

Evaluate whether libraries step on each other:

```bash
# Detect competing state management library imports
grep -rn "from 'redux'\|from '@reduxjs'\|from 'zustand'\|from 'jotai'\|from 'recoil'\|from 'mobx'" \
  src/ --include="*.ts" --include="*.tsx" 2>/dev/null | cut -d: -f3 | sort -u

# HTTP clients
grep -rn "from 'axios'\|from 'node-fetch'\|from 'got'\|from 'ky'\|fetch(" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | cut -d: -f3 | sort -u
```

**b. Stack-to-project fit**

Evaluate whether choices are proportionate to the project:

| Signal                                                   | Problem                                                   |
| -------------------------------------------------------- | --------------------------------------------------------- |
| Next.js for a simple static page                         | Over-engineering                                          |
| Express.js for a complex API with auth, jobs, events     | Under-dimensioned (NestJS, Fastify would be more fitting) |
| React for a project with 2 pages and no complex state    | Overkill (HTML + Alpine.js would suffice)                 |
| Microservices for a solo project < 5K lines              | Premature                                                 |

**c. Tight coupling with a library**

When reading files, flag if source code is excessively coupled to a library's non-standard internal API (use of private methods, dependency on internal structure), which would make migration difficult.

---

### 9. Licenses

**a. License inventory**

```bash
# List licenses of direct dependencies
cat package.json 2>/dev/null | grep -E '"dependencies"|"devDependencies"' -A100 | grep '"' | head -60
```

When analyzing, note the license of each main dependency (available in `node_modules/[package]/package.json` or on npm).

**b. Compatibility**

| License             | Risk for a proprietary project                   |
| ------------------- | ------------------------------------------------ |
| MIT, ISC, BSD       | No risk                                          |
| Apache 2.0          | No risk (attribution required)                   |
| LGPL                | Risk if modifying LGPL code                      |
| GPL                 | 🔴 Incompatible with closed proprietary code      |
| AGPL                | 🔴 Very restrictive (network use = distribution)  |
| SSPL                | 🔴 Incompatible with commercial services          |
| Commercial license  | 🟡 Check usage rights                             |

---

## Report format

```markdown
# Technology Stack Audit

## Dashboard

| Dimension                  | Score      | Summary  |
| -------------------------- | ---------- | -------- |
| Languages                  | ⭐⭐⭐⭐☆  | [summary]|
| Dependency relevance       | ⭐⭐⭐☆☆   | [summary]|
| Versions and lifecycle     | ⭐⭐⭐☆☆   | [summary]|
| Security                   | ⭐⭐⭐⭐☆  | [summary]|
| Documentation alignment    | ⭐⭐☆☆☆    | [summary]|
| APIs and external services | ⭐⭐⭐⭐☆  | [summary]|
| Build tools                | ⭐⭐⭐☆☆   | [summary]|
| Stack synergy              | ⭐⭐⭐⭐☆  | [summary]|
| Licenses                   | ⭐⭐⭐⭐⭐ | [summary]|

**Overall score**: XX/45

---

## 1. Languages

**Detected languages**: TypeScript (85%), JavaScript (10%), Shell (5%)
**Runtime version**: Node.js 18.17.0 (LTS — ok)

### Attention points

- `src/utils/legacy.js` — unmigrated JavaScript file in a TypeScript project

---

## 2. Direct dependencies

### Unused (no import found)

| Package     | Classified in | Last usage found        |
| ----------- | ------------- | ----------------------- |
| `lodash`    | dependencies  | None — replaceable by native |
| `cross-env` | dependencies  | Should be devDependencies |

### Redundant

- `axios` AND `node-fetch` both imported — choose one or use native `fetch` (Node 18+)

### Replaceable by native

| Package  | Suggested replacement           | Gain          |
| -------- | ------------------------------- | ------------- |
| `uuid`   | `crypto.randomUUID()`           | -1 dependency |
| `mkdirp` | `fs.mkdir({ recursive: true })` | -1 dependency |

### Misclassified

- `typescript` in `dependencies` → move to `devDependencies`
- `@types/node` in `dependencies` → move to `devDependencies`

---

## 3. Versions and lifecycle

### Outdated dependencies

| Package    | Current  | Latest   | Lag     | Urgency |
| ---------- | -------- | -------- | ------- | ------- |
| `express`  | 4.18.0   | 5.0.1    | Major   | 🔴      |
| `zod`      | 3.20.0   | 3.23.8   | Minor   | 🟡      |
| `prettier` | 2.8.0    | 3.2.5    | Major   | 🔴      |

### Deprecated / abandoned dependencies

- `node-sass` — deprecated, replace with `sass` (Dart Sass)
- `request` — archived since 2020, replace with native `fetch`

---

## 4. Security

**Result**: N vulnerabilities (X critical, Y moderate, Z low)

### Critical vulnerabilities

| Package  | CVE            | Severity | Fixed version | Command                      |
| -------- | -------------- | -------- | ------------- | ---------------------------- |
| `lodash` | CVE-2021-23337 | Critical | 4.17.21       | `npm install lodash@4.17.21` |

---

## 5. Documentation alignment

### Detected gaps

| Technology  | In docs        | In code                       | Status                              |
| ----------- | -------------- | ----------------------------- | ----------------------------------- |
| PostgreSQL  | Mentioned      | No pg dependency found        | 🔴 False documentation              |
| Redis       | Not mentioned  | `ioredis` imported everywhere | 🟡 Not documented                   |
| Vue.js 2    | Mentioned      | Vue 3 used                    | 🟢 Wrong version in docs            |

---

## 6. External APIs and services

### Identified services

| Service  | SDK                   | Integration quality         | Hardcoded key? |
| -------- | --------------------- | --------------------------- | -------------- |
| Stripe   | `stripe` (official)   | Good — errors handled       | No             |
| SendGrid | Raw HTTP client       | Average — no abstraction    | No             |
| Firebase | `firebase` (official) | Good                        | No             |

### Potentially exposed keys

- `src/config/email.ts:12` — string resembling an API key not read from `.env`

---

## 7. Build tools

**Detected chain**:

- Bundler: Vite 5.x
- Compiler: tsc (strict)
- Linter: ESLint + @typescript-eslint
- Formatter: Prettier
- Tests: Vitest

### Issues

- `babel.config.js` present but Vite uses esbuild — Babel is unused, remove it
- `type-check` script absent from `package.json`

---

## 8. Stack synergy

### Identified overlaps

- `axios` + native `fetch` both used for HTTP calls — choose one
- `react-query` + `redux` for server state management — React Query is enough for server state

### Project fit

The stack (Next.js + Prisma + PostgreSQL + Zustand) is **well-sized** for a project of this scale (15K lines, team of 3).

---

## 9. Licenses

| Package     | License | Risk                                    |
| ----------- | ------- | --------------------------------------- |
| `react`     | MIT     | None                                    |
| `express`   | MIT     | None                                    |
| `[package]` | GPL-3.0 | 🔴 Incompatible with proprietary code   |

---

## Problems by severity

### 🔴 Critical

1. **Critical vulnerability in `lodash`**
   - **Fix**: `npm install lodash@4.17.21`

2. **GPL dependency in a proprietary project**
   - **Fix**: Replace `[package]` with an MIT alternative

### 🟡 Moderate

1. **`express` one major version behind** — migrate to Express 5 or Fastify

2. **`node-sass` deprecated** — `npm uninstall node-sass && npm install sass`

### 🟢 Minor

1. **`typescript` misclassified** — move from `dependencies` to `devDependencies`

---

## Action plan

### High priority (security and compatibility)

- [ ] `npm audit fix` — fix automatically fixable vulnerabilities
- [ ] Replace the incompatible GPL dependency
- [ ] `npm uninstall node-sass && npm install sass`

### Medium priority (updates and cleanup)

- [ ] `npm install express@5` — update Express
- [ ] `npm uninstall lodash axios` — remove dependencies replaceable by native
- [ ] Move misclassified devDependencies

### Low priority (optimization)

- [ ] Remove unused `babel.config.js`
- [ ] Add `type-check` script to `package.json`
- [ ] Update README to reflect actual stack

---

## Metrics

| Metric                  | Value             |
| ----------------------- | ----------------- |
| Detected languages      | N                 |
| Direct dependencies     | N (X prod, Y dev) |
| Unused dependencies     | N                 |
| Outdated dependencies   | N                 |
| Vulnerabilities         | N (X critical)    |
| External services       | N                 |
| Unique licenses         | N                 |
```
