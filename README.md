# claude-config

Shared Claude Code configuration: specialized agents, slash-commands, scripts, persistent memory (MemPalace), and token optimization (RTK). Clone once, install everywhere, stay in sync.

> [!WARNING]
> **These scripts modify your system environment.**
>
> `install.sh` performs persistent, potentially destructive operations:
>
> - **Writes** to `~/.claude/` (agents, commands, hooks, scripts, settings, CLAUDE.md)
> - **Installs** global packages (`graphify`, `mempalace`, `rtk`)
> - **Modifies PATH** — adds `~/.local/bin` to `~/.bashrc` / `~/.bash_profile` / `~/.profile` (with confirmation, or silently with `-y`)
> - **Deletes files** (`graphify-out/`, mempalace wings, vault folders) via `exclude-from-index.sh`
> - **Writes git hooks and config** in target repos (post-commit vault sync, `pre-commit` shellcheck gate in this repo, `merge.ours.driver` / `pull.rebase false`)
> - **Auto-commits and pushes** git repos (vault sync)
>
> Read `install.sh` before running. Do not use on a machine whose `~/.claude/` is managed by another workflow.

---

## Public / Private model

This repo is the **shared base**. It contains everything that is useful to anyone: agents, commands, scripts, settings templates. It does **not** contain personal data (no vault, no env secrets).

For a personal setup with a versioned Obsidian vault and private overrides, fork or extend this repo privately:

```
claude-config (this repo, public)
    └── upstream ── your-claude-config (private fork)
                        ├── vault/          # personal Obsidian vault
                        └── env.local       # machine-specific secrets
```

Your private repo stays in sync with this one automatically — see [Minimal setup](#minimal-setup).

---

## Prerequisites

- [Node.js](https://nodejs.org)
- `curl` (for auto-installing [uv](https://astral.sh/uv) if missing)

---

## What `install.sh` does

1. Syncs from `upstream` remote **first** if present (private repos get latest shared config automatically); if the sync brings changes, the script re-executes itself so the rest of the run uses the updated version
2. Checks **Node.js**, installs **uv** if missing, then installs/upgrades **Graphify**, **MemPalace**, **chromadb**, **RTK**, **jq**, **shellcheck** and **context-mode** (plus the Zilliz MCP server when `MILVUS_ADDRESS` is set)
3. Asks once to add `~/.local/bin` to persistent PATH (`-y` skips)
4. Copies **agents**, **commands**, **scripts**, **templates** to `~/.claude/` — `agents/` and `commands/` are mirrored: deployed files removed from the repo are pruned
5. Records the repo location in `~/.claude/claude-config.path` and generates **`session-stop.sh`** (Stop hook: `graphify update` + mining the repo into its MemPalace wing + vault sync); hooks resolve the repo through this pointer instead of hardcoded absolute paths
6. Initializes **MemPalace**: creates the palace, selects the embedding model, checks index health. Repos are _not_ mined here — each one is mined into its own wing during step 15
7. Copies **CLAUDE.md** to `~/.claude/CLAUDE.md` (substitutes `${VAULT_DIR}`)
8. Generates **`claude.json`** from template (substitutes `FIGMA_API_KEY`)
9. Copies **`settings.json`**
10. Activates **RTK** via `setup-rtk.sh`
11. Runs **CC Safe Setup** to install safety hooks non-destructively
12. Installs **pinned plugins** via the `claude` CLI (`ponytail`, upstream `caveman`)
13. Restores **caveman mode** from `defaults/` if not set on this machine (skipped when the upstream caveman plugin is installed — it injects its own instructions)
14. Updates `.gitignore` in target repos (graphify block + `CLAUDE.md` + `mempalace.yaml` + `context/`) using `templates/gitignore.append`
15. Interactively selects sibling git repos to index. Per repo: graphify hooks + graph, LLM **community naming**, vault sync (report + file tree + canvas + one note per node), `mempalace.yaml` generation and mining into the repo's own wing
16. Runs the same pipeline on the config repo itself (forced graph refresh, no `.gitignore` management)
17. Installs a **shellcheck pre-commit gate** in the config repo — staged `*.sh` must pass `shellcheck -S warning`
18. Commits the vault and reconciles with `origin` (fetch → merge → push, retried on races) via `scripts/vault-sync.sh`

---

## Minimal setup

`install.sh` on a fresh clone already gives you the shared config. Two more things turn it into a personal setup: a **private repo** to hold your vault and overrides, and **Obsidian** to read what Graphify writes.

### Setting up a private repo

```bash
# Clone the public repo as your private base
git clone https://github.com/RemiAsselin42/claude-config my-claude-config
cd my-claude-config

# Point origin to your private repo, keep public as upstream
git remote rename origin upstream
git remote add origin https://github.com/<you>/my-claude-config
git push -u origin main
```

From then on, `scripts/sync-upstream.sh` pulls shared files from `upstream` into your private repo without touching personal files (`vault/`, `env.local`, `.claude/`):

**Automatic** — once per 8 hours via the `PreToolUse` hook (debounced by timestamp).  
**Forced** — unconditionally at the start of every `install.sh`.

### Obsidian vault

The public repo ships no `vault/` — `install.sh` creates it in your private repo and writes, per indexed repo, `Projets/<repo>/` with the graph report, the file tree, a `<repo>.canvas` community map and one note per graph node. To read it: Obsidian → _Open folder as vault_ → select `<your-repo>/vault`.

`scripts/vault-sync.sh` commits it and reconciles with `origin` (fetch → merge → push) at the end of every install and every session, so several machines can write to the same vault.

### Options

Nothing below is required — defaults work.

| Where       | Option                                               | Effect                                                                                  |
| ----------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| CLI         | `install.sh -y`                                      | Non-interactive: keeps each repo's current indexing state, auto-accepts the PATH change |
| CLI         | `install.sh -v`                                      | Verbose installer output                                                                |
| Prompt      | PATH                                                 | Asked once, to add `~/.local/bin` to `~/.bashrc` / `~/.bash_profile` / `~/.profile`     |
| Prompt      | Repo selection                                       | Which sibling git repos to index (graphify + MemPalace + vault)                         |
| `env.local` | `FIGMA_API_KEY`                                      | Enables the Figma MCP server                                                            |
| `env.local` | `MEMPALACE_EMBEDDING_MODEL`                          | `embeddinggemma` (default, multilingual) or `minilm` (English-only, faster)             |
| `env.local` | `MEMPALACE_PALACE_PATH`                              | Move the palace off `~/.mempalace/palace` (small system drive, synced folder)           |
| `env.local` | `GRAPHIFY_LABEL_BACKEND` / `_MODEL`                  | Which LLM names the graph communities (default: the `claude` CLI, no API key)           |
| `env.local` | `GRAPHIFY_DEEP_EXTRACT`                              | LLM re-extraction adding `INFERRED` edges — slow, billed on paid backends               |
| `env.local` | `MILVUS_ADDRESS` / `MILVUS_TOKEN` / `OPENAI_API_KEY` | Enables the Zilliz semantic-search MCP server                                           |

Each key is documented inline in `env.local.template`.

---

## Structure

```
claude-config/
├── install.sh                   # Main installation script
├── env.local.template           # Machine-specific variables (Figma key, embedder, label backend…)
├── CLAUDE.md                    # Global instructions for Claude Code
├── claude.json.template         # MCP config template (Figma, etc.)
├── settings.json                # Permissions, hooks, effort level, MCP servers
├── mempalace.yaml               # This repo's own MemPalace wing + mining exclusions
├── .graphifyignore              # Keeps vault/ (generated) out of this repo's own graph
│
├── agents/                      # Specialized agents → ~/.claude/agents/
├── commands/                    # Slash-commands → ~/.claude/commands/
├── defaults/                    # Defaults restored on new machine
│   ├── caveman.enabled          # Presence = caveman on by default
│   └── caveman.level            # Default intensity level
├── scripts/                     # Utility scripts → ~/.claude/scripts/
│   ├── repo-identity.sh         # Shared lib: canonical_repo_name()
│   ├── caveman-toggle.sh        # Toggle caveman mode
│   ├── setup-rtk.sh             # Install RTK
│   ├── sync-upstream.sh         # Sync shared files from upstream remote
│   ├── sync-graph-to-vault.sh   # Sync Graphify → Obsidian vault
│   ├── vault-sync.sh            # Commit + fetch/merge/push the vault (multi-machine safe)
│   └── exclude-from-index.sh    # Remove a repo from graphify + mempalace
└── templates/
    ├── CLAUDE.project.md        # CLAUDE.md starter template for new repos
    ├── gitignore.append         # .gitignore entries appended by install.sh
    └── context/                 # Per-repo context templates (copied by /init-context)
        ├── architecture.md
        ├── patterns.md
        └── constraints.md
```

---

<details>
<summary><strong>Agents</strong></summary>

| Agent                         | Role                                        |
| ----------------------------- | ------------------------------------------- |
| `architect-reviewer`          | System design and architecture review       |
| `backend-developer`           | Backend APIs and services                   |
| `code-reviewer`               | Code quality and security review            |
| `documentation-engineer`      | Technical documentation                     |
| `frontend-developer`          | Frontend applications (React, Vue, Angular) |
| `javascript-pro`              | Advanced JavaScript / Node.js               |
| `payment-integration`         | Payment systems and PCI compliance          |
| `react-performance-optimizer` | React performance and Core Web Vitals       |
| `security-auditor`            | Security audits and compliance              |
| `typescript-pro`              | Advanced TypeScript patterns                |
| `ui-designer`                 | UI design systems and components            |

</details>

---

<details>
<summary><strong>Slash-commands</strong></summary>

| Command                 | Description                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------- |
| `/apply-suggestions`    | Apply identified recommendations to code                                              |
| `/copilot-check`        | Judge Copilot review feedback on a PR before applying it                              |
| `/create-commit`        | Create a git commit                                                                   |
| `/create-pr`            | Split work into logical commits and open a PR                                         |
| `/explain-changes`      | Explain recent changes                                                                |
| `/find-dead-code`       | Find dead code in the project                                                         |
| `/init-context`         | Generate `context/architecture.md`, `patterns.md`, `constraints.md` from the codebase |
| `/review-changes`       | Analyze changes since last commit                                                     |
| `/review-codebase`      | Evaluate a freshly cloned repository                                                  |
| `/review-comments`      | Analyze code comment quality                                                          |
| `/review-documentation` | Check doc/code consistency                                                            |
| `/review-quality`       | Evaluate code quality                                                                 |
| `/review-stack`         | Audit the technology stack                                                            |
| `/update-agents`        | Update AGENTS.md                                                                      |
| `/update-documentation` | Update documentation                                                                  |
| `/update-prompts`       | Adapt prompt examples to the current project                                          |

</details>

---

<details>
<summary><strong>Caveman mode</strong></summary>

Minimal response style, persisted across sessions. Controlled via `/caveman` or directly:

```bash
bash ~/.claude/scripts/caveman-toggle.sh [on|off|toggle|inject|status] [level]
```

| Level          | Description                                              |
| -------------- | -------------------------------------------------------- |
| `lite`         | Removes filler and pleasantries, keeps full grammar      |
| `full`         | Terse responses, fragments accepted (default)            |
| `ultra`        | Maximum compression, abbreviations, arrows for causality |
| `wenyan-lite`  | Semi-classical register, literary tone                   |
| `wenyan-full`  | 文言文 mode, maximum classical terseness                 |
| `wenyan-ultra` | Extreme compression, classical letter style              |

State and level are stored in `~/.claude/caveman.enabled` and `~/.claude/caveman.level`. On a new machine, `install.sh` restores from `defaults/`.

When the upstream [caveman plugin](https://github.com/JuliusBrussee/caveman) is installed (pinned via `install.sh`), it injects its own compression instructions and adds `/caveman-compress`, `/caveman-stats`, `/caveman-commit`, `/caveman-review`. The local block is then stripped to avoid duplication — `caveman-toggle.sh` remains as fallback when the plugin is absent.

</details>

---

<details>
<summary><strong>Pinned plugins</strong></summary>

`install.sh` installs the same Claude Code plugins on every machine via the `claude` CLI (list: `PINNED_PLUGINS` array in `install.sh`):

| Plugin     | Source                                                                | Purpose                                                                                        |
| ---------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | YAGNI decision ladder — less generated code (reuse → stdlib → existing dependency → minimum)   |
| `caveman`  | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | Upstream compression plugin — replaces the local CLAUDE.md block, adds stats/compress commands |

If the `claude` CLI is not in PATH, the step is skipped with a warning; install manually with `claude plugin marketplace add <repo> && claude plugin install <name>@<marketplace>`.

</details>

---

<details>
<summary><strong>Hooks</strong></summary>

Configured in `settings.json`:

| Hook          | Trigger           | Action                                                                                            |
| ------------- | ----------------- | ------------------------------------------------------------------------------------------------- |
| `PreToolUse`  | Every tool call   | `sync-upstream.sh` — syncs from upstream (debounced 8h, private repos only) + `context-mode` hook |
| `PostToolUse` | Every tool call   | `context-mode` hook                                                                               |
| `Stop`        | End of session    | MemPalace save + `context-mode` hook + `session-stop.sh` (graphify update + vault sync)           |
| `PreCompact`  | Before compaction | MemPalace save + `context-mode` hook                                                              |

On Windows, `context-mode` cannot walk the process tree, so concurrent Claude Code sessions can share one session state. Set `CLAUDE_SESSION_ID` to a distinct value per session if you run several at once.

</details>

---

<details>
<summary><strong>RTK — Token proxy</strong></summary>

RTK rewrites common dev commands (e.g. `git status` → `rtk git status`) to reduce token consumption by 60–90%.

**Windows** — installed via `winget`, activated via `rtk init -g --claude-md`: RTK works through CLAUDE.md instructions (Claude prefixes commands itself, no bash hook needed).  
**Linux/macOS** — installed via `brew` or the official install script, activated via `rtk init -g`: RTK installs a `PreToolUse` hook into `settings.json` that rewrites commands transparently.

Install manually:

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

</details>

---

<details>
<summary><strong>Graphify</strong></summary>

Generates a knowledge graph of each indexed codebase.

```bash
graphify update .            # Update graph (AST only, no API cost)
graphify query "question"    # Semantic query
graphify path "A" "B"        # Path between two concepts
graphify explain "concept"   # Explain a concept from the codebase
```

Each indexed repo gets:

- `graphify-out/GRAPH_REPORT.md` — local report (gitignored)
- `vault/Projets/<repo>/` — versioned copy in the Obsidian vault (private repos only): `<repo> - GRAPH_REPORT.md`, `<repo> - FILE_TREE.md`, `<repo>.canvas` (community map) and `obsidian/` with one note per graph node

### Community naming

`graphify update` is AST-only, so communities stay named `Community 12` in the report, the canvas groups and every note. `install.sh` runs one LLM labeling pass per repo, only when names are missing or still placeholders. Default backend is the `claude` CLI already on PATH (no API key). Override in `env.local`:

```bash
GRAPHIFY_LABEL_BACKEND="ollama"   # claude-cli | gemini | openai | deepseek | kimi | ollama | none
GRAPHIFY_LABEL_MODEL="llama3"     # optional, backend default otherwise
GRAPHIFY_DEEP_EXTRACT="false"     # opt-in: LLM re-extraction adding INFERRED edges (slow, billed)
```

A repo is skipped when it contains a `.graphifyignore` — this repo has one for `vault/`, which is graphify's own output and would otherwise be indexed back into the graph.

</details>

---

<details>
<summary><strong>MemPalace</strong></summary>

Persistent cross-session memory. Data lives in `~/.mempalace/` (never versioned).

Each indexed repo gets its own **wing**. `install.sh` generates a `mempalace.yaml` (gitignored in target repos) holding the wing name and mining exclusions, then mines both the repo files and its Claude transcripts into that wing.

```bash
mempalace status                             # List the real wing names
mempalace search "topic" --wing wing_my_repo # Scoped to a repo
mempalace search "topic"                     # Global search
```

`mine` stores the wing as `wing_` + the name with `-` replaced by `_`, and `search --wing` matches that stored name exactly — passing the raw `mempalace.yaml` value returns 0 results.

Embedding model and palace location are set in `env.local` (`MEMPALACE_EMBEDDING_MODEL`, `MEMPALACE_PALACE_PATH`). Default is `embeddinggemma` (multilingual, ~300 MB); `minilm` is faster but English-only. Switching on an existing palace invalidates every vector — `install.sh` detects the mismatch and asks before re-indexing.

To rebuild on a new machine, just re-run `install.sh`.

Via MCP (in Claude Code): `mempalace_search` and `mempalace_add_drawer`.

</details>

---

<details>
<summary><strong>Zilliz — Semantic search (optional)</strong></summary>

When `MILVUS_ADDRESS` is set in `env.local`, Claude uses semantic vector search **before** grep for "find where X is handled" queries on large repos. Graphify provides structural navigation; Zilliz provides semantic relevance.

Configure in `env.local` (see `env.local.template`):

```bash
export MILVUS_ADDRESS="https://xxx.api.gcp-us-west1.zillizcloud.com"
export MILVUS_TOKEN="your-zilliz-api-key"
export OPENAI_API_KEY="sk-..."   # used for embeddings
```

`install.sh` installs the `@zilliz/claude-context-mcp` MCP server automatically when `MILVUS_ADDRESS` is set. If not set, this step is silently skipped.

</details>

---

<details>
<summary><strong>Per-repo context</strong></summary>

Run `/init-context` inside any repo to generate structured context files from the actual codebase:

- `context/architecture.md` — major decisions and their rationale
- `context/patterns.md` — recurring code patterns
- `context/constraints.md` — performance, security, and compatibility constraints

Templates are in `templates/context/`. Claude reads these files automatically at session start if the `context/` directory exists (via the Per-Repo Context rule in `CLAUDE.md`).

</details>

---

## See also

- [README.fr.md](README.fr.md) — French version
