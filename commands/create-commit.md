---
description: Create git commit.
argument-hint: '[commit context or suggested message, or empty to analyze automatically]'
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*), Bash(git restore:*)
---

# Create Logical and Descriptive Commits

You are a Git expert who helps create high-quality commits. Your role is to analyze changes, organize them into logical commits, and execute commits with clear and descriptive messages.

Context or suggested message: $ARGUMENTS

## Process

### 1. Inspect current state

Start by examining the repository state:

- `rtk git status`: list modified files
- `rtk git diff`: show unstaged changes
- `rtk git diff --stat`: summary of changes if numerous

### 2. Analyze changes

For each modified file, identify:

- The type of change (feature, fix, refactor, style, test, docs, perf, chore)
- The affected scope (component, module, or project area)
- Related changes vs. independent ones

### 3. Define commit boundaries

**Splitting criteria:**

- Feature vs refactoring
- Backend vs frontend
- Formatting vs logic
- Tests vs production code
- Dependency updates vs behavior changes
- Changes in different modules/features

**Golden rule:** One commit = one coherent logical change that could be reverted independently.

### 4. Selective staging

For each identified logical commit:

- Use `rtk git add -p` for interactive staging if changes are mixed in a file
- Use `rtk git add <file>` to add entire files
- Use `rtk git restore --staged <file>` to unstage if needed

### 5. Pre-commit verification

Before each commit, verify staged changes:

- `rtk git diff --cached`: shows exactly what will be committed
- Verify absence of:
  - Secrets or tokens
  - Accidental debug logs
  - Unrelated formatting changes
  - Unnecessary commented code

### 6. Writing the commit message

**Conventional Commits format (REQUIRED):**

```
type(scope): short summary (max 72 characters)

Message body explaining:
- What changes were made
- Why these changes were necessary
- What impact they have on the project

BREAKING CHANGE: description if applicable
```

**Body layout rules (REQUIRED):**

- **Continuous text:** write paragraphs on a single line without manual line breaks mid-sentence. Never break a sentence to respect a visual width.
- **Separation:** keep a blank line between logical paragraphs.
- **Bullet lists (recommended when many changes):** each bullet item = one complete single line. Bullets improve readability and are the preferred format for enumerating multiple changes.

**Commit types:**

- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Refactoring without behavior change
- `style`: Formatting, semicolons, etc.
- `test`: Adding or modifying tests
- `docs`: Documentation only
- `perf`: Performance improvement
- `chore`: Maintenance tasks (deps, config, etc.)
- `build`: Build system changes
- `ci`: CI/CD changes

**Message examples:**

```
feat(scroll-manager): add synchronization with 3D sections

Implements a system that synchronizes page scroll with Three.js object animations. Uses Lenis for smooth scroll with visible section detection and fluid transitions.

Impact: improves user experience fluidity.

fix(beatmaker): fix audio sample timing

Samples between 0.5 and 1.5 seconds were incorrectly offset. Uses requestAnimationFrame instead of setTimeout to respect precise audio synchronization.

Fixes #42

refactor(ui): simplify modal component rendering

Changes made:
- extracted display logic into a custom useModalState hook
- removed 3 redundant style files
- consolidated two button variants into one with `variant` prop

Impact: reduces CSS bundle size by 15% and improves modal code maintainability.
```

### 7. Executing the commit

- Use `git commit -v` to see the diff while writing
- Or `git commit -m "type(scope): message"` for short messages
- For multi-line messages, prefer `git commit -F <message_file>`
  or `git commit` (interactive editor) to ensure real line breaks
  in the body.
- **Body structure:** write continuous paragraphs on a single line, separated by blank lines. Bullet lists remain the exception where each item is a distinct line (recommended when there are many changes).
- Never use literal `\n` sequences in `-m` arguments.
- Important: each `-m` option creates a distinct paragraph. Never do
  `-m` line by line, otherwise the message contains unnecessary blank lines.
- If `-m` is needed in CLI, limit to:
  - one `-m` for the subject
  - one single `-m` for the entire body (multi-line in a single block)
- After commit, systematically verify the exact rendering with
  `rtk git log -1 --pretty=%B`.
- Execute the command and display the result

### 8. Quick verification

After each commit:

- Show hash and message: `rtk git log -1 --oneline`
- Verify tests pass (if applicable): `rtk npm test` or equivalent
- Continue with the next commit

### 9. Iteration

Repeat steps 4 to 8 until `rtk git status` is clean.

## Deliverables

For each commit session, provide:

1. **Summary of commits created:**
   - Hash and message of each commit
   - List of files included per commit
2. **Splitting rationale:**
   - Why these specific groupings
   - What criteria guided the separation

3. **Commands executed:**
   - All git commands used
   - Result of `rtk git diff --cached` before each commit

## Principles to follow

✅ **DO:**

- Commit messages in English, clear and descriptive
- Logical and coherent splitting
- Selective staging with `rtk git add -p` when needed
- Systematic verification with `rtk git diff --cached`
- Messages in imperative present ("add", "fix", "update")
- Message body that explains the "why", not the "how"
- Do not add "Co-authored-by" mentions in commit messages — handle that yourself afterward if needed
- Use appropriate commit types (feat, fix, refactor, etc.)
- Use relevant scopes to specify affected areas
- Use bullet lists in the message body when there are many changes to enumerate

## Reference

For more details on commit best practices, see:

- `.claude/skills/commit-work/SKILL.md`
- `.claude/skills/commit-work/README.md`

Apply these principles rigorously to create a clean, readable, and professional git history.
