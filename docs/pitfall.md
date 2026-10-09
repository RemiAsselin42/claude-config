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

### 2026-10-09 — The Bash tool halves double backslashes, quoted heredocs included
- **Area:** Claude Code 2.1.295, Bash tool on Windows (Git Bash) with this repo's PreToolUse hooks; a quoted heredoc (`<<'EOF'`) feeding `python -`
- **Symptom:** a Python script passed inline with `s/…/\\1/p` wrote the byte 0x01 into `tests/vibe-toggle.sh` (Python's octal escape for the halved `\1`) and `tr -d '\\r'` became `tr -d` with a raw CR byte; the first sign was `SyntaxWarning: invalid escape sequence '\('`. The test looked right on screen (`sed -n 321p` prints nothing for the control byte) and failed its own case 28. Probes: `printf '%s\n' 'a\\b'` prints `a\b`, the same inside a quoted heredoc; `\$x`, `\"q` and `a\nb` come out unchanged, so it is not a double-quoted wrapper, only `\\` is touched.
- **Cause:** every `\\` in the command text reaches bash as `\`, quoted heredoc body included. Not the guards: fed the same payload on stdin, `rtk hook claude` (0.43.0) returns the rewritten command with its `\\` intact, and protect-gates, destructive-guard, branch-guard and secret-guard return nothing. `context-mode hook claude-code pretooluse` could not be run on its own (it waits on stdin or the daemon), so the tool itself or that hook remains.
- **Workaround / fix:** write any script that carries backslashes to a file with the Write tool and run the file (`python -I file.py`); keep heredocs for backslash-free text; before committing, scan the staged files for control bytes (the session's throwaway `fix-test-bytes.py` did; nothing in the repo yet).
- **Status:** open (workaround only, the layer at fault not identified)

### 2026-10-09 — ponytail's SubagentStart matcher names the harness agents by their bare name
- **Area:** `mods/ponytail/hooks/claude-codex-hooks.json`, `"matcher": "^(?!(diff-reviewer|plan-reviewer|spec-tester)$)"`, the one edit to the vendored copy; `agents/`, deployed to `~/.claude/agents/`
- **Symptom:** none yet. Claude Code tests the matcher against `agent_type`, which for a custom subagent in `~/.claude/agents/` is the frontmatter `name`; for a subagent shipped by a plugin it is the plugin-scoped id, `<plugin>:<name>` (hooks reference, SubagentStart). Moved into a plugin of the `claude-config` marketplace, the three agents would report `claude-config:diff-reviewer` and so on, the negative lookahead would stop matching them, and ponytail's ruleset would reach the reviewers again, silently: a fresh session with the matcher removed showed exactly that (diff-reviewer quoting `PONYTAIL MODE ACTIVE — level: full`, PR #34).
- **Cause:** the exclusion is by name, and the name depends on where the agent file lives.
- **Workaround / fix:** `tests/ponytail-subagent.test.js` reads `agents/*.md` and compares bare names only. The day the agents move into a plugin, extend the matcher with the scoped alternatives (`claude-config:diff-reviewer|…`) and make the test derive the expected ids from where the agents live. A renamed or added harness agent is already caught by the test.
- **Status:** open (nothing to do until the agents leave `agents/`)

### 2026-10-09 — The sync's deletion pass missed upstream renames
- **Area:** `scripts/sync-upstream.sh`, the pass that removes from a fork what upstream dropped; `scripts/baseline-ratchet.js`, renamed to `.cjs` upstream on 2026-10-05 (`1ae6067`)
- **Symptom:** the private fork still tracked `scripts/baseline-ratchet.js` four days and several syncs after the rename; `harness-drift.sh` named it as the clone's only distance to `upstream/main` (PR #35).
- **Cause:** the pass ran `git diff --name-only --diff-filter=D <last synced commit> upstream/main`. `git diff` detects renames by default (`diff.renames`, since git 2.9), so a renamed file is `R`, never `D`. The baseline moved forward at every sync, so once recorded past the rename nothing could list it again; on this fork `merge-base HEAD upstream/main` is empty as well (unrelated histories), so the first-run fallback had nothing either.
- **Workaround / fix:** no baseline. The pass removes every file the fork tracks on a synced path that `upstream/main` lacks and that upstream's history knows (`git rev-list -n 1 upstream/main -- <path>`); a path upstream never had stays. `tests/sync-upstream.sh` case 9: a rename, a rename an earlier pass missed, the fork's own file. `.git/upstream-sync-ref` is no longer written or read; the one in existing clones is a dead leftover.
- **Status:** fixed (`feat/sync-upstream-renames`, 2026-10-09)
