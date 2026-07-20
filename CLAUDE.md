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

**Save (MCP tool — always use this):**

- `mempalace_add_drawer` with `wing=<repo wing>` for project memories — the wing is the `wing:` value in the repo's `mempalace.yaml` (fallback: `basename $PWD`)
- `mempalace_add_drawer` with `wing=global` for universal preferences (behavioral feedback)

**Search — two rules, always:**

1. **Always pass `--wing`.** An unscoped search returns other projects' memories and buries the relevant ones. The wing is the `wing:` value in the repo's `mempalace.yaml`. Only drop it when deliberately looking across projects.
2. **Write the query in English**, even when the conversation is in another language. Identifiers, error strings and commit prefixes in the indexed content are English, and English keeps results stable whichever embedding model this machine ended up with.

```bash
wing=$(sed -n 's/^wing:[[:space:]]*//p' mempalace.yaml)   # fallback: basename $PWD
mempalace search "install script dependencies" --wing "$wing"
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

- `Projets/` — One folder per repo, with the Graphify graph
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
ctx_execute(
  "javascript",
  `
  const files = fs.readdirSync('src').filter(f => f.endsWith('.ts'));
  files.forEach(f => console.log(f + ': ' + fs.readFileSync('src/'+f,'utf8').split('\\n').length + ' lines'));
`,
);
// Output: 3.6 KB
```

Rule: if the answer requires reading N > 3 files to aggregate data, generate a script instead. Use `ctx_execute` (context-mode MCP tool) or Bash.
