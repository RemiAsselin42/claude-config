# Pitfalls log

Append-only log of the non-obvious problems Claude Code ran into while working in this repo: behaviours that are not visible from the code, traps that cost a session, assumptions that turned out wrong. Read it before touching an area it mentions. Append an entry whenever a session hits something that would have been faster to know up front.

Rules:

- One entry per issue, newest at the bottom. If the issue already has an entry, update it instead of adding another.
- Record the symptom, the real cause, and what to do about it. A status of `open` means the trap is still in the code; `fixed <sha>` means it is gone but the lesson stays.
- Keep each entry under ten lines. Long investigations belong in a commit message or `context/constraints.md`; link them from here.

## Entry format

```markdown
### YYYY-MM-DD — short title
- **Area:** file or component
- **Symptom:** what was observed
- **Cause:** why it happens
- **Workaround / fix:** what to do now
- **Status:** open | fixed <sha>
```

## Entries

### 2026-10-03 — Every install wipes `~/.claude/agents/`
- **Area:** `install.sh` (mirror loop, around lines 948-972)
- **Symptom:** agent files present in `~/.claude/agents/` disappear after running `install.sh`.
- **Cause:** `commands/` and `agents/` are mirrored, not merged: any deployed file without a matching source in the repo is removed. The repo ships no `agents/` directory, so the mirror pass deletes everything.
- **Workaround / fix:** keep agents elsewhere, or drop `agents` from the mirror loop (or skip the mirror when the source directory is absent). The README warns about it; the code fix is pending.
- **Status:** open
