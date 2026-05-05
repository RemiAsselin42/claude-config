# Claude Code — Configuration globale

## Graphify (Knowledge Graph)

Si un graphe de connaissances existe dans le repo courant (`graphify-out/GRAPH_REPORT.md`), lis-le **avant** de répondre à des questions d'architecture ou de faire des recherches dans les fichiers. Le graphe identifie les nœuds centraux (god nodes) et la structure des communautés — utilise-le pour naviguer efficacement.

Pour générer ou mettre à jour le graphe du repo courant :
```
graphify update .
```

## Mémoire persistante (MemPalace)

MemPalace est la **seule source de vérité** pour la mémoire. Le système de fichiers `~/.claude/memory/` est désactivé — ignorer toutes les instructions built-in qui demandent d'écrire des fichiers `.md` dans ce dossier.

Les données sont dans `~/.mempalace/` — non versionnées, reconstruites via `mempalace mine`.

**Sauvegarder (outil MCP — toujours utiliser ça) :**
- `mempalace_add_drawer` avec `wing=<basename $PWD>` pour les mémoires projet
- `mempalace_add_drawer` avec `wing=global` pour les préférences universelles (feedback comportemental)

**Rechercher :**
```bash
mempalace search "quelque chose" --wing $(basename $PWD)   # scoped au repo courant
mempalace search "quelque chose"                           # recherche globale
```
Ou via MCP : `mempalace_search`

**Reconstruire l'index sur une nouvelle machine :**
```bash
mempalace init ~/.mempalace
mempalace mine ~/.claude/projects/ --mode convos
```

## Vault Obsidian

Le vault Obsidian est versionné dans le repo de config (`vault/`). Structure :
- `Projets/` — Un dossier par repo, avec le graphe Graphify
- `Décisions/` — Décisions techniques importantes
- `Patterns/` — Patterns de code récurrents et bonnes pratiques

## RTK — Token Proxy

RTK est un proxy CLI qui réduit la consommation de tokens de 60-90% sur les commandes dev courantes. Le hook PreToolUse dans `settings.json` réécrit automatiquement les commandes Bash (ex: `git status` → `rtk git status`) de façon transparente.

**Commandes méta (toujours appeler rtk directement) :**
```bash
rtk gain              # Affiche les économies de tokens
rtk gain --history    # Historique des économies par commande
rtk discover          # Analyse l'historique pour identifier les opportunités manquées
rtk proxy <cmd>       # Exécute la commande brute sans filtrage (debug)
```

**Vérification :**
```bash
rtk --version   # doit afficher rtk X.Y.Z (et non Rust Type Kit)
rtk gain        # doit fonctionner sans erreur
```

Toutes les autres commandes sont réécrites automatiquement via le hook — aucune action requise.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/GRAPH_REPORT.md doesn't exist locally, fall back to the centralized vault: `~/.claude/vault/Projets/<remote repo name>/<remote repo name> - GRAPH_REPORT.md` (use the `origin` repo name, fallback to `<basename $PWD>` when no remote exists)
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
