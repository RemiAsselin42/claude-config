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

1. Vérifie **Node.js**, installe **uv** si absent, puis installe/met à jour **Graphify**, **MemPalace**, **chromadb** et **RTK**
2. Synchronise depuis `upstream` si le remote existe (les repos privés récupèrent automatiquement la dernière config partagée)
3. Demande une seule confirmation si `~/.local/bin` doit être ajouté au PATH persistant (`-y` accepte automatiquement)
4. Copie les **agents**, **commandes** et **scripts** vers `~/.claude/`
5. Génère **`session-stop.sh`** avec le chemin absolu du repo (hook Stop)
6. Initialise **MemPalace** avec reconstruction de l'index depuis les transcripts Claude
7. Copie **CLAUDE.md** vers `~/.claude/CLAUDE.md`
8. Restaure le **caveman mode** depuis `defaults/` si absent sur la machine
9. Génère **`claude.json`** depuis le template (substitution `FIGMA_API_KEY`)
10. Copie **`settings.json`**
11. Active **RTK** via `setup-rtk.sh`
12. Sélection interactive des repos git frères à indexer (graphify + mempalace + vault)
13. Commit et push automatique du vault si des graphes ont été générés

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
├── hooks/                       # Hooks PreToolUse/Stop → ~/.claude/hooks/
├── scripts/                     # Scripts utilitaires → ~/.claude/scripts/
│   ├── repo-identity.sh         # Lib partagée : canonical_repo_name()
│   ├── caveman-toggle.sh        # Toggle caveman mode
│   ├── setup-rtk.sh             # Installe RTK
│   ├── sync-upstream.sh         # Sync des fichiers partagés depuis le remote upstream
│   ├── sync-graph-to-vault.sh   # Sync graphify → vault Obsidian
│   └── exclude-from-index.sh    # Exclure un repo de graphify + mempalace
└── templates/
    └── CLAUDE.project.md        # Template CLAUDE.md pour les repos sans config
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

---

## Hooks

Configurés dans `settings.json` :

| Hook | Déclencheur | Action |
|---|---|---|
| `PreToolUse` | Chaque appel d'outil | `sync-upstream.sh` — sync depuis upstream (debounce 8h) |
| `Stop` | Fin de session | Sauvegarde MemPalace + `session-stop.sh` (graphify update + sync vault) |
| `PreCompact` | Avant compaction | Sauvegarde MemPalace |

---

## RTK — Proxy de tokens

RTK réécrit les commandes dev courantes (ex: `git status` → `rtk git status`) pour réduire la consommation de tokens de 60–90%. Le hook `PreToolUse` applique cela de façon transparente.

Installation manuelle :

```bash
bash ~/.claude/scripts/setup-rtk.sh
```

**Windows** — installé via `winget`, avec un wrapper bash dans `~/.local/bin/rtk`.  
**Linux/macOS** — installé via `brew` ou le script officiel, puis `rtk init -g`.

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

## Voir aussi

- [README.md](README.md) — English version (primary)
