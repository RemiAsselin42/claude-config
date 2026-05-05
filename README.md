# claude-config

Shared Claude Code configuration: specialized agents, slash-commands, scripts, persistent memory (MemPalace), and token optimization (RTK). Clone once, install everywhere, stay in sync.

> [!WARNING]
> **These scripts modify your system environment.**
>
> `install.sh` performs persistent, potentially destructive operations:
> - **Writes** to `~/.claude/` (agents, commands, hooks, scripts, settings, CLAUDE.md)
> - **Installs** global packages (`graphify`, `mempalace`, `rtk`)
> - **Modifies PATH** — adds `~/.local/bin` to `~/.bashrc` / `~/.bash_profile` / `~/.profile` (with confirmation, or silently with `-y`)
> - **Deletes files** (`graphify-out/`, mempalace wings, vault folders) via `exclude-from-index.sh`
> - **Auto-commits** git repos (vault sync)
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

Your private repo stays in sync with this one automatically — see [Upstream sync](#upstream-sync).

---

## Prerequisites

- [Node.js](https://nodejs.org)
- `curl` (for auto-installing [uv](https://astral.sh/uv) if missing)

---

## Quick start

```bash
git clone https://github.com/RemiAsselin42/claude-config
cd claude-config
cp env.local.template env.local
# Edit env.local with your machine-specific values
bash install.sh
```

### Non-interactive (preserve current state per repo)

```bash
bash install.sh -y
```

### Verbose (show detailed installer output)

```bash
bash install.sh -v
```

---

## What `install.sh` does

1. Checks **Node.js**, installs **uv** if missing, then installs/upgrades **Graphify**, **MemPalace**, **chromadb**, and **RTK**
2. Syncs from `upstream` remote if present (private repos get latest shared config automatically)
3. Asks once to add `~/.local/bin` to persistent PATH (`-y` skips)
4. Copies **agents**, **commands**, **scripts** to `~/.claude/`
5. Generates **`session-stop.sh`** with the absolute repo path (Stop hook)
6. Initializes **MemPalace** and rebuilds index from Claude transcripts
7. Copies **CLAUDE.md** to `~/.claude/CLAUDE.md`
8. Restores **caveman mode** from `defaults/` if not set on this machine
9. Generates **`claude.json`** from template (substitutes `FIGMA_API_KEY`)
10. Copies **`settings.json`**
11. Activates **RTK** via `setup-rtk.sh`
12. Interactively selects sibling git repos to index (graphify + mempalace + vault)
13. Auto-commits vault if graphs were generated

---

## Structure

```
claude-config/
├── install.sh                   # Main installation script
├── env.local.template           # Machine-specific variables (FIGMA_API_KEY, etc.)
├── CLAUDE.md                    # Global instructions for Claude Code
├── claude.json.template         # MCP config template (Figma, etc.)
├── settings.json                # Permissions, hooks, effort level, MCP servers
│
├── agents/                      # Specialized agents → ~/.claude/agents/
├── commands/                    # Slash-commands → ~/.claude/commands/
├── defaults/                    # Defaults restored on new machine
│   ├── caveman.enabled          # Presence = caveman on by default
│   └── caveman.level            # Default intensity level
├── hooks/                       # PreToolUse/Stop hooks → ~/.claude/hooks/
├── scripts/                     # Utility scripts → ~/.claude/scripts/
│   ├── repo-identity.sh         # Shared lib: canonical_repo_name()
│   ├── caveman-toggle.sh        # Toggle caveman mode
│   ├── setup-rtk.sh             # Install RTK
│   ├── sync-upstream.sh         # Sync shared files from upstream remote
│   ├── sync-graph-to-vault.sh   # Sync Graphify → Obsidian vault
│   └── exclude-from-index.sh    # Remove a repo from graphify + mempalace
└── templates/
    └── CLAUDE.project.md        # CLAUDE.md template for repos without one
```

---

## Upstream sync

`scripts/sync-upstream.sh` pulls shared files from the `upstream` remote into your private repo, without touching personal files (`vault/`, `env.local`, `.claude/`).

**Automatic** — runs once per 8 hours via `PreToolUse` hook (debounced by timestamp).  
**Forced** — runs unconditionally at the start of every `install.sh`.

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

From then on, `install.sh` and the `PreToolUse` hook keep your private repo in sync with this one.

---

## Agents

| Agent | Role |
|---|---|
| `architect-reviewer` | System design and architecture review |
| `backend-developer` | Backend APIs and services |
| `code-reviewer` | Code quality and security review |
| `documentation-engineer` | Technical documentation |
| `frontend-developer` | Frontend applications (React, Vue, Angular) |
| `javascript-pro` | Advanced JavaScript / Node.js |
| `payment-integration` | Payment systems and PCI compliance |
| `react-performance-optimizer` | React performance and Core Web Vitals |
| `security-auditor` | Security audits and compliance |
| `typescript-pro` | Advanced TypeScript patterns |
| `ui-designer` | UI design systems and components |

---

## Slash-commands

| Command | Description |
|---|---|
| `/appliquer-suggestions` | Apply identified recommendations to code |
| `/caveman [on\|off] [level]` | Toggle caveman mode with optional intensity level |
| `/create-commit` | Create a git commit |
| `/evaluer-codebase` | Evaluate a freshly cloned repository |
| `/evaluer-commentaires` | Analyze code comment quality |
| `/evaluer-documentation` | Check doc/code consistency |
| `/evaluer-modifications` | Analyze changes since last commit |
| `/evaluer-qualite` | Evaluate code quality |
| `/evaluer-stack` | Audit the technology stack |
| `/expliquer-modifications` | Explain recent changes |
| `/mettre-a-jour-agents` | Update AGENTS.md |
| `/mettre-a-jour-documentation` | Update documentation |
| `/mettre-a-jour-prompts` | Adapt prompt examples to the current project |
| `/trouver-code-mort` | Find dead code in the project |

---

## Caveman mode

Minimal response style, persisted across sessions. Controlled via `/caveman` or directly:

```bash
bash ~/.claude/scripts/caveman-toggle.sh [on|off|toggle|inject|status] [level]
```

| Level | Description |
|---|---|
| `lite` | Removes filler and pleasantries, keeps full grammar |
| `full` | Terse responses, fragments accepted (default) |
| `ultra` | Maximum compression, abbreviations, arrows for causality |
| `wenyan-lite` | Semi-classical register, literary tone |
| `wenyan-full` | 文言文 mode, maximum classical terseness |
| `wenyan-ultra` | Extreme compression, classical letter style |

State and level are stored in `~/.claude/caveman.enabled` and `~/.claude/caveman.level`. On a new machine, `install.sh` restores from `defaults/`.

---

## Hooks

Configured in `settings.json`:

| Hook | Trigger | Action |
|---|---|---|
| `PreToolUse` | Every tool call | `sync-upstream.sh` — syncs from upstream (debounced 8h) |
| `Stop` | End of session | MemPalace save + `session-stop.sh` (graphify update + vault sync) |
| `PreCompact` | Before compaction | MemPalace save |

---

## RTK — Token proxy

RTK rewrites common dev commands (e.g. `git status` → `rtk git status`) to reduce token consumption by 60–90%. The `PreToolUse` hook applies this transparently.

Install manually:

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

**Windows** — installed via `winget`, with a bash wrapper at `~/.local/bin/rtk`.  
**Linux/macOS** — installed via `brew` or the official install script, then `rtk init -g`.

---

## Graphify

Generates a knowledge graph of each indexed codebase.

```bash
graphify update .            # Update graph (AST only, no API cost)
graphify query "question"    # Semantic query
graphify path "A" "B"        # Path between two concepts
graphify explain "concept"   # Explain a concept from the codebase
```

Each indexed repo gets:
- `graphify-out/GRAPH_REPORT.md` — local report (gitignored)
- `vault/Projets/<repo>/` — versioned copy in the Obsidian vault (private repos only)

---

## MemPalace

Persistent cross-session memory. Data lives in `~/.mempalace/` (never versioned).

```bash
mempalace search "topic" --wing repo-name   # Scoped to a repo
mempalace search "topic"                    # Global search

# Rebuild index on a new machine
mempalace init ~/.mempalace
mempalace mine ~/.claude/projects/ --mode convos
```

Via MCP (in Claude Code): `mempalace_search` and `mempalace_add_drawer`.

---

## See also

- [README.fr.md](README.fr.md) — French version
