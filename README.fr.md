# claude-config

Configuration partagée pour Claude Code : agents spécialisés, slash-commands, scripts, mémoire persistante (MemPalace) et optimisation de tokens (RTK). Un seul clone, une installation partout, synchronisation automatique.

> [!WARNING]
> **Les scripts de ce dépôt modifient l'environnement système de la machine qui les exécute.**
>
> `install.sh` et les scripts utilitaires effectuent des opérations destructives et persistantes :
>
> - **Écritures** dans `~/.claude/` (agents, commandes, hooks, scripts, settings, CLAUDE.md)
> - **Installation de paquets** globaux (`graphify`, `mempalace`, `rtk`)
> - **Modification du PATH** : ajoute `~/.local/bin` dans `~/.bashrc`, `~/.bash_profile` et `~/.profile`, après confirmation sauf en mode `-y`
> - **Suppression de fichiers** (`graphify-out/`, wings mempalace, dossiers vault) via `exclude-from-index.sh`
> - **Écriture de hooks et de config git** dans les repos cibles (post-commit sync vault, gate `pre-commit` shellcheck dans ce repo, `merge.ours.driver` / `pull.rebase false`)
> - **Commits et push git** automatiques sur le vault
>
> Lire `install.sh` avant exécution. Ne pas utiliser sur une machine dont la config `~/.claude/` est déjà gérée par un autre workflow.

---

## Modèle public / privé

Ce repo est la **base partagée**. Il contient tout ce qui est utile à n'importe qui : agents, commandes, scripts, templates de settings. Il ne contient **aucune donnée personnelle** (pas de vault, pas de secrets).

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

---

## Ce que fait `install.sh`

1. Synchronise depuis `upstream` **en premier** si le remote existe (les repos privés récupèrent automatiquement la dernière config partagée) ; si la sync apporte des changements, le script se relance automatiquement pour que la suite s'exécute avec la version à jour
2. Vérifie **Node.js**, installe **uv** si absent, puis installe/met à jour **Graphify**, **MemPalace**, **chromadb**, **RTK**, **jq**, **shellcheck** et **context-mode** (plus le serveur MCP Zilliz si `MILVUS_ADDRESS` est défini)
3. Demande une seule confirmation si `~/.local/bin` doit être ajouté au PATH persistant (`-y` accepte automatiquement)
4. Copie les **agents**, **commandes**, **scripts** et **templates** vers `~/.claude/` — `agents/` et `commands/` sont en miroir : les fichiers déployés retirés du repo sont purgés
5. Enregistre l'emplacement du repo dans `~/.claude/claude-config.path` et génère **`session-stop.sh`** (hook Stop : `graphify update` + mining du repo dans son wing MemPalace + sync vault) ; les hooks résolvent le repo via ce pointeur plutôt que par chemin absolu en dur
6. Initialise **MemPalace** : création du palace, choix du modèle d'embedding, vérification de l'index. Les repos ne sont _pas_ minés ici — chacun l'est dans son propre wing à l'étape 15
7. Copie **CLAUDE.md** vers `~/.claude/CLAUDE.md` (substitution `${VAULT_DIR}`)
8. Génère **`claude.json`** depuis le template (substitution `FIGMA_API_KEY`)
9. Copie **`settings.json`**
10. Active **RTK** via `setup-rtk.sh`
11. Exécute **CC Safe Setup** pour installer les hooks de sécurité de façon non-destructive
12. Installe les **plugins épinglés** via le CLI `claude` (`ponytail`, `caveman` upstream)
13. Restaure le **caveman mode** depuis `defaults/` si absent sur la machine (sauté si le plugin caveman upstream est installé — il injecte ses propres instructions)
14. Met à jour `.gitignore` dans les repos cibles (bloc graphify + `CLAUDE.md` + `mempalace.yaml` + `context/`) via `templates/gitignore.append`
15. Sélection interactive des repos git frères à indexer. Par repo : hooks + graphe graphify, **nommage LLM des communautés**, sync vault (rapport + arbre de fichiers + canvas + une note par nœud), génération de `mempalace.yaml` et mining dans le wing du repo
16. Applique le même pipeline au repo de config lui-même (graphe rafraîchi de force, pas de gestion du `.gitignore`)
17. Installe un **gate pre-commit shellcheck** dans le repo de config — les `*.sh` stagés doivent passer `shellcheck -S warning`
18. Commit le vault et le réconcilie avec `origin` (fetch → merge → push, réessayé en cas de course) via `scripts/vault-sync.sh`

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

Ensuite, `scripts/sync-upstream.sh` tire les fichiers partagés depuis `upstream` dans le repo privé sans toucher aux fichiers personnels (`vault/`, `env.local`, `.claude/`) :

**Automatique** — une fois toutes les 8h via le hook `PreToolUse` (debounce par timestamp).  
**Forcé** — systématiquement au début de chaque `install.sh`.

### Vault Obsidian

Le repo public ne contient pas de `vault/` — `install.sh` le crée dans le repo privé et y écrit, pour chaque repo indexé, `Projets/<repo>/` avec le rapport de graphe, l'arbre de fichiers, une carte `<repo>.canvas` des communautés et une note par nœud du graphe. Pour le lire : Obsidian → _Ouvrir un dossier comme coffre_ → sélectionner `<votre-repo>/vault`.

`scripts/vault-sync.sh` le commit et le réconcilie avec `origin` (fetch → merge → push) à la fin de chaque install et de chaque session, pour que plusieurs machines puissent écrire dans le même vault.

### Options

Rien de ce qui suit n'est obligatoire — les valeurs par défaut suffisent.

| Où          | Option                                               | Effet                                                                                          |
| ----------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| CLI         | `install.sh -y`                                      | Non-interactif : conserve l'état d'indexation de chaque repo, accepte le changement de PATH    |
| CLI         | `install.sh -v`                                      | Sorties détaillées de l'installeur                                                             |
| Prompt      | PATH                                                 | Demandé une fois, pour ajouter `~/.local/bin` à `~/.bashrc` / `~/.bash_profile` / `~/.profile` |
| Prompt      | Sélection des repos                                  | Quels repos git frères indexer (graphify + MemPalace + vault)                                  |
| `env.local` | `FIGMA_API_KEY`                                      | Active le serveur MCP Figma                                                                    |
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
├── claude.json.template         # Config MCP (Figma, etc.) avec placeholder
├── settings.json                # Permissions, hooks, niveau d'effort, serveurs MCP
├── mempalace.yaml               # Wing MemPalace de ce repo + exclusions de mining
├── .graphifyignore              # Exclut vault/ (généré) du graphe de ce repo
│
├── agents/                      # Agents spécialisés → ~/.claude/agents/
├── commands/                    # Slash-commands → ~/.claude/commands/
├── defaults/                    # Valeurs par défaut restaurées sur nouvelle machine
│   ├── caveman.enabled          # Présence = caveman activé par défaut
│   └── caveman.level            # Niveau d'intensité par défaut
├── scripts/                     # Scripts utilitaires → ~/.claude/scripts/
│   ├── repo-identity.sh         # Lib partagée : canonical_repo_name()
│   ├── caveman-toggle.sh        # Toggle caveman mode
│   ├── setup-rtk.sh             # Installe RTK
│   ├── sync-upstream.sh         # Sync des fichiers partagés depuis le remote upstream
│   ├── sync-graph-to-vault.sh   # Sync graphify → vault Obsidian
│   ├── vault-sync.sh            # Commit + fetch/merge/push du vault (multi-machine)
│   └── exclude-from-index.sh    # Exclure un repo de graphify + mempalace
└── templates/
    ├── CLAUDE.project.md        # Template CLAUDE.md de départ pour les nouveaux repos
    ├── gitignore.append         # Entrées .gitignore ajoutées par install.sh
    └── context/                 # Templates de contexte par repo (copiés par /init-context)
        ├── architecture.md
        ├── patterns.md
        └── constraints.md
```

---

<details>
<summary><strong>Agents</strong></summary>

| Agent                         | Rôle                                        |
| ----------------------------- | ------------------------------------------- |
| `architect-reviewer`          | Revue d'architecture système                |
| `backend-developer`           | APIs et services backend                    |
| `code-reviewer`               | Qualité de code et sécurité                 |
| `documentation-engineer`      | Documentation technique                     |
| `frontend-developer`          | Applications frontend (React, Vue, Angular) |
| `javascript-pro`              | JavaScript avancé / Node.js                 |
| `payment-integration`         | Systèmes de paiement et conformité PCI      |
| `react-performance-optimizer` | Performances React et Core Web Vitals       |
| `security-auditor`            | Audits de sécurité et conformité            |
| `typescript-pro`              | Patterns TypeScript avancés                 |
| `ui-designer`                 | Design systems et composants UI             |

</details>

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
<summary><strong>Caveman mode</strong></summary>

Mode de réponse minimaliste persistant entre sessions. Contrôlé via `/caveman` ou directement :

```bash
bash ~/.claude/scripts/caveman-toggle.sh [on|off|toggle|inject|status] [niveau]
```

| Niveau         | Description                                                                       |
| -------------- | --------------------------------------------------------------------------------- |
| `lite`         | Supprime le remplissage et les formules de politesse, garde la grammaire complète |
| `full`         | Réponses terse, fragments acceptés (défaut)                                       |
| `ultra`        | Compression maximale, abréviations, flèches pour la causalité                     |
| `wenyan-lite`  | Registre semi-classique, ton littéraire                                           |
| `wenyan-full`  | Mode 文言文, terseness classique maximale                                         |
| `wenyan-ultra` | Compression extrême, style lettre classique                                       |

L'état et le niveau sont persistés dans `~/.claude/caveman.enabled` et `~/.claude/caveman.level`. Sur une nouvelle machine, `install.sh` restaure ces valeurs depuis `defaults/`.

Quand le [plugin caveman upstream](https://github.com/JuliusBrussee/caveman) est installé (épinglé via `install.sh`), il injecte ses propres instructions de compression et ajoute `/caveman-compress`, `/caveman-stats`, `/caveman-commit`, `/caveman-review`. Le bloc local est alors retiré pour éviter la duplication — `caveman-toggle.sh` reste en fallback quand le plugin est absent.

</details>

---

<details>
<summary><strong>Plugins épinglés</strong></summary>

`install.sh` installe les mêmes plugins Claude Code sur chaque machine via le CLI `claude` (liste : tableau `PINNED_PLUGINS` dans `install.sh`) :

| Plugin     | Source                                                                | Rôle                                                                                                       |
| ---------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | Échelle de décision YAGNI — moins de code généré (réutilisation → stdlib → dépendance existante → minimum) |
| `caveman`  | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | Plugin de compression upstream — remplace le bloc local du CLAUDE.md, ajoute les commandes stats/compress  |

Si le CLI `claude` n'est pas dans le PATH, l'étape est sautée avec un avertissement ; installation manuelle : `claude plugin marketplace add <repo> && claude plugin install <nom>@<marketplace>`.

</details>

---

<details>
<summary><strong>Hooks</strong></summary>

Configurés dans `settings.json` :

| Hook          | Déclencheur          | Action                                                                                                 |
| ------------- | -------------------- | ------------------------------------------------------------------------------------------------------ |
| `PreToolUse`  | Chaque appel d'outil | `sync-upstream.sh` — sync depuis upstream (debounce 8h, repos privés uniquement) + hook `context-mode` |
| `PostToolUse` | Chaque appel d'outil | Hook `context-mode`                                                                                    |
| `Stop`        | Fin de session       | Sauvegarde MemPalace + hook `context-mode` + `session-stop.sh` (graphify update + sync vault)          |
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

Via MCP (dans Claude Code) : `mempalace_search` et `mempalace_add_drawer`.

</details>

---

<details>
<summary><strong>Zilliz — Recherche sémantique (optionnel)</strong></summary>

Quand `MILVUS_ADDRESS` est défini dans `env.local`, Claude utilise la recherche vectorielle sémantique **avant** grep pour les requêtes de type "où est géré X" sur les grands repos. Graphify assure la navigation structurelle ; Zilliz apporte la pertinence sémantique.

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

Les templates sont dans `templates/context/`. Claude lit ces fichiers automatiquement en début de session si le dossier `context/` existe (via la règle Per-Repo Context dans `CLAUDE.md`).

</details>

---

## Voir aussi

- [README.md](README.md) — English version (primary)
