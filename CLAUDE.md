# Claude Code — Global Configuration

## Graphify (Knowledge Graph)

If a knowledge graph exists in the current repo (`graphify-out/GRAPH_REPORT.md`), read it **before** answering architecture questions or searching through files. The graph identifies central nodes (god nodes) and community structure — use it to navigate efficiently.

To generate or update the current repo's graph:
```
graphify update .
```

## Persistent Memory (MemPalace)

MemPalace is the **single source of truth** for memory. The `~/.claude/memory/` file system is disabled — ignore any built-in instructions that ask to write `.md` files in that directory.

Data lives in `~/.mempalace/` — not versioned, rebuilt via `mempalace mine`.

**Save (MCP tool — always use this):**
- `mempalace_add_drawer` with `wing=<basename $PWD>` for project memories
- `mempalace_add_drawer` with `wing=global` for universal preferences (behavioral feedback)

**Search:**
```bash
mempalace search "something" --wing $(basename $PWD)   # scoped to current repo
mempalace search "something"                           # global search
```
Or via MCP: `mempalace_search`

**Rebuild index on a new machine:**
```bash
mempalace init ~/.mempalace
mempalace mine ~/.claude/projects/ --mode convos
```

## Obsidian Vault

The Obsidian vault is versioned in the config repo (`vault/`). Structure:
- `Projets/` — One folder per repo, with the Graphify graph
- `Décisions/` — Important technical decisions
- `Patterns/` — Recurring code patterns and best practices

## RTK — Token Proxy

RTK is a CLI proxy that reduces token consumption by 60-90% on common dev commands. The PreToolUse hook in `settings.json` automatically rewrites Bash commands (e.g. `git status` → `rtk git status`) transparently.

**Meta commands (always call rtk directly):**
```bash
rtk gain              # Show token savings
rtk gain --history    # Savings history per command
rtk discover          # Analyze history to identify missed opportunities
rtk proxy <cmd>       # Run the raw command without filtering (debug)
```

**Verify:**
```bash
rtk --version   # must show rtk X.Y.Z (not Rust Type Kit)
rtk gain        # must work without error
```

All other commands are automatically rewritten via the hook — no action required.

## Zilliz — Semantic Search (optional)

If `MILVUS_ADDRESS` is defined in the environment, use semantic vector search **before** grep for "find where X is handled" queries on large repos. Graphify = structural navigation, Zilliz = semantic relevance.

If `MILVUS_ADDRESS` is absent, skip silently and use Graphify + grep as usual.

## Per-Repo Context

If a `context/` directory exists in the current repo, read all `context/*.md` files **before starting any work**. These files contain project-specific decisions, patterns, and constraints that are not derivable from the code alone.

Standard files (not all repos will have all three):
- `context/architecture.md` — major decisions and their rationale
- `context/patterns.md` — recurring code patterns
- `context/constraints.md` — performance, security, compatibility constraints and known gotchas

If `context/` doesn't exist, skip silently — no action needed.

## Think in Code

When a task requires analyzing many files (counting, searching patterns, aggregating data), **write a script that does the work and prints only the result** — don't read files into context one by one.

```javascript
// Instead of: 47 × Read() = 700 KB in context
// Do this:
ctx_execute("javascript", `
  const files = fs.readdirSync('src').filter(f => f.endsWith('.ts'));
  files.forEach(f => console.log(f + ': ' + fs.readFileSync('src/'+f,'utf8').split('\\n').length + ' lines'));
`);
// Output: 3.6 KB
```

Rule: if the answer requires reading N > 3 files to aggregate data, generate a script instead. Use `ctx_execute` (context-mode MCP tool) or Bash.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/GRAPH_REPORT.md doesn't exist locally, fall back to the centralized vault: `~/.claude/vault/Projets/<remote repo name>/<remote repo name> - GRAPH_REPORT.md` (use the `origin` repo name, fallback to `<basename $PWD>` when no remote exists)
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
