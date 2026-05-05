---
description: 'Adapte les exemples des prompts au projet actuel en remplaçant les références génériques par des exemples réels du codebase.'
argument-hint: '[nom(s) de prompts spécifiques à adapter, ou vide pour tous les adapter]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Prompts ciblés

"$ARGUMENTS"

## Objectif

Remplacer les exemples génériques ou issus d'autres projets dans les prompts par des exemples réels et pertinents tirés du projet actuel, tout en conservant la structure et la mise en forme exactes.

## Processus

### 1. Inventorier les prompts

Liste tous les prompts à adapter :

```bash
ls .github/prompts/*.prompt.md
```

### 2. Analyser le projet actuel

Collecte les éléments réels du projet :

- Structure : `src/features/*/`, `tests/`, `docs/`
- Features : Noms réels des features
- Fichiers clés : Composants, types, utilities
- Scripts : `package.json` scripts disponibles
- Stack technique : TypeScript, React, Vite, Vitest, etc.
- Conventions : Patterns de nommage observés

### 3. Identifier les exemples à remplacer

Pour chaque prompt, repère :

- ❌ Noms de features génériques ou d'autres projets
- ❌ Chemins de fichiers inexistants dans le projet
- ❌ Commandes npm non disponibles
- ❌ Types/APIs/Tests non utilisés dans le projet
- ❌ Exemples de code avec imports invalides
- ❌ Références à des outils non présents
- ❌ Exemples de processus ou étapes non alignés avec le projet

### 4. Remplacer par des exemples réels

**Pour chaque exemple non pertinent :**

**Avant (exemple générique) :**

```markdown
### src/features/user-service/api.ts (+45, -12)

Ajoute la validation des emails avec regex conforme RFC 5322.
```

**Après (exemple du projet actuel) :**

```markdown
### src/features/asset-loader/loader.ts (+45, -12)

Rajoute la gestion des formats SVG pour permettre l'import de vecteurs.
```

### 5. Préserver la structure

**⚠️ IMPORTANT - Ne modifie PAS :**

- La mise en forme (titres, puces, structure)
- Les instructions et explications générales
- Les sections de processus et principes
- Les emojis et formatage
- Le frontmatter YAML

**✅ Modifie UNIQUEMENT :**

- Les exemples de noms de fichiers
- Les exemples de features
- Les exemples de commandes
- Les exemples de code
- Les références à des composants

### 6. Exemples de remplacement

**Noms de features :**

```diff
- ### Feature "user-authentication"
+ ### Feature "api-connector"
```

**Chemins de fichiers :**

```diff
- `src/api/users/controller.ts`
+ `src/features/main-feature/controller.ts`
```

**Commandes npm :**

```diff
- npm run deploy:prod
+ npm run build
```

**Types et APIs :**

```diff
- interface UserProfile { name: string; }
+ interface DetectionResult { issues: ScanIssue[]; }
```

**Imports et code :**

```diff
- import { validateUser } from './validation';
+ import { detectIssues } from './detection';
```

### 7. Validation

Après remplacement, vérifie :

- ✅ Tous les fichiers mentionnés existent dans le projet
- ✅ Tous les types/interfaces sont définis dans le codebase
- ✅ Toutes les commandes npm sont dans package.json
- ✅ Les features mentionnées sont dans `src/features/`
- ✅ La structure du prompt est identique
- ✅ Les exemples sont cohérents entre eux

### 8. Rapport de mise à jour

Fournis un résumé :

```markdown
## Prompts mis à jour

- create-commit.prompt.md
- evaluer-modifications.prompt.md
- appliquer-suggestions.prompt.md

### Total

✅ 3 prompts mis à jour
✅ 24 exemples adaptés au projet
✅ 0 erreur de structure
```

## Principes

### ✅ À FAIRE

- Utiliser uniquement des éléments existants du projet
- Conserver la cohérence
- Maintenir le niveau de détail identique
- Adapter les noms de variables dans le code exemple
- Vérifier que chaque exemple est réaliste

## Template de remplacement

Pour chaque exemple :

1. **Identifier le pattern** : Quel type d'exemple (feature, fichier, commande, type) ?
2. **Trouver l'équivalent** : Chercher dans le projet actuel
3. **Remplacer précisément** : Garder le même contexte et niveau de détail
4. **Vérifier la cohérence** : L'exemple reste logique ?

## Outils

- `Glob` : Explorer `src/features/`, `tests/`
- `Read` : Lire package.json, types, exemples
- `Grep` : Trouver patterns dans le code
- `Edit` : Remplacer les exemples

Adapte les prompts avec précision pour qu'ils reflètent parfaitement le projet actuel, rendant les exemples immédiatement applicables et pertinents.
