# claude-config

Configuration partagée pour Claude Code : slash-commands, scripts et hooks, mémoire persistante (MemPalace) et optimisation de tokens (RTK). Un seul clone, une installation partout, synchronisation automatique.

> [!WARNING]
> **Les scripts de ce dépôt modifient l'environnement système de la machine qui les exécute.**
>
> `install.sh` et les scripts utilitaires effectuent des opérations destructives et persistantes :
>
> - **Écritures** dans `~/.claude/` (commandes, scripts, templates, settings, CLAUDE.md)
> - **Purge** de `~/.claude/commands/` et `~/.claude/agents/` : tout ce qui s'y trouve sans fichier source dans le repo est supprimé à chaque exécution — le repo ne contient pas d'`agents/`, donc chaque install vide `~/.claude/agents/`
> - **Installation de paquets** globaux (`graphify`, `mempalace`, `rtk`)
> - **Modification du PATH** : ajoute `~/.local/bin` dans `~/.bashrc`, `~/.bash_profile` et `~/.profile`, après confirmation sauf en mode `-y`
> - **Suppression de fichiers** (`graphify-out/`, wings mempalace, dossiers vault) via `exclude-from-index.sh`
> - **Écriture de hooks et de config git** dans les repos cibles (post-commit sync vault, gate `pre-commit` shellcheck dans ce repo, `merge.ours.driver` / `pull.rebase false`)
> - **Commits et push git** automatiques sur le vault
>
> Lire `install.sh` avant exécution. Ne pas utiliser sur une machine dont la config `~/.claude/` est déjà gérée par un autre workflow.

---

## Modèle public / privé

Ce repo est la **base partagée**. Il contient tout ce qui est utile à n'importe qui : commandes, scripts, templates de settings. Il ne contient **aucune donnée personnelle** (pas de vault, pas de secrets).

Pour un usage personnel avec vault Obsidian versionné et overrides privés, forker ou étendre ce repo de façon privée :

```
claude-config (ce repo, public)
    └── upstream ── votre-claude-config (repo privé)
                        ├── vault/          # vault Obsidian personnel
                        └── env.local       # secrets machine-specific
```

Le repo privé se synchronise automatiquement avec celui-ci — voir [Installation minimale](#installation-minimale).

---

## Prérequis

- [Node.js](https://nodejs.org)
- `curl` pour l'installation automatique de [uv](https://astral.sh/uv) si absent
- bash 4.4+ (Git Bash sous Windows et tout Linux conviennent ; sur macOS `brew install bash`, le 3.2 livré ne peut pas exécuter le script)

---

## Ce que fait `install.sh`

1. Synchronise depuis `upstream` **en premier** si le remote existe (les repos privés récupèrent automatiquement la dernière config partagée) ; si la sync apporte des changements, le script se relance automatiquement pour que la suite s'exécute avec la version à jour. Ignorée, avec un message, tant que le repo a des modifications non commitées
2. Vérifie **Node.js**, installe **uv** si absent, puis installe/met à jour **Graphify**, **MemPalace**, **chromadb**, **RTK**, **jq**, **shellcheck** et **context-mode** (plus le serveur MCP Zilliz si `MILVUS_ADDRESS` est défini)
3. Demande une seule confirmation si `~/.local/bin` doit être ajouté au PATH persistant (`-y` accepte automatiquement)
4. Copie les **commandes**, **scripts** et **templates** vers `~/.claude/` — `commands/` et `agents/` sont en miroir (les fichiers déployés sans source dans le repo sont purgés), `scripts/` et `templates/` sont additifs. Le repo n'a plus d'`agents/` depuis `3eb0605`, donc cette étape vide `~/.claude/agents/` à chaque exécution
5. Enregistre l'emplacement du repo dans `~/.claude/claude-config.path` ; les hooks, `scripts/session-start.sh` (hook SessionStart : dernières entrées du diary MemPalace du repo + tête de `TODO.md`, ~200 tokens) et `scripts/session-stop.sh` (hook Stop : `graphify update` + mining du repo dans son wing MemPalace + sync vault, exécuté détaché) résolvent le repo via ce pointeur plutôt que par chemin absolu en dur
6. Initialise **MemPalace** : création du palace, choix du modèle d'embedding, vérification de l'index. Les repos ne sont _pas_ minés ici — chacun l'est dans son propre wing à l'étape 16
7. Copie **CLAUDE.md** vers `~/.claude/CLAUDE.md` (substitution `${VAULT_DIR}`)
8. Enregistre les **serveurs MCP** en scope user via `claude mcp add` — `mempalace` (`mempalace-mcp`), `context-mode` et `figma`. Claude Code ne lit les serveurs MCP que depuis `~/.claude.json` ou un `.mcp.json` de projet, jamais depuis `settings.json`. Figma s'authentifie en OAuth : lancer `/mcp` une fois dans Claude Code
9. Copie **`settings.json`** — épingle le modèle/effort par défaut (`opus[1m]` · `xhigh`) et pointe la statusline vers `scripts/statusline.sh` sur chaque machine
10. Active **RTK** via `setup-rtk.sh`
11. Supprime les cinq hooks **cc-safe-setup** laissés par les installs précédentes (`comment-strip`, `syntax-check`, `context-monitor`, `cd-git-allow`, `api-error-alert`) et échoue s'il en reste un sur disque ou dans le `settings.json` déployé. Les hooks bloquants vivent désormais dans `hooks/` (voir **Harnais qualité** plus bas) et sont enregistrés par `settings.json` ; `comment-strip` était la vraie cause du « bug heredoc » (`docs/pitfall.md`)
12. Installe les **plugins épinglés** via le CLI `claude` (`ponytail`, `caveman` upstream, `context7` + `frontend-design` officiels, `hono`)
13. Vérifie le prérequis de la **statusline** (`jq`) — `scripts/statusline.sh` affiche modèle, contexte, limites 5h/7j et git à partir du payload que Claude Code lui envoie, plus le badge du mode terse actif ; sans réseau, sans login
14. Active **ponytail** par défaut (plugin de mode terse) si aucun flag de mode n'existe sur la machine — `style-toggle.sh` bascule entre ponytail et caveman
15. Met à jour `.gitignore` dans les repos cibles (bloc graphify + `CLAUDE.md` + `mempalace.yaml` + `context/`) via `templates/gitignore.append`
16. Sélection interactive des repos git frères à indexer. Par repo : hooks + graphe graphify, **nommage LLM des communautés**, sync vault (rapport + arbre de fichiers + canvas + une note par nœud), génération de `mempalace.yaml`, mining dans le wing du repo, et un `CLAUDE.md` local **re-rendu** depuis `templates/CLAUDE.project.md` à chaque exécution — une machine restée sur une ancienne génération se met ainsi à jour toute seule. Ce qui est écrit sous la dernière ligne du template est conservé, et un `CLAUDE.md` qu'install.sh n'a jamais généré n'est pas touché (`tests/claude-md-refresh.sh` couvre les quatre cas)
17. Applique le même pipeline au repo de config lui-même (graphe rafraîchi de force, pas de gestion du `.gitignore`)
18. Installe un **gate pre-commit shellcheck** dans le repo de config — les `*.sh` stagés doivent passer `shellcheck -S warning`
19. Commit le vault et le réconcilie avec `origin` (fetch → merge → push, réessayé en cas de course) via `scripts/vault-sync.sh`

`install.sh --only claude` n'exécute que les étapes 4 et 7–14 ; `install.sh --only repos` que les étapes 15–19. Les étapes 1–3, 5 et 6 (sync, dépendances, pointeur du repo, santé MemPalace) tournent quel que soit le scope — les deux moitiés en dépendent.

---

## Installation minimale

`install.sh` sur un clone frais donne déjà la config partagée. Deux choses en font une config personnelle : un **repo privé** pour le vault et les overrides, et **Obsidian** pour lire ce que Graphify écrit.

### Configurer un repo privé

```bash
# Cloner ce repo comme base privée
git clone https://github.com/RemiAsselin42/claude-config mon-claude-config
cd mon-claude-config

# Pointer origin vers le repo privé, garder le public comme upstream
git remote rename origin upstream
git remote add origin https://github.com/<vous>/mon-claude-config
git push -u origin main
```

Ensuite, `scripts/sync-upstream.sh` tire les fichiers partagés depuis `upstream` dans le repo privé sans toucher aux fichiers personnels (`vault/`, `env.local`, `.claude/`). Il s'exécute au début de chaque `install.sh` et nulle part ailleurs : aucun hook ne l'appelle entre deux installs, donc le debounce de 8h du script (`~/.claude/.upstream-sync-stamp`) ne sert que si tu en branches un toi-même.

### Vault Obsidian

Le repo public ne contient pas de `vault/` — `install.sh` le crée dans le repo privé et y écrit, pour chaque repo indexé, `Projets/<repo>/` avec le rapport de graphe, l'arbre de fichiers, une carte `<repo>.canvas` des communautés et une note par nœud du graphe. Pour le lire : Obsidian → _Ouvrir un dossier comme coffre_ → sélectionner `<votre-repo>/vault`.

`scripts/vault-sync.sh` le commit et le réconcilie avec `origin` (fetch → merge → push) à la fin de chaque install et de chaque session, pour que plusieurs machines puissent écrire dans le même vault.

### Options

Rien de ce qui suit n'est obligatoire — les valeurs par défaut suffisent.

| Où          | Option                                               | Effet                                                                                          |
| ----------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| CLI         | `install.sh -y`                                      | Non-interactif : conserve l'état d'indexation de chaque repo, accepte le changement de PATH    |
| CLI         | `install.sh -v`                                      | Sorties détaillées de l'installeur                                                             |
| CLI         | `install.sh --only claude`                           | Côté Claude seulement : fichiers `~/.claude`, settings, MCP, plugins ; saute les repos         |
| CLI         | `install.sh --only repos`                            | Côté repos seulement : graphe, communautés, vault, wings MemPalace ; saute les fichiers Claude |
| Prompt      | PATH                                                 | Demandé une fois, pour ajouter `~/.local/bin` à `~/.bashrc` / `~/.bash_profile` / `~/.profile` |
| Prompt      | Sélection des repos                                  | Quels repos git frères indexer (graphify + MemPalace + vault)                                  |
| `env.local` | `MEMPALACE_EMBEDDING_MODEL`                          | `embeddinggemma` (défaut, multilingue) ou `minilm` (anglais seulement, plus rapide)            |
| `env.local` | `MEMPALACE_PALACE_PATH`                              | Déplace le palace hors de `~/.mempalace/palace` (petit disque système, dossier synchronisé)    |
| `env.local` | `GRAPHIFY_LABEL_BACKEND` / `_MODEL`                  | Quel LLM nomme les communautés du graphe (défaut : le CLI `claude`, sans clé API)              |
| `env.local` | `GRAPHIFY_DEEP_EXTRACT`                              | Ré-extraction LLM ajoutant les arêtes `INFERRED` — lent, facturé sur backend payant            |
| `env.local` | `MILVUS_ADDRESS` / `MILVUS_TOKEN` / `OPENAI_API_KEY` | Active le serveur MCP de recherche sémantique Zilliz                                           |

Chaque clé est documentée en commentaire dans `env.local.template`.

---

## Structure

```
claude-config/
├── install.sh                   # Script d'installation principal
├── env.local.template           # Variables machine-specific (clé Figma, embedder, backend de labels…)
├── CLAUDE.md                    # Instructions globales pour Claude Code
├── settings.json                # Permissions, hooks, niveau d'effort, attribution
├── mempalace.yaml               # Wing MemPalace de ce repo + exclusions de mining
├── .graphifyignore              # Exclut vault/ (généré) du graphe de ce repo
│
├── .github/workflows/
│   ├── arch-gates.yml           # Workflow CI réutilisable : cycles d'imports + contrats de couches, backend et frontend
│   └── baseline-ratchet.yml     # Workflow CI réutilisable : un baseline ne peut que rétrécir
├── gates/python/
│   └── check_imports.py         # Gate Python cycles + couches (grimp), lancé par arch-gates.yml au tag épinglé
├── commands/                    # Slash-commands → ~/.claude/commands/
├── hooks/                       # Gardes PreToolUse → ~/.claude/hooks/ (outils Bash et PowerShell)
│   ├── protect-gates.js         # Bloque les éditions par Claude des configs de gate, baselines, workflows, --no-verify, merge, labels
│   ├── destructive-guard.sh     # rm -rf sur chemins larges, git reset --hard, git clean, checkout forcé (copié de cc-safe-setup)
│   ├── branch-guard.sh          # Push sur main/master, force push (copié de cc-safe-setup)
│   └── secret-guard.sh          # git add de .env / clés / credentials (copié de cc-safe-setup)
├── scripts/                     # Scripts utilitaires → ~/.claude/scripts/
│   ├── baseline-ratchet.js      # Compare les baselines entre deux refs ; exécuté par le workflow ci-dessus
│   ├── repo-identity.sh         # Lib partagée : canonical_repo_name()
│   ├── session-start.sh         # Hook SessionStart : diary MemPalace + tête de TODO.md
│   ├── session-stop.sh          # Hook Stop : graphify update + mine du wing + sync vault
│   ├── statusline.sh            # Statusline : modèle, contexte, limites, mode, git
│   ├── style-toggle.sh          # Bascule mode terse : ponytail ⇄ caveman ⇄ off
│   ├── setup-rtk.sh             # Installe RTK
│   ├── sync-upstream.sh         # Sync des fichiers partagés depuis le remote upstream
│   ├── sync-graph-to-vault.sh   # Sync graphify → vault Obsidian
│   ├── vault-sync.sh            # Commit + fetch/merge/push du vault (multi-machine)
│   └── exclude-from-index.sh    # Exclure un repo de graphify + mempalace
├── templates/
│   ├── CLAUDE.project.md        # CLAUDE.md par repo, re-rendu à chaque install
│   └── gitignore.append         # Entrées .gitignore ajoutées par install.sh
├── docs/
│   ├── harness-plan.md          # Harnais qualité déterministe : principes et lots A–E
│   └── pitfall.md               # Journal append-only des pièges rencontrés par Claude Code dans ce repo
└── tests/
    ├── claude-md-refresh.sh     # Auto-test du re-rendu des CLAUDE.md par repo
    ├── statusline.sh            # Fige le format des lignes de la statusline sur un payload fixture
    ├── legacy-hooks.sh          # install.sh doit retirer les hooks cc-safe-setup abandonnés et voir un reliquat
    ├── install-scope.sh         # install.sh --only : l'usage nomme les deux moitiés, les valeurs invalides sont refusées, le garde répond juste
    ├── hooks.test.js            # Chaque garde de hooks/, nourrie de payloads Bash et PowerShell (node --test "tests/*.test.js")
    ├── baseline-ratchet.test.js # Le ratchet sur de vrais baselines d'un repo pilote
    ├── python/test_check_imports.py # Les gates Python sur graphes jouets, arbres temporaires et de bout en bout (uv run --no-project --with grimp==3.14 --with pytest pytest tests/python)
    └── fixtures/                # Vrais baselines et pyproject.toml d'un repo pilote, anonymisés
```

---

<details>
<summary><strong>Slash-commands</strong></summary>

| Commande                | Description                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------ |
| `/apply-suggestions`    | Applique les recommandations identifiées                                             |
| `/copilot-check`        | Évalue les retours de review Copilot sur une PR avant de les appliquer               |
| `/create-commit`        | Crée un commit git                                                                   |
| `/create-pr`            | Découpe le travail en commits logiques et ouvre une PR                               |
| `/explain-changes`      | Explique les modifications récentes                                                  |
| `/find-dead-code`       | Trouve le code mort dans le projet                                                   |
| `/init-context`         | Génère `context/architecture.md`, `patterns.md`, `constraints.md` depuis le codebase |
| `/review-changes`       | Analyse les modifications depuis le dernier commit                                   |
| `/review-codebase`      | Évalue un dépôt fraîchement cloné                                                    |
| `/review-comments`      | Analyse la qualité des commentaires                                                  |
| `/review-documentation` | Vérifie la cohérence doc/code                                                        |
| `/review-quality`       | Évalue la qualité du code                                                            |
| `/review-stack`         | Audit de la pile technologique                                                       |
| `/update-agents`        | Met à jour AGENTS.md                                                                 |
| `/update-documentation` | Met à jour la documentation                                                          |
| `/update-prompts`       | Adapte les exemples des prompts au projet courant                                    |

</details>

---

<details>
<summary><strong>Modes terses (ponytail / caveman)</strong></summary>

Deux plugins épinglés réduisent la consommation de tokens : **ponytail** (échelle de décision YAGNI — moins de code généré) et **caveman** (compression de la prose). Les deux ensemble sont redondants, donc un seul est actif à la fois — ponytail par défaut. Bascule en une commande :

```bash
bash ~/.claude/scripts/style-toggle.sh [ponytail|caveman|off|status] [niveau]
```

Disponible aussi en slash command dans Claude Code : `/style-toggle [mêmes arguments]` (vide = status).

Niveaux ponytail : `lite`, `full` (défaut), `ultra`. Caveman ajoute `wenyan-lite`, `wenyan-full`, `wenyan-ultra`.

L'état persistant est la config utilisateur de chaque plugin (`defaultMode` dans `%APPDATA%\<plugin>\config.json`, ou `$XDG_CONFIG_HOME`/`~/.config`) : leurs hooks SessionStart la relisent et réécrivent le flag de session (`~/.claude/.ponytail-active` / `.caveman-active`) à chaque démarrage — le défaut intégré est `full`, donc la bascule doit écrire la config, pas seulement le flag. `style-toggle.sh` écrit les deux (config pour la persistance, flag pour la mise à jour immédiate de la statusline). Les deux plugins restent installés — l'inactif est simplement dormant ; `/ponytail` et `/caveman` restent utilisables par session. Sur une nouvelle machine, `install.sh` active ponytail (`full`) si aucune config plugin n'existe. `scripts/statusline.sh` affiche le mode actif.

</details>

---

<details>
<summary><strong>Plugins épinglés</strong></summary>

`install.sh` installe les mêmes plugins Claude Code sur chaque machine via le CLI `claude` (liste : tableau `PINNED_PLUGINS` dans `install.sh`) :

| Plugin     | Source                                                                | Rôle                                                                                                       |
| ---------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | Échelle de décision YAGNI — moins de code généré (réutilisation → stdlib → dépendance existante → minimum) |
| `caveman`  | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | Plugin de compression upstream — remplace le bloc local du CLAUDE.md, ajoute les commandes stats/compress  |
| `context7` | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | MCP distant (2 outils) — doc à jour de n'importe quelle lib, à la demande                          |
| `frontend-design` | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Skill — direction visuelle opinionée, loin de l'« esthétique IA » générique              |
| `hono` | [honojs/skills](https://github.com/honojs/skills)     | Skill — référence API Hono inline (routing, middleware, validateurs, JSX) + `npx hono request`            |

Si le CLI `claude` n'est pas dans le PATH, l'étape est sautée avec un avertissement ; installation manuelle : `claude plugin marketplace add <repo> && claude plugin install <nom>@<marketplace>`.

</details>

---

<details>
<summary><strong>Hooks</strong></summary>

Configurés dans `settings.json` :

| Hook          | Déclencheur          | Action                                                                                                 |
| ------------- | -------------------- | ------------------------------------------------------------------------------------------------------ |
| `SessionStart` | Démarrage de session / après compaction | `session-start.sh` — dernières entrées du diary MemPalace de ce repo + tête de `TODO.md` |
| `PreToolUse`  | Chaque appel d'outil | Hook `context-mode` ; sur les appels `Bash`, `rtk hook claude` réécrit la commande via RTK              |
| `PostToolUse` | Chaque appel d'outil | Hook `context-mode`                                                                                    |
| `Stop`        | Fin de session       | Sauvegarde MemPalace + `session-stop.sh`, détaché (graphify update + mine du wing + sync vault)        |
| `PreCompact`  | Avant compaction     | Sauvegarde MemPalace + hook `context-mode`                                                             |

Sous Windows, `context-mode` ne peut pas parcourir l'arbre de processus : plusieurs sessions Claude Code simultanées peuvent partager le même état. Définir `CLAUDE_SESSION_ID` avec une valeur distincte par session si tu en ouvres plusieurs.

</details>

---

<details>
<summary><strong>RTK — Proxy de tokens</strong></summary>

RTK réécrit les commandes dev courantes (ex: `git status` → `rtk git status`) pour réduire la consommation de tokens de 60–90%.

**Windows** — installé via `winget`, activé avec `rtk init -g --claude-md` : RTK fonctionne via les instructions CLAUDE.md (Claude préfixe les commandes lui-même, sans hook bash).  
**Linux/macOS** — installé via `brew` ou le script officiel, activé avec `rtk init -g` : RTK installe un hook `PreToolUse` dans `settings.json` qui réécrit les commandes de façon transparente.

Installation manuelle :

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

</details>

---

<details>
<summary><strong>Graphify</strong></summary>

Génère un graphe de connaissances de chaque codebase indexé.

```bash
graphify update .            # Mettre à jour le graphe (AST uniquement, sans coût API)
graphify query "question"    # Requête sémantique
graphify path "A" "B"        # Chemin entre deux concepts
graphify explain "concept"   # Explication d'un concept du codebase
```

Chaque repo indexé dispose de :

- `graphify-out/GRAPH_REPORT.md` — rapport local (gitignored)
- `vault/Projets/<repo>/` — copie versionnée dans le vault Obsidian (repos privés uniquement) : `<repo> - GRAPH_REPORT.md`, `<repo> - FILE_TREE.md`, `<repo>.canvas` (carte des communautés) et `obsidian/` avec une note par nœud du graphe

### Nommage des communautés

`graphify update` est AST-only : les communautés restent nommées `Community 12` dans le rapport, dans les groupes du canvas et dans chaque note. `install.sh` lance une passe de labellisation LLM par repo, uniquement quand les noms sont absents ou encore des placeholders. Le backend par défaut est le CLI `claude` déjà dans le PATH (aucune clé API). Override dans `env.local` :

```bash
GRAPHIFY_LABEL_BACKEND="ollama"   # claude-cli | gemini | openai | deepseek | kimi | ollama | none
GRAPHIFY_LABEL_MODEL="llama3"     # optionnel, défaut du backend sinon
GRAPHIFY_DEEP_EXTRACT="false"     # opt-in : ré-extraction LLM ajoutant les arêtes INFERRED (lent, facturé)
```

Un repo contenant un `.graphifyignore` est ignoré — ce repo en a un pour `vault/`, qui est la sortie de graphify et serait sinon réindexé dans le graphe.

</details>

---

<details>
<summary><strong>MemPalace</strong></summary>

Mémoire persistante cross-sessions. Les données sont dans `~/.mempalace/` (jamais versionné).

Chaque repo indexé a son propre **wing**. `install.sh` génère un `mempalace.yaml` (gitignored dans les repos cibles) contenant le nom du wing et les exclusions de mining, puis mine les fichiers du repo et ses transcripts Claude dans ce wing.

```bash
mempalace status                             # Liste les vrais noms de wings
mempalace search "sujet" --wing wing_mon_repo # Scoped au repo
mempalace search "sujet"                     # Recherche globale
```

`mine` stocke le wing sous la forme `wing_` + le nom avec les `-` remplacés par `_`, et `search --wing` matche ce nom stocké à l'identique — passer la valeur brute de `mempalace.yaml` renvoie 0 résultat.

Le modèle d'embedding et l'emplacement du palace se règlent dans `env.local` (`MEMPALACE_EMBEDDING_MODEL`, `MEMPALACE_PALACE_PATH`). Défaut : `embeddinggemma` (multilingue, ~300 Mo) ; `minilm` est plus rapide mais entraîné uniquement sur de l'anglais. Changer de modèle sur un palace existant invalide tous les vecteurs — `install.sh` détecte l'écart et demande confirmation avant de réindexer.

Pour reconstruire sur une nouvelle machine, il suffit de relancer `install.sh`.

Via MCP (dans Claude Code) : `mempalace_search`. Les outils d'écriture (`mempalace_add_drawer`…) sont refusés tant que le daemon détient le palace — les mémoires s'écrivent dans des fichiers (`context/*.md`, le `CLAUDE.md` global) que le hook Stop mine.

</details>

---

<details>
<summary><strong>Zilliz — Recherche sémantique (optionnel)</strong></summary>

Quand `MILVUS_ADDRESS` est défini dans `env.local`, les outils MCP Zilliz sont disponibles pour les requêtes sémantiques de type "où est géré X" sur les grands repos — ce sont leurs descriptions qui pilotent leur usage, le CLAUDE.md global ne contient plus de section Zilliz. Graphify assure la navigation structurelle ; Zilliz apporte la pertinence sémantique.

Configuration dans `env.local` (voir `env.local.template`) :

```bash
export MILVUS_ADDRESS="https://xxx.api.gcp-us-west1.zillizcloud.com"
export MILVUS_TOKEN="your-zilliz-api-key"
export OPENAI_API_KEY="sk-..."   # utilisé pour les embeddings
```

`install.sh` installe automatiquement le serveur MCP `@zilliz/claude-context-mcp` quand `MILVUS_ADDRESS` est défini. Sinon, cette étape est silencieusement ignorée.

</details>

---

<details>
<summary><strong>Contexte par repo</strong></summary>

Exécuter `/init-context` dans n'importe quel repo pour générer des fichiers de contexte structurés depuis le codebase réel :

- `context/architecture.md` — décisions majeures et leur justification
- `context/patterns.md` — patterns de code récurrents
- `context/constraints.md` — contraintes de performance, sécurité et compatibilité

Il n'y a pas de templates : la commande crée `context/` si besoin et écrit les trois fichiers à partir du codebase lui-même. Claude les lit automatiquement en début de session si le dossier `context/` existe (via la règle Per-Repo Context dans `CLAUDE.md`).

</details>

---

<details>
<summary><strong>Journal des pièges</strong></summary>

`docs/pitfall.md` est un journal append-only des problèmes non évidents rencontrés par Claude Code en travaillant sur ce repo : comportements invisibles depuis le code, pièges qui ont coûté une session, hypothèses qui se sont révélées fausses. Contrairement à `context/` (gitignored, régénéré par `/init-context`), il est versionné et grandit à la main, une entrée par problème.

Chaque entrée note la zone, le symptôme, la vraie cause, le contournement ou le correctif, et un statut (`open` tant que le piège est encore dans le code, `fixed <sha>` une fois disparu). Claude le lit avant de toucher une zone qu'il mentionne et y ajoute une entrée dès qu'une session bute sur quelque chose qu'il aurait été plus rapide de savoir d'avance. Le hook Stop le mine dans le wing MemPalace du repo avec le reste de `docs/`.

</details>

---

<details>
<summary><strong>Harnais qualité — les portes que Claude ne peut pas ouvrir</strong></summary>

Principes : ce qui bloque est déterministe, les reviewers LLM sont consultatifs, le merge est le seul geste humain, un baseline ne peut que rétrécir. Le harnais ferme les sorties en quatre couches :

| Couche | Bloque | Notes |
| --- | --- | --- |
| Règles `deny` de `settings.json` | `gh pr merge`, `git rebase`, force push, `rtk proxy` | évaluées avant toute règle `allow`, quel que soit le mode de permission |
| `hooks/destructive-guard.sh`, `branch-guard.sh`, `secret-guard.sh` | `rm -rf` sur chemins larges, `git reset --hard`, `git clean`, checkout forcé, push sur `main`, force push, `git add` de `.env` ou de clés | copiés de cc-safe-setup 30.0.7 (MIT), retouchés pour matcher aussi `rtk git …` et `cd … && git …` |
| `hooks/protect-gates.js` | éditions des configs de gate (`.dependency-cruiser.*`, `eslint.config.*`, `ruff.toml`, `mypy.ini`, `.github/workflows/*`), des baselines (`*-baseline.json`, `.dependency-cruiser-known-violations.json`) et des sections `[tool.ruff\|mypy\|mutmut\|pytest]` de `pyproject.toml` (les dépendances restent libres) ; `git commit --no-verify`, `--update-baseline`, `lint:arch:baseline`, `gh pr merge`, `gh pr edit --add-label` et les endpoints REST derrière ; `git merge` et tout push qui atterrit sur `main`/`master` (refspec, `HEAD`, `--all`, push nu depuis main) sauf si le dernier message tapé par l'humain est `/create-commit` ; écritures shell ou PowerShell (`>`, `sed -i`, `tee`, `cp`, `mv`, `rm`, `Set-Content`, `Out-File`, `Add-Content`, `Copy-Item`, `Move-Item`, `Remove-Item`) vers ces fichiers ; le harnais lui-même (`~/.claude/settings.json`, `~/.claude/hooks/*`, `.claude/settings*.json`, les transcripts de session `~/.claude/projects/**/*.jsonl` qui portent ce marqueur) | Node, sans dépendance ; `PreToolUse` sur `Bash\|PowerShell` et sur `Edit\|Write\|MultiEdit\|NotebookEdit` |
| `.github/workflows/baseline-ratchet.yml` | un baseline qui grossit, apparaît ou disparaît dans une PR | CI — la couche qui tient vraiment ; les hooks sont des ralentisseurs |
| `.github/workflows/arch-gates.yml` | un nouveau cycle d'imports, une nouvelle remontée entre couches, un module sans couche | CI ; Python via `gates/python/check_imports.py` (grimp), frontend via dependency-cruiser, imports runtime uniquement, arêtes directes, cycles entre modules des deux côtés |

Chaque hook se déclenche pour l'outil Bash comme pour l'outil PowerShell ; `tests/hooks.test.js` envoie les deux payloads. Lancer Claude Code avec `PROTECT_GATES=off` dans l'environnement transforme protect-gates en avertissement visible pour cette session — sauf pour les chemins du harnais, qui restent bloqués. Le ratchet CI n'est jamais désactivé.

**Limite connue, assumée.** Les hooks reconnaissent des écritures de commandes : ils arrêtent les accidents, pas un contournement délibéré. Une écriture depuis un interpréteur (`node -e "fs.appendFileSync(…)"`) atteint une baseline ou forge le marqueur `/create-commit` dans un transcript. Ce qui tient, c'est la protection de branche GitHub, et `main` est protégée avec les admins exemptés, par choix : le token du propriétaire, que Claude utilise aussi, peut donc passer outre. Activer « Do not allow bypassing the above settings » ferme ce trou, au prix d'une PR pour tout changement sur `main`, y compris ceux du propriétaire.

**Brancher le ratchet dans un repo.** Un fichier, ajouté par un humain (protect-gates empêche Claude d'écrire des workflows) :

```yaml
# .github/workflows/baseline-ratchet.yml
name: baseline-ratchet
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]   # poser le label doit relancer le check
permissions:
  contents: read
  pull-requests: write   # pour le commentaire posté quand le label est utilisé
jobs:
  ratchet:
    uses: RemiAsselin42/claude-config/.github/workflows/baseline-ratchet.yml@v1
```

`@v1` est un tag de ce repo. Le job récupère `scripts/baseline-ratchet.js` au même commit : la logique des gates vient toujours de claude-config à une version épinglée, jamais de la branche testée. Un humain accepte un baseline qui grossit en posant le label `baseline-update` sur la PR : le job passe alors et poste les entrées ajoutées en commentaire. Limite : GitHub ne voit que le jeton, un label posé par Claude avec ton jeton est indiscernable d'un label posé par toi — d'où la règle du hook et le commentaire.

**Brancher les gates d'architecture dans un repo.** La logique (le script Python, les versions de grimp et de dependency-cruiser, les flags) vient de ce repo au tag épinglé ; le repo ne garde que ses déclarations, toutes protégées par protect-gates et le ratchet :

- `backend/arch-gates.json` — le paquet racine et ses couches, de la plus basse à la plus haute. Une entrée couvre le module et ses sous-modules, sauf le paquet racine, qui ne couvre que lui-même : un nouveau sous-paquet fait échouer le gate (exit 2) tant qu'il n'est pas classé.

  ```json
  {"package": "app", "layers": [
    {"name": "config", "modules": ["app", "app.config"]},
    {"name": "adapters", "modules": ["app.db", "app.parsers"]},
    {"name": "web", "modules": ["app.routes", "app.main"]}]}
  ```

- `backend/import-cycles-baseline.json`, `backend/import-layers-baseline.json` — la dette gelée, à côté d'`arch-gates.json`.
- `frontend/.dependency-cruiser.cjs` avec `no-circular` et une règle `layer-*` par frontière, `tsPreCompilationDeps: false` ; `frontend/.dependency-cruiser-known-violations.json` comme baseline.

```yaml
# .github/workflows/arch-gates.yml
name: arch-gates
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  arch:
    uses: RemiAsselin42/claude-config/.github/workflows/arch-gates.yml@v2
    with:
      python-config: backend/arch-gates.json   # omettre un côté absent du repo
      frontend-dir: frontend
```

Les lancer en local avant de pousser, depuis la racine du repo :

```bash
gates="$(cat ~/.claude/claude-config.path)/gates/python/check_imports.py"
uv run --no-project --with grimp==3.14 python "$gates" cycles --config backend/arch-gates.json
uv run --no-project --with grimp==3.14 python "$gates" layers --config backend/arch-gates.json
(cd frontend && npx --yes -p dependency-cruiser@17.4.3 -p typescript@5.9.3 depcruise src --config .dependency-cruiser.cjs --ignore-known)
```

**Rendre les checks obligatoires sur `main`.** GitHub → repo → Settings → Branches → ajouter une règle de protection pour `main` → cocher *Require a pull request before merging*, *Require status checks to pass before merging* et *Require branches to be up to date before merging*, puis ajouter chaque check par son nom (un check est proposé dès qu'il a tourné sur au moins une PR). Cocher aussi *Do not allow bypassing the above settings*, sinon un jeton admin — le tien, donc celui de Claude — merge malgré les checks. Les noms sont `<nom du workflow> / <nom du job>` tels que GitHub les liste : les jobs de gate du repo, plus `ratchet / ratchet`, `arch / python` et `arch / frontend` (`<job appelant> / <job appelé>`) une fois les workflows appelants ci-dessus sur `main`.

</details>

---

## Voir aussi

- [README.md](README.md) — English version (primary)
