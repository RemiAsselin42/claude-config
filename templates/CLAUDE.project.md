## Graphify (Knowledge Graph)

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/GRAPH_REPORT.md doesn't exist locally, fall back to the centralized vault: `~/.claude/vault/Projets/{{REPO_NAME}}/{{REPO_NAME}} - GRAPH_REPORT.md`
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)

## Persistent Memory (MemPalace)

MemPalace stores context that persists across sessions. Content is populated automatically — search and apply it before starting work.

Typical content: past architectural decisions and their rationale, constraints the user mentioned, recurring preferences, known gotchas, things that were tried and didn't work.

**Search before starting non-trivial work** — there may be relevant context from past sessions:
```bash
mempalace search "topic" --wing {{REPO_NAME}}   # scoped to this repo
mempalace search "topic"                        # global search
```
Or via MCP: `mempalace_search`

## Obsidian Vault

The vault is a versioned knowledge base (inside the claude-config repo) that persists across machines. It is the fallback when graphify-out/ does not exist locally — useful on a fresh clone or a new machine.

Use cases:
- Read `vault/Projets/{{REPO_NAME}}/{{REPO_NAME}} - GRAPH_REPORT.md` when the local graph is missing
- Read `vault/Décisions/` for past architectural decisions
- Read `vault/Patterns/` for established patterns in this codebase

The vault is committed automatically after each `./install.sh` run and after each `graphify update`.
