# Harnais qualité déterministe — passation pour Claude Code

> Document de passation rédigé à partir d'une session d'analyse avec Rémi (octobre 2026).
> Il fait autorité sur l'objectif, les principes et le plan. Lis-le en entier avant toute action.
> Commence par le **Lot A** (section 6) et respecte la méthode de travail (section 7).

---

## 1. Objectif

Rémi code avec l'IA depuis 2021. Problème récurrent : le code généré passe les tests mais la dette
technique et le spaghetti augmentent. Claude écrit des tests (souvent des mocks) qui valident son propre
code, et un reviewer LLM se laisse convaincre.

L'objectif n'est **pas la vitesse**. C'est un harnais **strict et déterministe**, configuré une fois dans
`claude-config`, propagé à tous les repos, qui refuse le mauvais code à la place de Rémi. Il ne doit pas
ajouter de complexité qui deviendrait elle-même de la dette.

## 2. Principes non négociables

1. **Ce qui bloque est déterministe, ce qui juge est consultatif.** Aucun LLM dans un chemin bloquant.
   Les reviewers LLM (`/review-*`) tournent *après* les gates, avec leurs rapports en entrée.
2. **L'auteur ne valide pas son propre travail.** Les tests sont figés depuis la spec. Si un agent veut
   modifier un test, c'est un événement visible, pas une ligne silencieuse dans un diff.
3. **Cliquet (baseline).** La dette existante est gelée, seules les *nouvelles* violations bloquent.
   Jamais de seuil absolu le jour 1. Un baseline ne peut que **rétrécir**.
4. **La CI fait autorité, le hook local est un confort.** Un hook se contourne, la CI non.
5. **Le merge est le seul geste humain de la chaîne.** Aucun agent ne merge une PR.
6. **Un gate n'existe que s'il a été vu échouer.** Démonstration rouge → vert obligatoire, sur le
   maillon fragile (pas le cas facile), puis sur la PR réelle en CI.
7. **Toute logique maison est minimale et testée** sur des cas jouets. On ne réimplémente pas ce
   qu'un outil maintenu fait déjà (évaluer les outils existants avant d'écrire du code).
8. **Même sémantique entre gates voisins** (ex. cycles et couches = imports runtime uniquement,
   des deux côtés backend et frontend).

## 3. État de papers-helper (le cobaye)

Stack : FastAPI / Python 3.12 / uv / Ruff + mypy strict / pytest (backend) ; Vite / React 19 / TS /
pnpm / ESLint 9 / Vitest (frontend). CI GitHub Actions `backend.yml` et `frontend.yml`.

### Gate 1 — dépendances circulaires ✅ (PR #5)
- **Frontend** : `dependency-cruiser`, règle `no-circular`, `tsPreCompilationDeps: false` (cycles
  runtime), `tsConfig: tsconfig.app.json`, baseline `.dependency-cruiser-known-violations.json`
  via `--ignore-known`.
- **Backend** : `scripts/check_import_cycles.py` = grimp + Tarjan (composantes fortement connexes)
  + baseline `import-cycles-baseline.json`.
  - `build_app_graph()` : `exclude_type_checking_imports=True`, `cache_dir=None`.
  - `discover_packages()` : découverte dynamique (`os.walk`) des namespace packages (ex. `app/routes/`).
  - Filet `expected_modules()` lu sur disque indépendamment de grimp → exit 2 si un module manque.
  - 10 tests unitaires (dont diamant ≠ cycle, cycle en namespace, cycle uniquement de types).
- Dette gelée : **1 cycle runtime réel** `app.graph ↔ app.graph.builder ↔ app.ingestion`.
  (Le cycle `config ↔ embeddings ↔ ollama_service` n'était qu'un artefact `TYPE_CHECKING`.)

### Gate 2 — architecture en couches ✅ (PR #6)
- **Backend** : `scripts/check_layers.py` réutilise `build_app_graph()`. Interdit uniquement les
  remontées (même couche et descente autorisées). Baseline `import-layers-baseline.json` = `[]`.
  - L0 `config`, `settings` · L1 adaptateurs `ollama_service`, `llm_service`, `embeddings`, `chroma`,
    `parsers.*` · L2 domaine `ingestion`, `graph.*` · L3 `routes.*` · L4 `main`.
  - Module non classé → exit 2. 10 tests + `test_real_app_upward_edges_are_all_baselined`.
- **Frontend** : règles `layer-*` dans dependency-cruiser. L0 `types|constants|prompts` · L1 `utils`
  · L2 `api` · L3 `hooks` · L4 `components` · L5 `App.tsx|main.tsx`. Script renommé `lint:arch`.
  - Dette gelée : 3 remontées `utils → api` (`enrich.ts → categorize.ts, condense.ts`,
    `providerConfig.ts → llm.ts`).
- Hook local : `.claude/hooks/check-cycles.ps1` + `.claude/settings.json` (**gitignorés**, non partagés).

### Gate 3 — mutation testing 🚧 (branche `gate3-mutation-testing`, dernier état connu)
- Outil : **mutmut 3.3.1** (backend Python ; Stryker ne concerne que le JS/TS). Cible : un seul module,
  `app/parsers/_bibtex.py`.
- Construit, non commité : `[tool.mutmut]` dans `pyproject.toml` (`paths_to_mutate`, `also_copy=["app"]`,
  `pytest_add_cli_args_test_selection=["tests/test_parsers.py"]`), `scripts/check_mutation_score.py`
  (lit `mutants/mutmut-cicd-stats.json`, filet 0 mutant → exit 2), tests du wrapper,
  `.github/workflows/mutation.yml`, `mutants/` dans `.gitignore`.
- À faire :
  - gater sur **« le nombre de survivants n'augmente pas »** en plus du score (un score global stable
    peut masquer une régression locale) ;
  - bâtir les fixtures du wrapper sur une **vraie** sortie mutmut capturée ;
  - prouver dans un environnement Linux (sandbox ou CI) : runtime mesuré (bloquant sur PR si < ~2 min,
    sinon job séparé), déterminisme (2 runs, même score), **démo centrale** (un test affaibli qui garde
    la couverture verte mais laisse un mutant survivant → rouge ; restauré → vert) ;
  - jamais de mutation dans le hook local.
- Bloqué en dernier lieu par une panne de l'outil PowerShell côté Windows.

### Gate 4 — prévu
`jscpd` (duplication, cross-langage) + passage en erreur des règles de complexité (Ruff `C901`,
ESLint `complexity`), en mode cliquet.

## 4. Audit de claude-config (commit `4e2e126`, 18/09/2026)

### Ce qui est solide (à préserver)
- Distribution : `install.sh` + sync `upstream`, miroir de `commands/` (purge des fichiers retirés),
  `CLAUDE.md` de projet regénéré sans écraser la partie perso (testé par `tests/claude-md-refresh.sh`).
- Couche contexte : MemPalace, Graphify, vault Obsidian, `context/`, SessionStart sobre (~200 tokens).
- Commandes `/review-*` en `context: fork` ; `/create-pr` impose une `main` protégée.

### Problèmes constatés
1. **Permissions trop larges** (`settings.json`) : `defaultMode: "auto"` + allow `gh pr merge *`,
   `git push origin *`, `git rebase *`. Claude peut merger ses propres PR (contredit le principe 5).
   Rien n'empêche la modification d'une config de gate ou d'un baseline.
2. **Hooks bloquants non versionnés** : les 5 hooks du repo ne font que de la plomberie
   (context-mode, rtk, mempalace, session-stop). Tout ce qui bloque vient de
   `yes | npx --yes cc-safe-setup` (`install.sh` ~l.1031), **sans version épinglée** (v30.0.7 au
   03/10/2026, un seul mainteneur), qui installe 8 hooks sans relecture : `destructive-guard`,
   `branch-guard`, `syntax-check`, `context-monitor`, `comment-strip`, `cd-git-allow`, `secret-guard`,
   `api-error-alert`. Le harnais effectif n'est ni dans le repo ni reproductible.
3. **Aucun gate de qualité dans claude-config.** `/review-quality` mesure la couverture + jugement LLM.
   Les Gates 1-2 n'existent que dans papers-helper, avec un hook local gitignoré.
4. **`CLAUDE.md` global = uniquement de l'outillage**, aucune règle d'ingénierie (section 2).
5. **README désynchronisé** :
   - 11 agents listés alors que `agents/` a été supprimé (commit `3eb0605`) ;
   - `templates/context/` référencé (README + `/init-context`) mais absent ;
   - sync `upstream` « automatique toutes les 8h via PreToolUse » annoncée, mais aucun hook de ce
     type dans `settings.json` (la sync ne tourne qu'au lancement d'`install.sh`).
6. **Pas de CI sur claude-config** : `install.sh` (1 566 lignes, opérations destructives) n'est couvert
   que par 2 tests shell + un pre-commit shellcheck local.

### Idées reprises d'ECC (affaan-m/ECC, MIT) — l'idée, pas le framework
- `config-protection` : bloquer la modification des configs de lint. Testé : ECC bloque
  `eslint.config.js` et `ruff.toml` mais **laisse passer** `pyproject.toml`, `.dependency-cruiser.cjs`
  et les baselines JSON. À étendre.
- Bloquer `git commit --no-verify`.
- Ne PAS installer ECC (293 skills, 68 agents, 0 gate déterministe, philosophie couverture + LLM).

## 5. Contraintes d'environnement (machine de Rémi)
- Windows, **pas de droits admin** (donc pas de WSL pour l'instant). PowerShell 7 la plupart du temps,
  Git Bash sinon. L'outil PowerShell de Claude Code a déjà eu des pannes durables.
- `gh` inutilisable localement ; les PR passent par l'API GitHub avec le credential manager.
- Node.js est un prérequis d'`install.sh` → **langage recommandé pour les hooks partagés : Node**
  (multi-plateforme, évite le doublon `.ps1` / `.sh`).

## 6. Plan de travail pour claude-config (un lot à la fois)

### Lot A — fermer les portes de sortie (priorité 1)
1. `settings.json` : `gh pr merge` en `deny` (ou `ask`). Proposer à Rémi la liste exacte des autres
   permissions à resserrer avant de les changer.
2. `cc-safe-setup` : épingler une version précise **ou** copier dans le repo les hooks réellement
   voulus (proposer la liste à Rémi, avec ce que fait chacun).
3. Hook `PreToolUse` (Node) **protect-gates** : bloque toute modification par Claude
   - des configs de gate (`.dependency-cruiser.cjs`, `eslint.config.*`, `ruff.toml`, sections
     `[tool.ruff]`, `[tool.mypy]`, `[tool.mutmut]` de `pyproject.toml`, workflows `.github/workflows/*`) ;
   - des baselines (`*-baseline.json`, `.dependency-cruiser-known-violations.json`, plancher mutation) ;
   - des commandes `--update-baseline`, `lint:arch:baseline`, `git commit --no-verify`.
   `pyproject.toml` : ne bloquer que les modifications des sections de config d'outil, pas les
   dépendances.
4. Workflow CI réutilisable **baseline-ratchet** : compare chaque baseline à la branche de base ;
   échoue si des entrées sont **ajoutées**, sauf label explicite posé par Rémi (ex. `baseline-update`).
- **Preuves attendues** : rouge → vert pour chaque cas (édition bloquée, commande bloquée, edit légitime
  de dépendance dans `pyproject.toml` autorisé, baseline qui rétrécit = vert, qui grossit = rouge,
  qui grossit avec label = vert), tests unitaires du hook et du script de ratchet.

### Lot B — règles d'ingénierie dans le `CLAUDE.md` global
Ajouter une section courte reprenant la section 2 : ne jamais modifier un test/baseline/config pour
faire passer un check, ne jamais affaiblir une assertion, prouver rouge → vert, s'arrêter après une
unité de travail, ne jamais merger. Pas de duplication avec l'outillage existant.

### Lot C — extraire les gates de papers-helper vers claude-config
- Modèles : config dependency-cruiser (cycles + couches), scripts `check_import_cycles.py` /
  `check_layers.py` génériques (couches déclarées dans un fichier de config par projet).
- Workflow GitHub réutilisable appelé en une ligne par chaque repo.
- Commande `/init-gates` (calquée sur `/init-context`) : installe, **propose** les couches à Rémi,
  attend son accord, génère les baselines.
- Pilote : remplacer les copies locales de papers-helper par la version partagée sans changer le
  comportement (Gates 1-2 doivent rester verts, mêmes baselines), puis un 2ᵉ repo.
- **Contrainte fixée au Lot A** : la CI charge la logique des gates depuis claude-config à une
  version **épinglée** (tag `@v1` ; le workflow réutilisable récupère ses scripts à son propre
  `job.workflow_sha`), jamais depuis la branche de la PR testée. Tant que `scripts/check_*.py` et
  le script `lint:arch` de `package.json` vivent dans les repos, le hook `protect-gates` ne les
  protège pas : c'est ce lot qui les en sort.

### Lot D — hygiène du harnais
README resynchronisé (agents, `templates/context/`, sync upstream : soit réimplémenter le hook, soit
corriger la doc — demander à Rémi), petit test qui vérifie que les tableaux du README correspondent aux
dossiers réels, CI minimale sur claude-config (shellcheck + tests, Linux + macOS).

### Lot E — plus tard
Commande `/feature` orchestrée (plan → review du plan par un autre modèle → code → gates → review
adversariale du diff → retour à Rémi). Seulement quand les lots A à D sont en place.

## 7. Méthode de travail (obligatoire)
1. **Un lot à la fois.** Tu le prouves, tu t'arrêtes, tu attends le feu vert explicite de Rémi.
2. **Proposer avant d'imposer** toute décision d'architecture ou de politique (couches, permissions,
   hooks gardés). Rémi tranche.
3. Explique chaque ligne de config en français.
4. Ne dis jamais « fait » sans la démonstration rouge → vert, sur le cas fragile.
5. Ne touche à rien hors du lot en cours. `git status` propre, aucun résidu de démo.
6. Branche dédiée + PR ; démonstration rouge → vert sur la CI de la PR ; **tu ne merges pas**.
7. Vérifie l'existant avant d'écrire du code maison (outil maintenu ? option native ?).
