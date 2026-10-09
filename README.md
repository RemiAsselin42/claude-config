# claude-config

Shared Claude Code configuration: slash-commands, scripts and hooks, persistent memory (MemPalace), and token optimization (RTK). Clone once, install everywhere, stay in sync.

> [!WARNING]
> **These scripts modify your system environment.**
>
> `install.sh` performs persistent, potentially destructive operations:
>
> - **Writes** to `~/.claude/` (commands, scripts, templates, mods, settings, CLAUDE.md)
> - **Prunes** `~/.claude/commands/` and `~/.claude/agents/`: anything there without a source file in the repo is deleted on every run — `~/.claude/agents/` ends up holding exactly the three subagents of `agents/`
> - **Installs** global packages (`graphify`, `mempalace`, `rtk`)
> - **Modifies PATH** — adds `~/.local/bin` to `~/.bashrc` / `~/.bash_profile` / `~/.profile` (with confirmation, or silently with `-y`)
> - **Deletes files** (`graphify-out/`, mempalace wings, vault folders) via `exclude-from-index.sh`
> - **Writes git hooks and config** in target repos (post-commit vault sync, `pre-commit` shellcheck gate in this repo, `merge.ours.driver` / `pull.rebase false`)
> - **Auto-commits and pushes** git repos (vault sync)
>
> Read `install.sh` before running. Do not use on a machine whose `~/.claude/` is managed by another workflow.

---

## Public / Private model

This repo is the **shared base**. It contains everything that is useful to anyone: commands, scripts, settings templates. It does **not** contain personal data (no vault, no env secrets).

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
- bash 4.4+ (Git Bash on Windows and any Linux qualify; on macOS `brew install bash` — the stock 3.2 cannot run the script)

---

## What `install.sh` does

1. Syncs from the `upstream` remote **first**: a fork that lacks the remote gets it, pointing at the public repo (`CLAUDE_CONFIG_UPSTREAM_URL` in `install.sh`), whatever its name; a checkout of the public repo itself gets none. If the sync brings changes, the script re-executes itself so the rest of the run uses the updated version, and syncs once more when those changes touched the sync script: a path added to its list arrives in the same run. Skipped, with a message, while the repo has uncommitted changes or is not on its default branch (what `origin/HEAD` names, else `main` or `master`: the sync commits upstream's files into the current branch)
2. Checks **Node.js**, installs **uv** if missing, then installs/upgrades **Graphify**, **MemPalace**, **chromadb**, **RTK**, **jq**, **shellcheck** and **context-mode** (plus the Zilliz MCP server when `MILVUS_ADDRESS` is set)
3. Asks once to add `~/.local/bin` to persistent PATH (`-y` skips)
4. Copies **commands**, **scripts**, **templates** to `~/.claude/` — `commands/` and `agents/` are mirrored (deployed files with no source in the repo are pruned), `scripts/` and `templates/` are additive. `agents/` holds the three subagents `/feature` spawns, pinned to another model; a subagent dropped from the repo disappears from every machine at the next install. `mods/` goes to `~/.claude/mods/` the same additive way: `settings.json` names the deployed `paste-view` in `CLAUDE_CODE_PLUGIN_DIRS`, so every new session shows a preview of what is pasted (a pasted text as one line that gives its size and opens it whole; for an image, a line that opens it in the system viewer under a coarse mosaic of half blocks on Windows, or a real thumbnail where the terminal draws kitty graphics, which Windows Terminal and VS Code do not) with nothing fetched from a marketplace
5. Records the repo location in `~/.claude/claude-config.path`; hooks, `scripts/session-start.sh` (SessionStart hook: newest MemPalace diary entries for the repo + head of `TODO.md`, ~200 tokens) and `scripts/session-stop.sh` (Stop hook: `graphify update` + mining the repo into its MemPalace wing + vault sync, run detached) resolve the repo through this pointer instead of hardcoded absolute paths
6. Initializes **MemPalace**: creates the palace, selects the embedding model, checks index health. Repos are _not_ mined here — each one is mined into its own wing during step 16
7. Copies **CLAUDE.md** to `~/.claude/CLAUDE.md` (substitutes `${VAULT_DIR}`)
8. Registers the **MCP servers** in user scope via `claude mcp add` — `mempalace` (`mempalace-mcp`), `context-mode` and `figma`. Claude Code reads MCP servers from `~/.claude.json` or a project `.mcp.json` only, never from `settings.json`. Figma authenticates over OAuth: run `/mcp` once inside Claude Code
9. Copies **`settings.json`** — this pins the default model/effort (`fable` · `xhigh`) and points the statusline at `scripts/statusline.sh` on every machine
10. Activates **RTK** via `setup-rtk.sh`
11. Removes the five **cc-safe-setup** hooks that earlier installs left behind (`comment-strip`, `syntax-check`, `context-monitor`, `cd-git-allow`, `api-error-alert`) and fails if one is still on disk or in the deployed `settings.json`; then checks that the four guards (`hooks/*.sh`, `protect-gates.js`) are on disk and registered there, since a registered hook whose file is missing guards nothing. The blocking hooks now ship in `hooks/` (see **Quality harness** below) and are registered by `settings.json`; `comment-strip` was the real cause of the "heredoc bug" (`docs/pitfall.md`)
12. Installs **pinned plugins** via the `claude` CLI (`ponytail`, upstream `caveman`, official `context7` + `frontend-design`, `hono`, `vibe-wise`), and warns when `python3` does not run (the vibe-wise hook calls it)
13. Checks the **statusline** prerequisite (`jq`) — `scripts/statusline.sh` renders model, context, 5h/7d rate limits and git from the payload Claude Code pipes in, plus the active terse-mode badge and the project's VibeWise learning mode; no network, no login
14. Enables **ponytail** by default (terse-mode plugin) when no mode flag exists on this machine — `style-toggle.sh` switches between ponytail and caveman
15. Updates `.gitignore` in target repos (graphify block + `CLAUDE.md` + `mempalace.yaml` + `context/`) using `templates/gitignore.append`
16. Interactively selects sibling git repos to index. Per repo: graphify hooks + graph, LLM **community naming**, vault sync (report + file tree + canvas + one note per node), `mempalace.yaml` generation and mining into the repo's own wing, and a local `CLAUDE.md` **re-rendered** from `templates/CLAUDE.project.md` on every run — so a machine still holding an older generation catches up. Anything written below the template's last line is kept, and a `CLAUDE.md` install.sh never generated is left untouched (`tests/claude-md-refresh.sh` covers all four cases)
17. Runs the same pipeline on the config repo itself (forced graph refresh, no `.gitignore` management)
18. Installs a **shellcheck pre-commit gate** in the config repo — staged `*.sh` must pass `shellcheck -S warning`
19. Commits the vault and reconciles with `origin` (fetch → merge → push, retried on races) via `scripts/vault-sync.sh`

`install.sh --only claude` runs steps 4 and 7–14 only; `install.sh --only repos` runs steps 15–19 only. Steps 1–3, 5 and 6 (sync, dependencies, repo pointer, MemPalace health) run under either scope — both halves need them.

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

From then on, `scripts/sync-upstream.sh` pulls shared files from `upstream` into your private repo without touching personal files (`vault/`, `env.local`, `.claude/`). It runs at the start of every `install.sh` and nowhere else: no hook calls it between installs, so the script's 8-hour debounce (`~/.claude/.upstream-sync-stamp`) only matters if you wire one up yourself. It never touches a fork with uncommitted changes on a synced path, and it cannot sync an unreachable upstream: in both cases it exits 3 with the reason on stderr, and install.sh prints a yellow `⚠ upstream sync skipped` — the files it then deploys come from the fork as it is, possibly behind upstream — instead of the green `✓ upstream synced`.

### Obsidian vault

The public repo ships no `vault/` — `install.sh` creates it in your private repo and writes, per indexed repo, `Projets/<repo>/` with the graph report, the file tree, a `<repo>.canvas` community map and one note per graph node. To read it: Obsidian → _Open folder as vault_ → select `<your-repo>/vault`.

`scripts/vault-sync.sh` commits it and reconciles with `origin` (fetch → merge → push) at the end of every install and every session, so several machines can write to the same vault.

### Options

Nothing below is required — defaults work.

| Where       | Option                                               | Effect                                                                                  |
| ----------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| CLI         | `install.sh -y`                                      | Non-interactive: keeps each repo's current indexing state, auto-accepts the PATH change |
| CLI         | `install.sh -v`                                      | Verbose installer output                                                                |
| CLI         | `install.sh --only claude`                           | Claude side only: `~/.claude` files, settings, MCP servers, plugins; skips the repos    |
| CLI         | `install.sh --only repos`                            | Repos side only: graph, community names, vault, MemPalace wings; skips the Claude files |
| Prompt      | PATH                                                 | Asked once, to add `~/.local/bin` to `~/.bashrc` / `~/.bash_profile` / `~/.profile`     |
| Prompt      | Repo selection                                       | Which sibling git repos to index (graphify + MemPalace + vault)                         |
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
├── settings.json                # Permissions, hooks, effort level, attribution
├── mempalace.yaml               # This repo's own MemPalace wing + mining exclusions
├── .graphifyignore              # Keeps vault/ (generated) out of this repo's own graph
├── .gitignore                   # env.local, vault/, context/, graphify-out/: the per-machine and generated side
├── .gitattributes               # LF everywhere; vault/ and graphify-out/ merge "ours", no eol conversion
├── README.md                    # This file
├── README.fr.md                 # Same, in French
│
├── .github/workflows/
│   ├── arch-gates-python.yml    # Reusable CI workflow: import cycles + layer contracts of a Python package
│   ├── arch-gates-frontend.yml  # Reusable CI workflow: import cycles + layer contracts under src/ (dependency-cruiser)
│   ├── baseline-ratchet.yml     # Reusable CI workflow: a gate baseline may only shrink
│   ├── mutation-gate.yml        # Reusable CI workflow: mutmut on what [tool.mutmut] names, then the not-killed mutants against the baseline
│   ├── quality-python.yml       # Reusable CI workflow: ruff C901 and jscpd on a Python package, then both against their baselines
│   ├── quality-frontend.yml     # Reusable CI workflow: the project's eslint with the complexity rule and jscpd under src/, then both against their baselines
│   └── ci.yml                   # This repo's own CI: shellcheck + every test under tests/, on ubuntu and macos
├── gates/python/
│   ├── check_imports.py         # Python cycles + layers gate (grimp), run by arch-gates-python.yml at the pinned tag
│   ├── check_mutation.py        # Mutation gate: the mutants the tests do not kill (mutmut) may only shrink, run by mutation-gate.yml
│   └── check_quality.py         # Complexity (ruff C901, eslint complexity) and duplication (jscpd) gates: both may only shrink, run by quality-*.yml
├── agents/                      # Subagents → ~/.claude/agents/ (mirrored), pinned to another model, spawned by /feature
│   ├── plan-reviewer.md         # Reviews the plan against the spec before any code, read-only
│   ├── spec-tester.md           # Writes the acceptance tests from the spec, before the code exists
│   └── diff-reviewer.md         # Adversarial review of the diff against spec, tests and gate output, read-only
├── commands/                    # Slash-commands → ~/.claude/commands/
├── hooks/                       # PreToolUse guards → ~/.claude/hooks/ (Bash and PowerShell tools)
│   ├── protect-gates.js         # Blocks Claude's edits to gate configs, baselines, workflows, hook bypasses, merge, labels, ref deletion
│   ├── destructive-guard.sh     # rm -rf on broad paths, git reset --hard, git clean, forced checkout (vendored, cc-safe-setup)
│   ├── branch-guard.sh          # Push to main/master, force push (vendored, cc-safe-setup)
│   └── secret-guard.sh          # git add of .env / keys / credentials (vendored, cc-safe-setup)
├── scripts/                     # Utility scripts → ~/.claude/scripts/
│   ├── baseline-ratchet.cjs     # Compares baselines between two refs; run by the workflow above (.cjs: callers may be ESM packages)
│   ├── repo-identity.sh         # Shared lib: canonical_repo_name()
│   ├── session-start.sh         # SessionStart hook: starts the MemPalace daemon, diary + TODO.md head, one line when MemPalace is down
│   ├── session-stop.sh          # Stop hook: graphify update + wing mine + vault sync
│   ├── statusline.sh            # Statusline: model, context, rate limits, mode, VibeWise, git
│   ├── style-toggle.sh          # Switch terse mode: ponytail ⇄ caveman ⇄ off
│   ├── vibe-toggle.sh           # VibeWise learning mode of the current project: on ⇄ off, status
│   ├── setup-rtk.sh             # Install RTK
│   ├── sync-upstream.sh         # Sync shared files from upstream remote
│   ├── sync-graph-to-vault.sh   # Sync Graphify → Obsidian vault
│   ├── vault-sync.sh            # Commit + fetch/merge/push the vault (multi-machine safe)
│   └── exclude-from-index.sh    # Remove a repo from graphify + mempalace
├── templates/
│   ├── CLAUDE.project.md        # Per-repo CLAUDE.md, re-rendered on every install
│   ├── gitignore.append         # .gitignore entries appended by install.sh
│   └── gates/                   # What /init-gates creates in a repo: dependency-cruiser config, the CI callers of the three gate families
├── mods/paste-view/             # Claude Code mod → ~/.claude/mods/: pasted images and long texts previewed above the prompt (vendored, Amorfx/claude-paste-view, Windows added); claude plugin test mods/paste-view
├── docs/
│   └── pitfall.md               # Append-only log of traps Claude Code hit in this repo
└── tests/
    ├── claude-md-refresh.sh     # Self-check for the per-repo CLAUDE.md refresh
    ├── statusline.sh            # Pins the statusline line format against a fixture payload
    ├── vibe-toggle.sh           # vibe-toggle.sh on throwaway projects (lookup, on/off, CRLF, symlinks), the VibeWise statusline line, the plugin's wiring
    ├── vibe-toggle-write.sh     # What vibe-toggle.sh writes: only the plugin's markers, line endings and a missing final newline kept, a failed write leaves the notes whole
    ├── legacy-hooks.sh          # install.sh must remove the dropped cc-safe-setup hooks and notice a leftover
    ├── install-scope.sh         # install.sh --only: usage names both halves, bad values are refused, the guard answers right
    ├── sync-upstream.sh         # The upstream sync on two throwaway repos: dirty or unreachable = exit 3 (skipped), clean = pulled and committed, a path added to the list = brought by install.sh's second pass
    ├── readme-structure.sh      # Both READMEs against git ls-files: every tree entry tracked, every tracked entry in the tree, command table = commands/
    ├── workflows-yaml.sh        # Every workflow and gate template parses as YAML (js-yaml): a broken one runs nothing and reaches no PR
    ├── mempalace-health.sh      # install.sh looks for venv holders before uv, trusts an import over a version, fails closed on a broken venv; session-start.sh starts the daemon and says when MemPalace is down
    ├── hooks.test.js            # Every guard in hooks/, fed Bash and PowerShell payloads (node --test "tests/*.test.js")
    ├── baseline-ratchet.test.js # The ratchet on real baselines from a pilot repository
    ├── gates-template.test.js   # The dependency-cruiser template on a toy project: layers, cycle, module in no layer, path alias
    ├── python/conftest.py       # load_gate(name): a gate script loaded from gates/python by file, the way CI runs it
    ├── python/test_check_imports.py # The Python gates on toy graphs, temp trees and end to end (uv run --no-project --with grimp==3.14 --with pytest pytest tests/python)
    ├── python/test_check_mutation.py # The mutation gate on written .meta files, and on a real mutmut run of a toy package (Linux and macOS: mutmut refuses native Windows)
    ├── python/test_check_quality.py # The complexity and duplication gates on reports cut from real runs, and on real ruff, eslint and jscpd runs over toy projects
    └── fixtures/                # Real baselines and pyproject.toml from a pilot repository, anonymized
```

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
| `/feature`              | A feature end to end on a local branch: plan, plan review by another model, tests from the spec seen red, code, gates, tests frozen by git, adversarial review, report; no PR (human-only) |
| `/find-dead-code`       | Find dead code in the project                                                         |
| `/init-context`         | Generate `context/architecture.md`, `patterns.md`, `constraints.md` from the codebase |
| `/init-gates`           | Install the gates in a repo, architecture, quality and mutation: propose layers, thresholds and the mutation target, wait for approval, create configs, baselines and CI callers, open a PR (human-only) |
| `/review-changes`       | Analyze changes since last commit                                                     |
| `/review-codebase`      | Evaluate a freshly cloned repository                                                  |
| `/review-comments`      | Analyze code comment quality                                                          |
| `/review-documentation` | Check doc/code consistency                                                            |
| `/review-quality`       | Evaluate code quality                                                                 |
| `/review-stack`         | Audit the technology stack                                                            |
| `/style-toggle`         | Switch terse mode: ponytail ⇄ caveman ⇄ off (empty = status)                          |
| `/update-agents`        | Update AGENTS.md                                                                      |
| `/update-documentation` | Update documentation                                                                  |
| `/update-prompts`       | Adapt prompt examples to the current project                                          |
| `/vibe-toggle`          | Turn VibeWise learning mode on or off for the current project (empty = status)        |

</details>

---

<details>
<summary><strong>Terse modes (ponytail / caveman)</strong></summary>

Two pinned plugins reduce token consumption: **ponytail** (YAGNI decision ladder — less generated code) and **caveman** (prose compression). Running both is redundant, so exactly one is active at a time — ponytail by default. Switch in one command:

```bash
bash ~/.claude/scripts/style-toggle.sh [ponytail|caveman|off|status] [level]
```

Also available as a slash command inside Claude Code: `/style-toggle [same arguments]` (empty = status).

Ponytail levels: `lite`, `full` (default), `ultra`. Caveman adds `wenyan-lite`, `wenyan-full`, `wenyan-ultra`.

Persistent state is each plugin's user config (`defaultMode` in `%APPDATA%\<plugin>\config.json`, or `$XDG_CONFIG_HOME`/`~/.config`): their SessionStart hooks re-read it and rewrite the session flag (`~/.claude/.ponytail-active` / `.caveman-active`) on every session start — the builtin default is `full`, so the switch must write the config, not just the flag. `style-toggle.sh` writes both (config for persistence, flag for an immediate statusline update). Both plugins stay installed — the inactive one is simply dormant; `/ponytail` and `/caveman` remain available for per-session tweaks. On a new machine, `install.sh` enables ponytail (`full`) when neither plugin config exists. `scripts/statusline.sh` renders whichever mode is active.

</details>

<details>
<summary><strong>Learning mode (VibeWise)</strong></summary>

The pinned **vibe-wise** plugin turns work on a project into a learning session: Claude asks for your design first, explains what is unfamiliar, and writes the code once you approve the step. Unlike the terse modes it is **per project**: its state lives in `<project>/.vibe-wise/` (learner notes, to keep out of git), and installing the plugin changes nothing until a project is started.

- First time in a project: type `/vibe-wise:learn`, the plugin's onboarding (only a human can start it).
- After that: `/vibe-toggle off` pauses it, `/vibe-toggle on` resumes it, `/vibe-toggle` shows the state. From a shell:

```bash
bash ~/.claude/scripts/vibe-toggle.sh [on|off|status] [dir]
```

`vibe-toggle.sh` rewrites the `Learning mode:` line of the project's `profile.md`, which the plugin's SessionStart hook reads at every session start, `/clear` and compaction: a switch fully applies from the next of those (`/vibe-wise:learn` starts it at once). The statusline shows `VibeWise │ On · Normal` (the checkpoint frequency), `VibeWise │ Off` when paused, and no line in a project without notes. The hook needs a `python3` that runs; `install.sh` warns when it does not.

</details>

---

<details>
<summary><strong>Pinned plugins</strong></summary>

`install.sh` installs the same Claude Code plugins on every machine via the `claude` CLI (list: `PINNED_PLUGINS` array in `install.sh`):

| Plugin     | Source                                                                | Purpose                                                                                        |
| ---------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | YAGNI decision ladder — less generated code (reuse → stdlib → existing dependency → minimum)   |
| `caveman`  | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | Upstream compression plugin — replaces the local CLAUDE.md block, adds stats/compress commands |
| `context7` | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Remote MCP (2 tools) — current docs for any library, on demand                     |
| `frontend-design` | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Skill — opinionated visual direction, away from the generic "AI aesthetic"    |
| `hono` | [honojs/skills](https://github.com/honojs/skills)     | Skill — inline Hono API reference (routing, middleware, validators, JSX) + `npx hono request` |
| `vibe-wise` | [nykooi1/vibe-wise](https://github.com/nykooi1/vibe-wise) | Learning mode, per project — you design, Claude explains and writes the agreed code; `/vibe-toggle` switches it, the statusline shows it |

If the `claude` CLI is not in PATH, the step is skipped with a warning; install manually with `claude plugin marketplace add <repo> && claude plugin install <name>@<marketplace>`.

</details>

---

<details>
<summary><strong>Hooks</strong></summary>

Configured in `settings.json`:

| Hook          | Trigger           | Action                                                                                            |
| ------------- | ----------------- | ------------------------------------------------------------------------------------------------- |
| `SessionStart` | Session start / after compaction | `session-start.sh` — starts the MemPalace daemon (hook writes are routed `require`: through the daemon or skipped, never beside it), newest diary entries for this repo + head of `TODO.md`, one line when MemPalace is down |
| `PreToolUse`  | Every tool call   | `context-mode` hook; on `Bash` calls, `rtk hook claude` rewrites the command through RTK; on `Bash` and `PowerShell`, the three `hooks/*.sh` guards then `protect-gates.js`; on `Edit`/`Write`/`MultiEdit`/`NotebookEdit`, `protect-gates.js` |
| `PostToolUse` | Every tool call   | `context-mode` hook                                                                               |
| `Stop`        | End of session    | MemPalace save + `session-stop.sh`, detached (graphify update + wing mine + vault sync)           |
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

Via MCP (in Claude Code): `mempalace_search`. The write tools (`mempalace_add_drawer`…) are refused while the daemon owns the palace — memories are written to files (`context/*.md`, the global `CLAUDE.md`) that the Stop hook mines.

</details>

---

<details>
<summary><strong>Zilliz — Semantic search (optional)</strong></summary>

When `MILVUS_ADDRESS` is set in `env.local`, the Zilliz MCP tools are available to Claude for semantic "find where X is handled" queries on large repos — the tool descriptions drive their use, the global CLAUDE.md no longer carries a Zilliz section. Graphify provides structural navigation; Zilliz provides semantic relevance.

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

There are no templates: the command creates `context/` if needed and writes the three files from the codebase itself. Claude reads them automatically at session start if the `context/` directory exists (via the Per-Repo Context rule in `CLAUDE.md`).

</details>

---

<details>
<summary><strong>Pitfalls log</strong></summary>

`docs/pitfall.md` is an append-only log of the non-obvious problems Claude Code ran into while working on this repo: behaviours invisible from the code, traps that cost a session, assumptions that turned out wrong. Unlike `context/` (gitignored, regenerated by `/init-context`), it is versioned and grows by hand, one entry per issue.

Each entry records the area, the symptom, the real cause, the workaround or fix, and a status (`open` while the trap is still in the code, `fixed <sha>` once it is gone). Claude reads it before touching an area it mentions and appends an entry whenever a session hits something that would have been faster to know up front. The Stop hook mines it into the repo's MemPalace wing with the rest of `docs/`.

</details>

---

<details>
<summary><strong>Quality harness — the doors Claude cannot open</strong></summary>

Principles: whatever blocks is deterministic, LLM reviewers are consultative, the merge is the only human gesture, a baseline may only shrink. The harness closes the exits in four layers:

| Layer | Blocks | Notes |
| --- | --- | --- |
| `settings.json` deny rules | `gh pr merge`, `git rebase`, force pushes, `rtk proxy` | evaluated before any allow rule, in every permission mode |
| `hooks/destructive-guard.sh`, `branch-guard.sh`, `secret-guard.sh` | `rm -rf` on broad paths, `git reset --hard`, `git clean`, forced checkouts, pushes to `main`, force pushes, staging `.env` or key files; without `jq` they refuse every command (exit 2) instead of reading an empty one | vendored from cc-safe-setup 30.0.7 (MIT), patched to also match `rtk git …` and `cd … && git …`, and to fail closed without `jq` |
| `hooks/protect-gates.js` | edits to gate configs (`.dependency-cruiser.*`, `eslint.config.*`, `ruff.toml`, `mypy.ini`, `.github/workflows/*`), to baselines (`*-baseline.json`, `.dependency-cruiser-known-violations.json`), to the pre-commit hook scripts themselves (`.git/hooks/*`, `.husky/*`, `.pre-commit-config.yaml`) and `.git/config`, and to the `[tool.ruff\|mypy\|mutmut\|pytest]` sections of `pyproject.toml` (dependencies stay free); `git commit --no-verify` (any prefix git accepts, `-n` bundled too), a `core.hooksPath` set or passed with `-c`, `HUSKY=0` set for the command (not mentioned in a message), `--update-baseline`, `lint:arch:baseline`, `gh pr merge`, `gh pr edit --add-label`, the REST endpoints behind them and the commit-status endpoint (`/statuses/<sha>`); `git merge` and any push landing on `main`/`master` (refspec, `HEAD`, `--all`, bare push from main) unless the latest message the human typed is `/create-commit`; any push that deletes a remote ref (`--delete`, `-d`, `:ref`) or rewrites one (`+ref`, `--force`, `-f`, `--force-with-lease`), `main` included and with no exemption, and the REST twins (`DELETE`/`PATCH /git/refs/<ref>`, `gh release delete`); shell or PowerShell writes (`>`, `sed -i`, `tee`, `cp`, `mv`, `rm`, `Set-Content`, `Out-File`, `Add-Content`, `Copy-Item`, `Move-Item`, `Remove-Item`) to any of those files; the harness itself (`~/.claude/settings.json`, `~/.claude/hooks/*`, `.claude/settings*.json`, the session transcripts `~/.claude/projects/**/*.jsonl` that carry that marker) | Node, no dependency; `PreToolUse` on `Bash\|PowerShell` and on `Edit\|Write\|MultiEdit\|NotebookEdit` |
| `.github/workflows/baseline-ratchet.yml` | a baseline that grows, appears or disappears in a PR | CI — the layer that actually holds; the hooks are speed bumps |
| `.github/workflows/arch-gates-python.yml`, `arch-gates-frontend.yml` | a new import cycle, a new upward import between layers, a module in no layer | CI; Python through `gates/python/check_imports.py` (grimp), frontend through dependency-cruiser, both runtime imports only, direct edges, module-level cycles |

Every hook fires for the Bash tool and for the PowerShell tool alike; `tests/hooks.test.js` feeds both payloads. Starting Claude Code with `PROTECT_GATES=off` in the environment turns protect-gates into a visible warning for that session — except for the harness paths, which stay blocked. The CI ratchet is never off.

`/feature` is the harness applied to one feature, in this order: plan; review of the plan by `agents/plan-reviewer.md`, another model with no memory of the session; the owner approves; `agents/spec-tester.md` writes the acceptance tests from the spec, which are run red and committed alone; code; the repo's own gates; `git diff` against that commit proves the tests untouched; `agents/diff-reviewer.md` reads the diff adversarially; one fix pass, gates again; a report. The branch stays local: the owner reads, runs `/create-pr`, and merges.

**Known limit, accepted.** The hooks match command spellings, so they stop accidents, not a deliberate bypass: a write from an interpreter (`node -e "fs.appendFileSync(…)"`) reaches a baseline or forges the `/create-commit` marker in a transcript. GitHub branch protection is what holds, and `main` is protected with admins exempted by choice — so the owner's token, which Claude also uses, can bypass it. Turning on "Do not allow bypassing the above settings" closes that, at the cost of a PR for every change to `main`, the owner's included.

**Wire the ratchet into a repo.** One file, added by a human (protect-gates blocks Claude from writing workflows):

```yaml
# .github/workflows/baseline-ratchet.yml
name: baseline-ratchet
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]   # the override label must re-run the check
permissions:
  contents: read
  pull-requests: write   # for the comment posted when the label is used
jobs:
  ratchet:
    uses: RemiAsselin42/claude-config/.github/workflows/baseline-ratchet.yml@v1
```

`@v1` is a tag on this repo. A `v*` tag is immutable (ruleset `24734324`: no update, no deletion, no bypass); each release is a new annotated tag `vN+1` plus a PR that moves the callers to it, never a tag re-pointed in place. The job checks out `scripts/baseline-ratchet.cjs` at the same commit, so the gate logic always comes from claude-config at that version, never from the branch under test (`.cjs`, not `.js`: the checkout lands inside the caller's repo, and a `"type": "module"` in its `package.json` would make Node load a `.js` as ESM and crash on `require`). A human accepts a growing baseline by setting the `baseline-update` label on the PR: the job then passes and posts the added entries as a PR comment. Limit: GitHub only sees the token, so a label set by Claude with your token is indistinguishable from one you set — hence the hook rule and the comment.

**Wire the gates into a repo.** Type `/init-gates` in it: Claude reads the import graph, proposes the layers, measures complexity and duplication with the pinned tools, proposes a mutation target on the Python side, waits for your approval on each family, then creates everything on a `ci/gates` branch and opens a PR. A family the repo already has is left alone; the others are added. While `/init-gates` is the latest message you typed, protect-gates lets Claude *create* a gate file that does not exist yet — never change or delete one — and the baselines come from `--init-baseline`, which refuses to overwrite. The `[tool.mutmut]` section is the one thing Claude adds to `pyproject.toml`: under `/init-gates`, protect-gates lets it add that section to a file that has none, every other tool section byte for byte as before. One thing stays yours: `mutation-baseline.json`, printed by the PR's first run since mutmut cannot run on Windows, and refused to Claude even under `/init-gates`. The PR's ratchet is red by design (every baseline is new): your `baseline-update` label is how you accept the frozen debt.

By hand, the logic (the Python script, the grimp and dependency-cruiser versions, the flags) comes from this repo at the pinned tag; the repo keeps only its declarations, all protected by protect-gates and the ratchet:

- `backend/arch-gates.json` — the root package and its layers, lowest first. An entry covers the module and its submodules, except the root package, which covers only itself: a new subpackage fails the gate (exit 2) until it is classified.

  ```json
  {"package": "app", "layers": [
    {"name": "config", "modules": ["app", "app.config"]},
    {"name": "adapters", "modules": ["app.db", "app.parsers"]},
    {"name": "web", "modules": ["app.routes", "app.main"]}]}
  ```

- `backend/import-cycles-baseline.json`, `backend/import-layers-baseline.json` — the frozen debt, next to `arch-gates.json`.
- `frontend/.dependency-cruiser.cjs` from `templates/gates/dependency-cruiser.cjs`: only its `LAYERS` array and `tsConfig` change per repo; the rules (`no-circular`, one `layer-*` per layer, a module in no layer) derive from it. `frontend/.dependency-cruiser-known-violations.json` is the baseline.

```yaml
# .github/workflows/arch-gates.yml — keep only the job(s) of the sides the repo has
name: arch-gates
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  arch-python:
    uses: RemiAsselin42/claude-config/.github/workflows/arch-gates-python.yml@v3
    with:
      config: backend/arch-gates.json
  arch-frontend:
    uses: RemiAsselin42/claude-config/.github/workflows/arch-gates-frontend.yml@v3
    with:
      dir: frontend
```

One reusable workflow per side and no `if` in them: a side the repo lacks has no job, so nothing shows as skipped, and a required check can only go missing — which blocks the merge — never be skipped past by emptying an input (the single `arch-gates.yml@v2` of before did exactly that).

Run them locally before pushing, from the repo root:

```bash
gates="$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"
uv run --no-project --with grimp==3.14 python "$gates" cycles --config backend/arch-gates.json
uv run --no-project --with grimp==3.14 python "$gates" layers --config backend/arch-gates.json
(cd frontend && npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --config .dependency-cruiser.cjs --ignore-known)
```

**Make the checks required on `main`.** GitHub → repository → Settings → Branches → add a branch protection rule for `main` → tick *Require a pull request before merging*, *Require status checks to pass before merging* and *Require branches to be up to date before merging*, then add each check by name (a check is offered once it has run on at least one PR). Also tick *Do not allow bypassing the above settings*, otherwise an admin token — yours, hence Claude's — merges past the checks. Names are `<workflow name> / <job name>` as GitHub lists them: the repo's own gate jobs, plus `ratchet / ratchet`, `arch-python / python` and `arch-frontend / frontend` (`<caller job> / <called job>`) once the caller workflows above are on `main`.

**Migrating a `@v2` caller.** Switch the caller to the `@v3` jobs above on a branch and let its PR run once, so the new check names exist. Then, in the branch protection of `main`: add `arch-python / python` and/or `arch-frontend / frontend`, and remove `arch / python` and `arch / frontend` — a required name that no longer runs stays "Expected" and blocks every PR. Leave the other required checks (`ratchet / ratchet`, the repo's own jobs) untouched. Do it before merging that PR.

**Mutation gate (Python).** `mutmut` rewrites the files `[tool.mutmut]` names in `pyproject.toml` one mutant at a time and runs the selected tests against each one; a mutant the tests still pass on, or that no selected test reaches, is a hole in the tests. `gates/python/check_mutation.py` reads mutmut's `mutants/*.meta` and compares those not-killed mutants with `backend/mutation-baseline.json`, a list of `[name, hash of the function]` pairs: a new one fails (exit 1), a baselined one is tolerated while its function is unchanged (mutant names are positional, an edit renumbers them), and the file may only shrink (ratchet). mutmut refuses native Windows, so the gate runs in CI only: the caller is `templates/gates/mutation-gate.yml` (`uses: …/mutation-gate.yml@v4`, `with: dir: backend`), check `mutation / mutation`. The first run has no baseline and is red with the list to commit as the baseline; `mutmut show <name>` prints a mutant's diff. Make the check required once its run time is known: a few minutes belongs on every PR, more belongs on a separate trigger.

**Complexity and duplication gates.** `gates/python/check_quality.py` ratchets two reports per side: the cyclomatic complexity of every function above the threshold (ruff `C901` on the Python side, eslint's `complexity` rule on the frontend, both imposed on the command line, the repo's own ruff and eslint configurations untouched) and the clones jscpd finds. `complexity-baseline.json` holds `[file, function, complexity]`: a new function above the threshold fails, a known one fails when it got more complex, one that shrank is reported so the baseline can follow. Anonymous functions ("Arrow function") get an ordinal by order of appearance in the file; an ordinal is a position, not an identity, so naming the function is the only way to track it for sure. `duplication-baseline.json` holds `[fingerprint, format, lines, file A, file B]`, the fingerprint hashing the duplicated text so moved lines keep their entry; the gate counts the pairs per fingerprint, so a third copy of a known block fails too. A file a tool cannot parse is a blind spot (exit 2), never a function fixed. The CI ratchet reads an entry whose last field is a number as a measure under a key: a lower value is a shrink, a higher one is growth. Caller: `templates/gates/quality-gates.yml`, one job per side (`quality-python.yml@v5` with `dir`, `package`; `quality-frontend.yml@v5` with `dir`, which installs the project's lint dependencies from its lockfile), checks `quality-python / python` and `quality-frontend / frontend`. Thresholds and jscpd scope are inputs (`max-complexity`, `jscpd-ignore`, `jscpd-formats`). The first run has no baseline and is red with the lists to commit.

</details>

---

## See also

- [README.fr.md](README.fr.md) — French version
