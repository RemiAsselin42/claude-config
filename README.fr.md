# claude-config

Configuration partagée pour Claude Code : agents spécialisés, slash-commands, scripts, mémoire persistante (MemPalace) et optimisation de tokens (RTK). Un seul clone, une installation partout, synchronisation automatique.

> [!WARNING]
> **Les scripts de ce dépôt modifient l'environnement système de la machine qui les exécute.**
>
> `install.sh` et les scripts utilitaires effectuent des opérations destructives et persistantes :
> - **Écritures** dans `~/.claude/` (agents, commandes, hooks, scripts, settings, CLAUDE.md)
> - **Installation de paquets** globaux (`graphify`, `mempalace`, `rtk`)
> - **Modification du PATH** : ajoute `~/.local/bin` dans `~/.bashrc`, `~/.bash_profile` et `~/.profile`, après confirmation sauf en mode `-y`
> - **Suppression de fichiers** (`graphify-out/`, wings mempalace, dossiers vault) via `exclude-from-index.sh`
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

Le repo privé se synchronise automatiquement avec celui-ci — voir [Sync upstream](#sync-upstream).

---

## Prérequis

- [Node.js](https://nodejs.org)
- `curl` pour l'installation automatique de [uv](https://astral.sh/uv) si absent

---

## Démarrage rapide

```bash
git clone https://github.com/RemiAsselin42/claude-config
cd claude-config
cp env.local.template env.local
# Remplir env.local avec les valeurs de la machine
bash install.sh
```

### Mode non-interactif (conserve l'état actuel de chaque repo)

```bash
bash install.sh -y
```

### Debug (affiche les sorties détaillées)

```bash
bash install.sh -v
```

---

## Ce que fait `install.sh`

1. Synchronise depuis `upstream` **en premier** si le remote existe (les repos privés récupèrent automatiquement la dernière config partagée) ; si la sync apporte des changements, le script se relance automatiquement pour que la suite s'exécute avec la version à jour
2. Vérifie **Node.js**, installe **uv** si absent, puis installe/met à jour **Graphify**, **MemPalace**, **chromadb**, **RTK** et **context-mode**
3. Demande une seule confirmation si `~/.local/bin` doit être ajouté au PATH persistant (`-y` accepte automatiquement)
4. Copie les **agents**, **commandes**, **scripts** et **templates** vers `~/.claude/`
5. Génère **`session-stop.sh`** avec le chemin absolu du repo (hook Stop)
6. Exécute **CC Safe Setup** pour installer les hooks de sécurité de façon non-destructive
7. Initialise **MemPalace** avec reconstruction de l'index depuis les transcripts Claude
8. Copie **CLAUDE.md** vers `~/.claude/CLAUDE.md`
9. Installe les **plugins épinglés** via le CLI `claude` (`ponytail`, `caveman` upstream)
10. Restaure le **caveman mode** depuis `defaults/` si absent sur la machine (sauté si le plugin caveman upstream est installé — il injecte ses propres instructions)
11. Génère **`claude.json`** depuis le template (substitution `FIGMA_API_KEY`)
12. Copie **`settings.json`**
13. Active **RTK** via `setup-rtk.sh`
14. Met à jour `.gitignore` dans les repos cibles (bloc graphify + `CLAUDE.md` + `mempalace.yaml` + `context/`) via `templates/gitignore.append`
15. Sélection interactive des repos git frères à indexer (graphify + mempalace + vault)
16. Commit et push automatique du vault si des graphes ont été générés

---

## Structure

```
claude-config/
├── install.sh                   # Script d'installation principal
├── env.local.template           # Variables machine-specific (FIGMA_API_KEY, etc.)
├── CLAUDE.md                    # Instructions globales pour Claude Code
├── claude.json.template         # Config MCP (Figma, etc.) avec placeholder
├── settings.json                # Permissions, hooks, niveau d'effort, serveurs MCP
│
├── agents/                      # Agents spécialisés → ~/.claude/agents/
├── commands/                    # Slash-commands → ~/.claude/commands/
├── defaults/                    # Valeurs par défaut restaurées sur nouvelle machine
│   ├── caveman.enabled          # Présence = caveman activé par défaut
│   └── caveman.level            # Niveau d'intensité par défaut
├── hooks/                       # Scripts de hook → ~/.claude/hooks/ (actuellement vide)
├── scripts/                     # Scripts utilitaires → ~/.claude/scripts/
│   ├── repo-identity.sh         # Lib partagée : canonical_repo_name()
│   ├── caveman-toggle.sh        # Toggle caveman mode
│   ├── setup-rtk.sh             # Installe RTK
│   ├── sync-upstream.sh         # Sync des fichiers partagés depuis le remote upstream
│   ├── sync-graph-to-vault.sh   # Sync graphify → vault Obsidian
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

## Sync upstream

`scripts/sync-upstream.sh` tire les fichiers partagés depuis le remote `upstream` dans le repo privé, sans toucher aux fichiers personnels (`vault/`, `env.local`, `.claude/`).

**Automatique** — s'exécute une fois toutes les 8h via le hook `PreToolUse` (debounce par timestamp).  
**Forcé** — s'exécute systématiquement au début de chaque `install.sh`.

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

Ensuite, `install.sh` et le hook `PreToolUse` maintiennent le repo privé synchronisé avec celui-ci.

---

## Agents

| Agent | Rôle |
|---|---|
| `architect-reviewer` | Revue d'architecture système |
| `backend-developer` | APIs et services backend |
| `code-reviewer` | Qualité de code et sécurité |
| `documentation-engineer` | Documentation technique |
| `frontend-developer` | Applications frontend (React, Vue, Angular) |
| `javascript-pro` | JavaScript avancé / Node.js |
| `payment-integration` | Systèmes de paiement et conformité PCI |
| `react-performance-optimizer` | Performances React et Core Web Vitals |
| `security-auditor` | Audits de sécurité et conformité |
| `typescript-pro` | Patterns TypeScript avancés |
| `ui-designer` | Design systems et composants UI |

---

## Slash-commands

| Commande | Description |
|---|---|
| `/appliquer-suggestions` | Applique les recommandations identifiées |
| `/caveman [on\|off] [niveau]` | Active/désactive le mode caveman avec niveau optionnel |
| `/create-commit` | Crée un commit git |
| `/evaluer-codebase` | Évalue un dépôt fraîchement cloné |
| `/evaluer-commentaires` | Analyse la qualité des commentaires |
| `/evaluer-documentation` | Vérifie cohérence doc/code |
| `/evaluer-modifications` | Analyse les modifications depuis le dernier commit |
| `/evaluer-qualite` | Évalue la qualité du code |
| `/evaluer-stack` | Audit de la pile technologique |
| `/expliquer-modifications` | Explique les modifications récentes |
| `/init-context` | Génère `context/architecture.md`, `patterns.md`, `constraints.md` depuis le codebase |
| `/mettre-a-jour-agents` | Met à jour AGENTS.md |
| `/mettre-a-jour-documentation` | Met à jour la documentation |
| `/mettre-a-jour-prompts` | Adapte les exemples des prompts au projet courant |
| `/trouver-code-mort` | Trouve le code mort dans le projet |

---

## Caveman mode

Mode de réponse minimaliste persistant entre sessions. Contrôlé via `/caveman` ou directement :

```bash
bash ~/.claude/scripts/caveman-toggle.sh [on|off|toggle|inject|status] [niveau]
```

| Niveau | Description |
|---|---|
| `lite` | Supprime le remplissage et les formules de politesse, garde la grammaire complète |
| `full` | Réponses terse, fragments acceptés (défaut) |
| `ultra` | Compression maximale, abréviations, flèches pour la causalité |
| `wenyan-lite` | Registre semi-classique, ton littéraire |
| `wenyan-full` | Mode 文言文, terseness classique maximale |
| `wenyan-ultra` | Compression extrême, style lettre classique |

L'état et le niveau sont persistés dans `~/.claude/caveman.enabled` et `~/.claude/caveman.level`. Sur une nouvelle machine, `install.sh` restaure ces valeurs depuis `defaults/`.

Quand le [plugin caveman upstream](https://github.com/JuliusBrussee/caveman) est installé (épinglé via `install.sh`), il injecte ses propres instructions de compression et ajoute `/caveman-compress`, `/caveman-stats`, `/caveman-commit`, `/caveman-review`. Le bloc local est alors retiré pour éviter la duplication — `caveman-toggle.sh` reste en fallback quand le plugin est absent.

---

## Plugins épinglés

`install.sh` installe les mêmes plugins Claude Code sur chaque machine via le CLI `claude` (liste : tableau `PINNED_PLUGINS` dans `install.sh`) :

| Plugin | Source | Rôle |
|---|---|---|
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | Échelle de décision YAGNI — moins de code généré (réutilisation → stdlib → dépendance existante → minimum) |
| `caveman` | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | Plugin de compression upstream — remplace le bloc local du CLAUDE.md, ajoute les commandes stats/compress |

Si le CLI `claude` n'est pas dans le PATH, l'étape est sautée avec un avertissement ; installation manuelle : `claude plugin marketplace add <repo> && claude plugin install <nom>@<marketplace>`.

---

## Hooks

Configurés dans `settings.json` :

| Hook | Déclencheur | Action |
|---|---|---|
| `PreToolUse` | Chaque appel d'outil | `sync-upstream.sh` — sync depuis upstream (debounce 8h, repos privés uniquement) + hook `context-mode` |
| `PostToolUse` | Chaque appel d'outil | Hook `context-mode` |
| `Stop` | Fin de session | Sauvegarde MemPalace + hook `context-mode` + `session-stop.sh` (graphify update + sync vault) |
| `PreCompact` | Avant compaction | Sauvegarde MemPalace + hook `context-mode` |

---

## RTK — Proxy de tokens

RTK réécrit les commandes dev courantes (ex: `git status` → `rtk git status`) pour réduire la consommation de tokens de 60–90%.

**Windows** — installé via `winget`, activé avec `rtk init -g --claude-md` : RTK fonctionne via les instructions CLAUDE.md (Claude préfixe les commandes lui-même, sans hook bash).  
**Linux/macOS** — installé via `brew` ou le script officiel, activé avec `rtk init -g` : RTK installe un hook `PreToolUse` dans `settings.json` qui réécrit les commandes de façon transparente.

Installation manuelle :

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

---

## Graphify

Génère un graphe de connaissances de chaque codebase indexé.

```bash
graphify update .            # Mettre à jour le graphe (AST uniquement, sans coût API)
graphify query "question"    # Requête sémantique
graphify path "A" "B"        # Chemin entre deux concepts
graphify explain "concept"   # Explication d'un concept du codebase
```

Chaque repo indexé dispose de :
- `graphify-out/GRAPH_REPORT.md` — rapport local (gitignored)
- `vault/Projets/<repo>/` — copie versionnée dans le vault Obsidian (repos privés uniquement)

---

## MemPalace

Mémoire persistante cross-sessions. Les données sont dans `~/.mempalace/` (jamais versionné).

```bash
mempalace search "sujet" --wing nom-du-repo   # Scoped au repo
mempalace search "sujet"                      # Recherche globale

# Reconstruire l'index sur une nouvelle machine
mempalace init ~/.mempalace
mempalace mine ~/.claude/projects/ --mode convos
```

Via MCP (dans Claude Code) : `mempalace_search` et `mempalace_add_drawer`.

---

## Zilliz — Recherche sémantique (optionnel)

Quand `MILVUS_ADDRESS` est défini dans `env.local`, Claude utilise la recherche vectorielle sémantique **avant** grep pour les requêtes de type "où est géré X" sur les grands repos. Graphify assure la navigation structurelle ; Zilliz apporte la pertinence sémantique.

Configuration dans `env.local` (voir `env.local.template`) :

```bash
export MILVUS_ADDRESS="https://xxx.api.gcp-us-west1.zillizcloud.com"
export MILVUS_TOKEN="your-zilliz-api-key"
export OPENAI_API_KEY="sk-..."   # utilisé pour les embeddings
```

`install.sh` installe automatiquement le serveur MCP `@zilliz/claude-context-mcp` quand `MILVUS_ADDRESS` est défini. Sinon, cette étape est silencieusement ignorée.

---

## Contexte par repo

Exécuter `/init-context` dans n'importe quel repo pour générer des fichiers de contexte structurés depuis le codebase réel :

- `context/architecture.md` — décisions majeures et leur justification
- `context/patterns.md` — patterns de code récurrents
- `context/constraints.md` — contraintes de performance, sécurité et compatibilité

Les templates sont dans `templates/context/`. Claude lit ces fichiers automatiquement en début de session si le dossier `context/` existe (via la règle Per-Repo Context dans `CLAUDE.md`).

---

## Voir aussi

- [README.md](README.md) — English version (primary)
