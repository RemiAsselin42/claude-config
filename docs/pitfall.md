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

### 2026-10-03 — "Bash heredocs strip blank lines" was a hook, not Claude Code
- **Area:** `~/.claude/hooks/comment-strip.sh`, installed by `npx cc-safe-setup` from `install.sh` and registered as a PreToolUse hook on Bash
- **Symptom:** every Bash command containing a heredoc lost its blank lines and its `# …` lines (markdown titles included) when executed. Reported as a Claude Code bug on 2026-08-31 and worked around with the Write tool in CLAUDE.md.
- **Cause:** the hook runs `sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d'` over the whole command and hands the result back as `updatedInput`, heredoc contents included. Fed the payload `cat > x.md <<EOF` + `# Title` + a blank line, it returns the command without the title and without the blank line.
- **Workaround / fix:** cc-safe-setup is no longer run by `install.sh`; the three guards worth keeping are vendored in `hooks/`, the five others are deleted on every install and `_verify_legacy_cc_safe_hooks_removed` fails the install if one is left. On a machine where `install.sh` has not run since, the hook is still live.
- **Status:** fixed (cc-safe-setup removed from `install.sh`, guards vendored in `hooks/`)

### 2026-10-06 — `uv tool install --upgrade` deletes the venv when a shim is running
- **Area:** `install.sh` `_uv_tool_install`, uv 0.11.7 (same code in 0.12.23), Windows
- **Symptom:** `mempalace search` and the MCP server die at import (`No module named 'dotenv'`) while `mempalace --version` answers; uv says `Would make no changes`; `install.sh` prints `✓ MemPalace` on every run; the hooks silence it (`|| true`, `2>/dev/null`). Memory was off for two and a half days (2026-10-04 15:23 → 2026-10-07).
- **Cause:** the upgrade updates the venv in place, then replaces the `~/.local/bin` shims. A running `mempalace-mcp.exe` (one per open Claude Code session) cannot be replaced, and uv then removes the whole environment (`finalize_tool_install` → `remove_virtualenv`), file by file in alphabetical order, until the first `.pyd` a process has mapped. The dist-info directories that survive make uv count the packages as installed. The same happened on 09-03, 09-10 and 09-18; `graphifyy` is exposed the same way.
- **Workaround / fix:** the holders (venv processes and the shims themselves) are listed before uv runs and the upgrade is skipped unless the owner kills them; after uv, the venv's own interpreter must `import chromadb, mempalace` or the install stops red; `_mempalace_state` answers `broken` before anything else; `session-start.sh` prints one line when `wake-up` dies. Close every Claude Code session before `install.sh` anyway: a process started mid-run has the same effect. Repair by hand: `uv pip install --python <venv python> --reinstall --no-deps --link-mode copy <the packages whose files are gone>`, or the full `uv tool install "mempalace[dml]" --overrides ~/.mempalace/uv-overrides.txt --upgrade --reinstall` with nothing running. `tests/mempalace-health.sh`.
- **Status:** fixed (this entry's branch)

### 2026-10-06 — `v1` moved: papers-helper's ratchet changed with no PR on its side
- **Area:** release tags of the reusable workflows (`baseline-ratchet.yml@v1`, called by papers-helper's required check `ratchet / ratchet`)
- **Symptom:** on 2026-10-03 `v1` was an annotated tag on `6bb0d50`; on 2026-10-06 it was deleted and recreated lightweight on `a7043ef` ("v1 must move to that commit"). Between the two, `scripts/baseline-ratchet.cjs` and `baseline-ratchet.yml` changed (`1ae6067`, `238be44`, `9134113`: script shipped as `.cjs`, array entries read as measures), so the check ran new logic on every papers-helper PR while nothing in papers-helper changed.
- **Cause:** a reusable workflow fetches its scripts at `job.workflow_sha`, so the tag is the only pin, and nothing kept a tag in place: no ruleset on GitHub, and protect-gates let `git push --delete` and `+ref` through.
- **Workaround / fix:** a release is a new annotated tag plus a PR that moves the callers (`context/architecture.md`, "Release tags"). Ruleset `24734324` (2026-10-08, `refs/tags/v*`: update, deletion, non-fast-forward, empty bypass list) refuses the move: `--delete v1` (2026-10-08) and `--delete v0-ruleset-probe` (2026-10-09) rejected with GH013. protect-gates refuses the push locally since PR #31. `v1` stays on `a7043ef`.
- **Status:** fixed (ruleset `24734324`, PR #31)
