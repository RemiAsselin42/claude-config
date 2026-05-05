# claude-config

Configuration centralisée pour Claude Code : agents, commandes, scripts, vault Obsidian et mémoire persistante. Un seul dépôt à déployer sur chaque machine pour retrouver instantanément le même environnement.

> [!WARNING]
> **Les scripts de ce dépôt modifient l'environnement système de la machine qui les exécute.**
>
> `install.sh` et les scripts utilitaires effectuent des opérations destructives et persistantes :
> - **Écritures** dans `~/.claude/` (agents, commandes, hooks, scripts, settings, CLAUDE.md)
> - **Installation de paquets** globaux (`graphify`, `mempalace`, `rtk`)
> - **Modification du PATH** : `install.sh` peut ajouter `~/.local/bin` dans `~/.bashrc`, `~/.bash_profile` et `~/.profile`, après confirmation sauf en mode `-y`
> - **Suppression de fichiers** (`graphify-out/`, wings mempalace, dossiers vault) via `exclude-from-index.sh`
> - **Commits et push git** automatiques sur le vault
>
> Lire `install.sh` avant exécution. Ne pas utiliser sur une machine dont la config `~/.claude/` est déjà gérée par un autre workflow.

## Prérequis

- [Node.js](https://nodejs.org)
- `curl` pour l'installation automatique de [uv](https://astral.sh/uv) si absent

## Installation

```bash
# 1. Copier le fichier de variables machine-specific
cp env.local.template env.local
# Remplir FIGMA_API_KEY dans env.local

# 2. Lancer l'installation
bash install.sh

# Mode non-interactif (conserve l'état actuel de chaque repo)
bash install.sh -y

# Debug : affiche les sorties détaillées des installateurs
bash install.sh -v
```

L'installeur effectue, dans l'ordre :

1. Préparation des dépendances : vérifie **Node.js**, installe **uv** si absent, puis installe/vérifie **Graphify**, **MemPalace**, **chromadb** dans le Python courant, et **RTK**
2. Demande une seule confirmation si `~/.local/bin` doit être ajouté au PATH persistant (`~/.bashrc`, `~/.bash_profile`, `~/.profile`) ; `-y` accepte automatiquement
3. Copie des **agents**, **commandes** et **scripts** vers `~/.claude/`
4. Génération de **`session-stop.sh`** avec le chemin absolu du repo (hook Stop)
5. Initialisation de **MemPalace** avec reconstruction de l'index depuis les transcripts Claude
6. Copie de **CLAUDE.md** global vers `~/.claude/CLAUDE.md`
7. Restauration du **caveman mode** depuis `defaults/` si absent sur la machine, puis injection dans `CLAUDE.md`
8. Génération de **`claude.json`** depuis le template (substitution `FIGMA_API_KEY`)
9. Copie de **`settings.json`**
10. Activation de **RTK** (`setup-rtk.sh`) — après CLAUDE.md et settings.json car `rtk init -g` peut les modifier
11. Sélection interactive des repos git frères à indexer (graphify + mempalace + vault)
12. Commit et push automatique du vault si des graphes ont été générés

## Structure

```
claude-config/
├── install.sh              # Script d'installation principal
├── env.local.template      # Variables machine-specific (FIGMA_API_KEY, etc.)
├── CLAUDE.md               # Instructions globales pour Claude Code
├── claude.json.template    # Config MCP (Figma, etc.) avec placeholder
├── settings.json           # Permissions, hooks, niveau d'effort, serveurs MCP
│
├── agents/                 # Agents spécialisés (~/.claude/agents/)
├── commands/               # Slash-commands (~/.claude/commands/)
├── defaults/               # Valeurs par défaut restaurées sur nouvelle machine
│   ├── caveman.enabled     # Présence = caveman activé par défaut
│   └── caveman.level       # Niveau d'intensité par défaut (ex: full)
├── hooks/                  # Hooks PreToolUse/Stop (~/.claude/hooks/)
│   └── rtk-hook.sh         # Wrapper RTK : détecte l'absence de RTK/jq et propose l'installation
├── scripts/                # Scripts utilitaires (~/.claude/scripts/)
│   ├── repo-identity.sh         # Lib partagée : canonical_repo_name() + helpers PATH TOOL_BIN_DIR
│   ├── caveman-toggle.sh        # Toggle caveman mode avec niveaux d'intensité
│   ├── setup-rtk.sh             # Installe RTK (Windows: winget + wrapper bash ; Linux/macOS: brew/curl)
│   ├── sync-graph-to-vault.sh   # Sync graphify → vault Obsidian
│   └── exclude-from-index.sh   # Exclure un repo de graphify + mempalace
├── templates/
│   └── CLAUDE.project.md   # Template CLAUDE.md pour les repos sans config
└── vault/                  # Vault Obsidian versionné
    ├── Projets/            # Graphes Graphify par repo
    ├── Décisions/          # Décisions techniques importantes
    └── Patterns/           # Patterns récurrents et bonnes pratiques
```

## Scripts utilitaires

### `scripts/sync-graph-to-vault.sh`

Copie les artefacts Graphify du repo courant vers le vault Obsidian. Appelé automatiquement après chaque `graphify update` (hook post-commit) et à la fin de `install.sh`.

Artefacts copiés vers `vault/Projets/<repo-name>/`, où `<repo-name>` vient du remote Git `origin` quand il existe, puis du nom de dossier local en fallback :
- `<repo-name> - GRAPH_REPORT.md` — rapport d'analyse du graphe
- `<repo-name> - FILE_TREE.md` — arborescence du projet
- `<repo-name>.canvas` — canvas Obsidian (si Python disponible)

```bash
# Depuis la racine d'un repo graphifié
bash ~/.claude/scripts/sync-graph-to-vault.sh
```

### `scripts/exclude-from-index.sh`

Exclut un ou plusieurs repos de l'indexation graphify + mempalace + vault.

```bash
# Interactif
bash ~/.claude/scripts/exclude-from-index.sh /chemin/vers/repo

# Non-interactif (supprime graphify-out/ et le vault sans confirmation)
bash ~/.claude/scripts/exclude-from-index.sh --yes /chemin/vers/repo
```

Actions réalisées :
1. Désinstalle les hooks graphify
2. Crée un `.graphifyignore` à la racine du repo
3. Supprime `graphify-out/` (avec confirmation sauf `--yes`)
4. Supprime le wing mempalace via chromadb (fallback `uv run --with chromadb` si chromadb absent du Python courant)
5. Supprime le dossier vault Obsidian nommé d'après le remote `origin` (avec confirmation sauf `--yes`)
6. Supprime l'éventuel dossier vault legacy (nom de dossier local) si différent du nom canonique (avec confirmation sauf `--yes`)

## Caveman Mode

Mode de réponse minimaliste persistant entre sessions. Contrôlé via `/caveman` ou directement :

```bash
bash ~/.claude/scripts/caveman-toggle.sh [on|off|toggle|inject|status] [niveau]
```

Niveaux disponibles :

| Niveau | Description |
|---|---|
| `lite` | Supprime le remplissage et les formules de politesse, garde la grammaire complète |
| `full` | Réponses terse, fragments acceptés (défaut) |
| `ultra` | Compression maximale, abréviations, flèches pour la causalité |
| `wenyan-lite` | Registre semi-classique, ton littéraire |
| `wenyan-full` | Mode 文言文, terseness classique maximale |
| `wenyan-ultra` | Compression extrême, style lettre classique |

Le bloc caveman est injecté en tête de `~/.claude/CLAUDE.md` entre les marqueurs `<!-- caveman:start -->` et `<!-- caveman:end -->`. L'état et le niveau sont persistés dans `~/.claude/caveman.enabled` et `~/.claude/caveman.level`. Sur une nouvelle machine, `install.sh` restaure ces fichiers depuis `defaults/`.

```bash
/caveman              # Toggle on/off (conserve le niveau courant)
/caveman on ultra     # Active avec niveau ultra
/caveman off          # Désactive
/caveman status       # Affiche l'état courant sans modifier
```

## Hooks automatiques

Configurés dans `settings.json` :

| Hook | Déclencheur | Action |
|---|---|---|
| `PreToolUse` | Bash | `rtk-hook.sh` — réécrit les commandes via RTK pour économiser des tokens ; propose l'installation si RTK/jq absent |
| `Stop` | Fin de session | Sauvegarde MemPalace + `session-stop.sh` (graphify update + sync vault) |
| `PreCompact` | Avant compaction | Sauvegarde MemPalace |

RTK est installé automatiquement par `install.sh`. Pour l'installer manuellement :

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

Sur **Windows**, le script installe RTK via `winget` et crée un wrapper bash `~/.local/bin/rtk` (le PATH Windows n'étant pas rafraîchi dans la session bash de Claude Code). Dans le flux `install.sh`, la modification persistante du PATH est centralisée au début de l'installation. Lancé manuellement, `setup-rtk.sh` demande confirmation avant d'ajouter `~/.local/bin` au PATH.

Sur **Linux/macOS**, RTK est installé via `brew` ou le script d'installation officiel, puis configuré avec `rtk init -g`.

## Graphify

Graphify génère un graphe de connaissances du codebase. Chaque repo indexé dispose de :
- `graphify-out/GRAPH_REPORT.md` — rapport local (gitignored)
- `vault/Projets/<repo>/` — copie versionnée dans le vault, nommée d'après le repo Git distant `origin` quand disponible

Les fichiers suivants sont ignorés par git (générés localement) :

```
graphify-out/
```

Commandes utiles :

```bash
graphify update .           # Mettre à jour le graphe (AST uniquement, sans coût API)
graphify query "question"   # Requête sémantique sur le graphe
graphify path "A" "B"       # Chemin entre deux concepts
graphify explain "concept"  # Explication d'un concept du codebase
```

## MemPalace

Mémoire persistante cross-sessions. Les données sont dans `~/.mempalace/` (non versionné).

```bash
# Recherche
mempalace search "sujet" --wing nom-du-repo   # Scoped au repo
mempalace search "sujet"                      # Recherche globale

# Reconstruire l'index sur une nouvelle machine
mempalace init ~/.mempalace
mempalace mine ~/.claude/projects/ --mode convos
```

Via MCP (dans Claude Code) : outil `mempalace_search` et `mempalace_add_drawer`.

## Agents disponibles

| Agent | Rôle |
|---|---|
| `architect-reviewer` | Revue d'architecture |
| `backend-developer` | Développement backend |
| `code-reviewer` | Revue de code |
| `documentation-engineer` | Documentation technique |
| `frontend-developer` | Développement frontend |
| `javascript-pro` | Expertise JavaScript |
| `payment-integration` | Intégration paiement |
| `react-performance-optimizer` | Optimisation React |
| `security-auditor` | Audit de sécurité |
| `typescript-pro` | Expertise TypeScript |
| `ui-designer` | Design UI |

## Commandes (slash-commands)

| Commande | Description |
|---|---|
| `/appliquer-suggestions` | Applique les recommandations identifiées |
| `/caveman [on\|off] [niveau]` | Active/désactive le mode caveman avec niveau d'intensité optionnel |
| `/create-commit` | Crée un commit git |
| `/evaluer-codebase` | Évalue un dépôt fraîchement cloné |
| `/evaluer-commentaires` | Analyse la qualité des commentaires |
| `/evaluer-documentation` | Vérifie cohérence doc/code |
| `/evaluer-modifications` | Analyse les modifications depuis le dernier commit |
| `/evaluer-qualite` | Évalue la qualité du code |
| `/evaluer-stack` | Audit de la pile technologique |
| `/expliquer-modifications` | Explique les modifications récentes |
| `/mettre-a-jour-agents` | Met à jour AGENTS.md |
| `/mettre-a-jour-documentation` | Met à jour la documentation |
| `/mettre-a-jour-prompts` | Adapte les exemples des prompts au projet |
| `/trouver-code-mort` | Trouve le code mort dans le projet |

## Vault Obsidian

Le vault est dans `vault/` et versionné dans ce repo. Pointer Obsidian directement sur ce dossier.

Structure :
- `Projets/` — Graphes Graphify + arborescences par repo
- `Décisions/` — Décisions techniques importantes (pourquoi, pas quoi)
- `Patterns/` — Patterns récurrents et bonnes pratiques identifiées

Le vault est mis à jour automatiquement après chaque session Claude Code et après chaque `install.sh`.

## Nouvelle machine

```bash
git clone <repo-url> ~/Documents/_Dev/claude-config
cd ~/Documents/_Dev/claude-config
cp env.local.template env.local
# Éditer env.local avec les valeurs de la machine
bash install.sh
```
