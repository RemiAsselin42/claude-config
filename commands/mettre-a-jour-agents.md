---
description: 'Met à jour le fichier AGENTS.md avec les directives critiques du projet.'
argument-hint: '[standards ou conventions spécifiques à ajouter, ou vide pour une mise à jour complète]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Directives spécifiques

"$ARGUMENTS"

## Objectif

Maintenir un fichier AGENTS.md **concis** (<200 lignes) avec uniquement les directives CRITIQUES pour travailler efficacement sur le projet.

## Principes du AGENTS.md

### Ce qui DOIT y être

**Seulement les éléments critiques non-découvrables rapidement :**

- Standards de code spécifiques au projet (non-standard)
- Conventions de nommage particulières
- Commandes essentielles et leurs usages
- Structure de projet si non-évidente
- Pièges à éviter absolument
- Format de réponse exigé pour certaines tâches
- Dépendances critiques et leur rôle

### Ce qui NE DOIT PAS y être

- Longues explications découvrables par analyse du code
- Documentation exhaustive (→ README.md)
- Historique du projet
- Tutoriels détaillés
- Informations redondantes avec autres docs
- Standards génériques (TypeScript, React standard)

## Structure recommandée

```markdown
# Guide Agent - [Nom du Projet]

> Guide de référence rapide (<200 lignes). Pour la documentation complète : README.md

## Architecture

- **Stack** : [Technologies principales]
- **Structure** : [Organisation spécifique si non-évidente]
- **Pattern principal** : [Ex: Feature-based, Registry pattern]

## Standards critiques

### Nommage

- Sections : `kebab-case` (hero, face-vader, thematic-objects)
- Composants : `camelCase` (glbModel, scrollManager)
- Controllers : `camelCase` suffixé `Controller` (modelRotationController)
- Tests : `*.test.ts` co-localisés

### Types

- Strictement typé, zéro `any`
- Types partagés : `src/sections/types.ts`
- Types core : `src/core/*.ts`

### Imports

- Absolus autorisés avec alias `@/`
- Ordre : Three.js → libs → local
- Barrel exports dans `index.ts` si nécessaire

## Commandes essentielles

\`\`\`bash
npm run dev # Dev avec HMR
npm test # Vitest watch mode
npm run test:ci # Tests CI (coverage)
npm run build # Build production
npm run lint # ESLint + fix
...
\`\`\`

## Tests

- **Couverture minimale** : 80%
- **Co-location** : `*.test.ts` à côté du fichier testé
- **Mocks Three.js** : Utiliser `vitest` pour mocker les imports
- **Convention** : `describe()` → nom de fonction/classe, `it()` → comportement

## Ajout d'une section

1. Créer `src/sections/XX-nom-section/`
2. Fichiers requis : `index.ts` ou `nom.ts`, `README.md`
3. Enregistrer dans `src/sections/registry.ts`
4. Ajouter tests dans `src/sections/*.test.ts`
5. Documenter dans section README

## Pièges à éviter

- ❌ Oublier de disposer des objets Three.js (memory leaks)
- ❌ Opérations lourdes dans la boucle de rendu
- ❌ console.log en production (utiliser telemetry `core/telemetry.ts`)
- ❌ Imports circulaires (surtout dans `registry.ts`)

## Outils internes

- **Telemetry** : `src/core/telemetry.ts` - Analytics et logging
- **Types communs** : `src/sections/types.ts` - SectionContext, SectionLifecycle
- **Asset Loader** : `src/core/assetLoader.ts` - Chargement des modèles 3D
- **Scroll Manager** : `src/core/scrollManager.ts` - Gestion du scroll

## Format de réponse

Lors de modifications de code :

1. Lire contexte avec `Read`
2. Utiliser `Edit` pour les modifications
3. Utiliser `Bash` pour lancer lint et tests
4. Résumer changements brièvement

## Références

- Architecture détaillée : `/docs/architecture.md` (si existe)
- Contribution : `/docs/CONTRIBUTING.md` (si existe)
- Three.js : Documentation officielle
```

## Processus de mise à jour

### 1. Analyser l'état actuel

Lis le AGENTS.md existant :

- Compte les lignes (doit être <200)
- Repère les problématiques auxquelles les agents font face actuellement et qui pourraient être résolues par une mise à jour du guide
- Identifie sections obsolètes
- Repère informations manquantes critiques

### 2. Scanner le projet

Identifie les éléments critiques actuels :

```bash
# Structure du projet
rtk ls src/

# Scripts disponibles
cat package.json | grep scripts

# Conventions de nommage actuelles
find src/ -type f -name "*.ts" -o -name "*.tsx"

# Tests patterns
find tests/ -type f -name "*.test.ts"
```

### 3. Identifier les changements critiques

Vérifie si ces éléments ont changé :

- Nouvelles commandes npm importantes
- Nouveaux standards de code adoptés
- Changements d'architecture significatifs
- Nouveaux pièges découverts
- Outils internes ajoutés/modifiés

### 4. Mettre à jour de manière minimale

**Ajoute seulement si :**

- Non-découvrable rapidement par l'agent
- Critique pour éviter erreurs graves
- Spécifique au projet (pas générique)
- Change fréquemment le workflow

**Supprime si :**

- Devenu obsolète
- Redondant avec autre documentation
- Trop détaillé (déplacer vers README)
- Générique (standards universels)

### 5. Vérifier la concision

Après modification :

- Compte les lignes : **<200 lignes**
- Vérifie densité : chaque ligne apporte valeur
- Élimine verbosité : phrases courtes, puces
- Élimine les éléments textuels inutiles comme les emojis ou la mise en forme excessive
- Structure claire : sections bien délimitées

### 6. Rapport de mise à jour

```markdown
## AGENTS.md mis à jour

### Changements appliqués

✅ Ajouté section "Nouveaux hooks disponibles"
✅ Mis à jour commandes npm (ajout test:watch)
✅ Supprimé section obsolète "Configuration Webpack"
✅ Condensé section "Standards TypeScript" (15→8 lignes)

### Métriques

- **Lignes** : 187/200 ✅
- **Sections** : 9
- **Densité** : Optimale

### Validation

✅ Toutes les commandes testées et valides
✅ Standards correspondent au code actuel
✅ Aucune redondance avec README.md
✅ Guide utilisable immédiatement
```

## Template minimaliste

Si création from scratch, utilise cette structure ultra-concise :

```markdown
# Guide Agent - [Project]

## Stack

[Liste technologies]

## Standards

- Nommage : [Convention spécifique]
- Types : [Règles strictes du projet]
- Tests : [Couverture requise]

## Commandes

\`\`\`bash
[3-5 commandes essentielles max]
\`\`\`

## Pièges

- ❌ [Erreur critique à éviter 1]
- ❌ [Erreur critique à éviter 2]

## Ajout feature

1. [Étape 1]
2. [Étape 2]
3. [Étape 3]

## Outils internes

- [Outil critique 1] : [Usage en 1 ligne]
```

## Règles d'or

1. **<200 lignes impératif**
2. **Référence rapide, pas tutoriel**
3. **Critique only, pas nice-to-know**
4. **Phrases courtes, puces préférées**
5. **Mise à jour si changement majeur uniquement**

Maintiens un AGENTS.md laser-focused qui permet à un agent de démarrer efficacement en 2 minutes de lecture.
