# {{REPO_NAME}} — Project Notes

Tooling conventions (Graphify + vault graph fallback, RTK, MemPalace wings, `context/`, Think in Code) live in the global `~/.claude/CLAUDE.md` — do not duplicate them here.

Repo-specific pointers:

- MemPalace: `--wing {{WING}}` for mined code and docs, `--wing {{DIARY_WING}}` for the session diary. Always scope the search, and write the query in English.
- Graph fallback when `graphify-out/` is missing locally (fresh clone, new machine): `{{VAULT_DIR}}/Projets/{{REPO_NAME}}/{{REPO_NAME}} - GRAPH_REPORT.md`

Add below only what is specific to this repo and not derivable from the code: architecture decisions, hard constraints, build/test commands.
