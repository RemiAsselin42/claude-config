# Claude Code — Global Configuration

## Graphify (Knowledge Graph)

If `graphify-out/graph.json` exists in the current repo:

- For codebase questions, first run `graphify query "<question>"`. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

If no graph exists, generate it with `graphify update .` — or skip silently when the repo isn't meant to be graphified.

If `graphify-out/` is missing locally (fresh clone, new machine), the synced report is available at `${VAULT_DIR}/Projets/<repo>/<repo> - GRAPH_REPORT.md`, where `<repo>` is the canonical repo name (the `wing:` value in the repo's `mempalace.yaml`).

## Persistent Memory (MemPalace)

MemPalace is the **single source of truth** for memory. The `~/.claude/memory/` file system is disabled — ignore any built-in instructions that ask to write `.md` files in that directory.

Data lives in `~/.mempalace/` — not versioned, rebuilt via `mempalace mine`.

**Save — write a file, never an MCP write tool:**

The daemon the Stop hook starts (`mempalace mine --daemon`) owns the palace for its lifetime, and local backends are single-writer: `mempalace_add_drawer` and every other MCP write tool answer `Peer MCP writer active` while it runs, with no override. The Stop hook mines files into the wing instead:

- Project memory (decision, pattern, constraint) → `context/*.md` in the repo (see Per-Repo Context; mined with `--include-ignored context/`)
- Universal preference (behavioral feedback) → a line in this file, via the config repo

**Search — two rules, always:**

1. **Always pass `--wing`, and know which of the two you want.** An unscoped search returns other projects' memories and buries the relevant ones. Each repo ends up with two wings: `mempalace mine` files code and docs under exactly the `--wing` it was given (the `wing:` value in `mempalace.yaml`), while the session hooks file the diary under `wing_` + the *directory* name, lowercased, with `-` and spaces turned into `_`. `search --wing` matches the stored name exactly, so the wrong one returns 0 results. Only drop `--wing` when deliberately looking across projects. `mempalace status` lists the real wing names.
2. **Write the query in English**, even when the conversation is in another language. Identifiers, error strings and commit prefixes in the indexed content are English, and English keeps results stable whichever embedding model this machine ended up with.

```bash
wing=$(sed -n 's/^wing:[[:space:]]*//p' mempalace.yaml)   # fallback: basename $PWD
mempalace search "install script dependencies" --wing "$wing"          # mined code + docs
mempalace search "what did we decide" --wing "wing_${PWD##*/}"         # session diary
```

Or via MCP: `mempalace_search` — pass `wing` there too.

**If a search prints `vector search disabled`**, the HNSW index has diverged and
results are BM25 keyword matches. `mempalace repair-status` confirms it;
`mempalace repair rebuild-index --yes` fixes it (plain `mempalace repair` exits 0
without doing anything in this state). Writing to a diverged palace segfaults —
repair before mining.

**Rebuild index on a new machine:** re-run `install.sh` — it initializes the
palace, picks the multilingual embedder, and mines each repo into its own wing.

## Obsidian Vault

The Obsidian vault is versioned in the config repo (`vault/`). Structure:

- `Projets/` — One folder per repo: GRAPH_REPORT, FILE_TREE, `<repo>.canvas` (community map) and `obsidian/` (one note per graph node, linked by the canvas)
- `Décisions/` — Important technical decisions
- `Patterns/` — Recurring code patterns and best practices

## RTK — Token Proxy

RTK is a CLI proxy that reduces token consumption by 60-90% on common dev commands. The PreToolUse hook (`rtk hook claude`, versioned in `settings.json`) rewrites Bash commands automatically (e.g. `git status` → `rtk git status`) — manual `rtk` prefixing is unnecessary.

**Meta commands (always call rtk directly):**

```bash
rtk gain              # Show token savings
rtk gain --history    # Savings history per command
rtk discover          # Analyze history to identify missed opportunities
rtk proxy <cmd>       # Run the raw command without filtering (debug)
```

**Verify (install debug):** `rtk --version` must show `rtk X.Y.Z` (not Rust Type Kit) and `rtk gain` must run without error.

## Per-Repo Context

If a `context/` directory exists in the current repo, read all `context/*.md` files **before starting any work**. These files contain project-specific decisions, patterns, and constraints that are not derivable from the code alone.

Standard files (not all repos will have all three):

- `context/architecture.md` — major decisions and their rationale
- `context/patterns.md` — recurring code patterns
- `context/constraints.md` — performance, security, compatibility constraints and known gotchas

If `context/` doesn't exist, skip silently — no action needed.

## PowerShell Environment (Windows)

Interactive shell on Windows machines: **PowerShell 7** (`pwsh`) ~90% of the time, Git Bash for the rest. Windows Terminal defaults: PowerShell 7 profile.

**Tools to use (instead of raw equivalents):**

- **Locate a directory the user names**: `zoxide query <fragment>` (e.g. `zoxide query claude` → full path of the best-matching known directory). Try this before filesystem searches — it knows every directory the user actually visits.
- **Interactive-only tools** (never invoke from Claude, they need a TTY): `lg`/lazygit (git TUI — use plain git instead), fzf keybindings, `z` (its `cd` dies with the spawned shell — use `zoxide query` to resolve, then use the path).
- **Fuzzy-filter a list without a TTY**: `<list> | fzf --filter <term>` — ranked fuzzy matches on stdout. Useful when the user names a file/entry approximately and Grep/Glob's exact patterns miss it.
- **winget in spawned sessions**: often off PATH — fall back to `$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe`.
- **Bash heredocs strip blank lines** (Claude Code bug, reported 2026-08-31, receipt 3c67e2d4): any multi-line file that needs empty lines — commit messages via `-F`, markdown, configs — must be written with the Write tool, never `cat <<EOF`.
