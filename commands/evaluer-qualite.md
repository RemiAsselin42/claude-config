---
description: 'Évalue la qualité du code : conventions, modularité, architecture, tests et typage.'
argument-hint: '[répertoire ou fichier spécifique, ou vide pour analyser tout le projet]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(wc:*), Bash(npm run test:coverage:*), Bash(npm run lint:*), Bash(npx tsc:*), Bash(npx eslint:*)
context: fork
agent: agent
---

## Périmètre d'analyse

"$ARGUMENTS"

## Objectif

Produire une analyse ciblée sur la **qualité intrinsèque du code** : conventions, modularité, architecture, couverture de tests et typage. Cette analyse exclut volontairement les aspects fonctionnels (ce que fait le code), les performances et la sécurité.

## Processus

### 0. Orientation initiale

```bash
# Structure du projet (3 niveaux max)
find . -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/dist/*' -not -path '*/build/*' | sort

# Fichiers de configuration de qualité présents
find . -maxdepth 2 -name ".eslintrc*" -o -name ".prettierrc*" -o -name "biome.json" -o -name "tsconfig*.json" -o -name ".editorconfig" -o -name "jest.config*" -o -name "vitest.config*" | grep -v node_modules
```

Lis également `package.json` (ou `pyproject.toml`, `Cargo.toml`, etc.) pour identifier les scripts de lint et de test disponibles.

Si `$ARGUMENTS` est fourni, restreins l'analyse à ce chemin.

---

### 1. Pattern architectural

**a. Identification du pattern**

```bash
find . -maxdepth 2 -type d -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' | sort
```

Patterns courants à détecter :

| Pattern                         | Indices structurels                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------ |
| **MVC**                         | dossiers `models/`, `views/`, `controllers/`                                               |
| **Hexagonale / Ports-Adapters** | dossiers `domain/`, `application/`, `infrastructure/`, `ports/`, `adapters/`               |
| **Feature-based**               | dossiers par fonctionnalité (`users/`, `orders/`, `auth/`) chacun avec ses propres modules |
| **Layered**                     | dossiers `services/`, `repositories/`, `entities/`, `dtos/`                                |
| **Microservices**               | plusieurs `package.json` ou plusieurs services dans un monorepo                            |
| **Monolithique non structuré**  | tout dans `src/` avec peu de sous-dossiers                                                 |

**b. Évaluation de la pertinence du pattern**

Évalue si le pattern choisi est adapté :

- **Taille du projet** : un pattern hexagonal complexe pour 500 lignes est sur-architecturé
- **Cohérence** : le pattern est-il appliqué uniformément ? (pas de mélange MVC + hexagonal)
- **Couplage** : les couches respectent-elles les règles de dépendances du pattern ?
- **Scalabilité** : le pattern permet-il une évolution saine ?

```bash
# Détecter des violations de couches (imports relatifs remontants)
grep -rn "from '\.\.\/" src/ --include="*.ts" 2>/dev/null | grep -v node_modules | head -30
```

---

### 2. Conventions de nommage

**a. Linter et formateur**

Vérifie si un linter/formateur est configuré et tente de l'exécuter :

```bash
rtk lint | head -50
```

**b. Conventions par type de symbole**

Pour chaque langage présent, vérifie la cohérence des conventions :

| Symbole                           | Convention attendue                                     |
| --------------------------------- | ------------------------------------------------------- |
| Classes, Interfaces, Types, Enums | `PascalCase`                                            |
| Fonctions, méthodes, variables    | `camelCase`                                             |
| Constantes globales               | `SCREAMING_SNAKE_CASE`                                  |
| Fichiers source                   | cohérence interne (kebab-case ou camelCase)             |
| Fichiers de test                  | suffixe `.test.ts` / `.spec.ts` ou dossier `__tests__/` |

```bash
# Détecter des noms d'une seule lettre (hors itérateurs i, j, k)
grep -rn "\bconst [b-hln-z]\b\|\blet [b-hln-z]\b" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -20

# Détecter des types/interfaces en minuscule
grep -rn "^interface [a-z]\|^type [a-z]" src/ --include="*.ts" 2>/dev/null | head -20
```

**c. Incohérences à relever**

- Mélange de styles dans le même projet (ex: `getUserData` et `get_user_data`)
- Noms trop vagues sans contexte : `data`, `info`, `tmp`, `temp`, `obj`, `result`
- Abréviations non standard : `usr`, `cfg`, `mgr`, `svc`

---

### 3. Taille et modularité des fichiers

**a. Fichiers trop volumineux (> 500 lignes)**

```bash
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) \
  -exec wc -l {} \; 2>/dev/null | sort -rn | head -30
```

Pour chaque fichier > 500 lignes :

1. Lis le fichier avec `Read`
2. Identifie les responsabilités multiples
3. Propose un découpage modulaire concret (nouveaux fichiers suggérés avec leurs responsabilités)

**b. Densité de responsabilités**

```bash
# Compter les exports par fichier
grep -rn "^export " src/ --include="*.ts" 2>/dev/null | cut -d: -f1 | sort | uniq -c | sort -rn | head -20
```

Signaux d'alerte :

- Fichier avec > 5 exports distincts (classes/fonctions/types)
- Fichier avec > 10 fonctions
- Fichier qui importe de > 10 modules différents

---

### 4. Couverture et qualité des tests

**a. Détection de l'outillage de test**

```bash
cat package.json 2>/dev/null | grep -E '"jest"|"vitest"|"mocha"|"jasmine"|"cypress"|"playwright"'
```

**b. Exécution de la couverture**

Tente les commandes suivantes dans l'ordre jusqu'à succès :

```bash
rtk npm run test:coverage | tail -30
rtk npm run coverage | tail -30
rtk jest --coverage --passWithNoTests | tail -30
rtk vitest run --coverage | tail -30
```

**c. Analyse structurelle des tests**

```bash
# Ratio fichiers de test vs fichiers source
echo "Fichiers de test :" && find . -not -path '*/node_modules/*' \( -name "*.test.ts" -o -name "*.spec.ts" -o -name "*.test.js" -o -name "*.spec.js" \) | wc -l
echo "Fichiers source :" && find src/ -not -path '*/node_modules/*' \( -name "*.ts" -o -name "*.js" \) | grep -v "\.test\.\|\.spec\.\|\.d\.ts" | wc -l

# Tests skippés
grep -rn "\.skip\|xit\b\|xdescribe\b\|it\.skip\|test\.skip" . --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules | head -20
```

**d. Qualité des assertions**

```bash
# Assertions trop génériques
grep -rn "toBeTruthy\(\)\|toBeFalsy\(\)\|toBeDefined\(\)" . --include="*.test.ts" --include="*.spec.ts" 2>/dev/null | head -20
```

---

### 5. Qualité du typage

#### Pour TypeScript

**a. Configuration stricte**

```bash
cat tsconfig.json 2>/dev/null
```

Vérifie : `"strict": true`, `"noImplicitAny": true`, `"strictNullChecks": true`, `"noUnusedLocals": true`, `"noUnusedParameters": true`.

**b. Comptage des anti-patterns de typage**

```bash
echo "=== :any ===" && grep -rn ": any\b\|<any>" src/ --include="*.ts" 2>/dev/null | grep -v "\.d\.ts" | wc -l
echo "=== @ts-ignore ===" && grep -rn "@ts-ignore" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== @ts-nocheck ===" && grep -rn "@ts-nocheck" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== as unknown as ===" && grep -rn "as unknown as" src/ --include="*.ts" 2>/dev/null | wc -l
echo "=== Object/Function types ===" && grep -rn ": Object\b\|: Function\b" src/ --include="*.ts" 2>/dev/null | wc -l
```

```bash
# Erreurs de compilation
rtk tsc --noEmit | tail -20
```

#### Pour d'autres langages typés

- **Python** : vérifie l'usage de `mypy`/`pyright`, présence d'annotations de type
- **Go** : vérifie les `interface{}` excessifs
- **Rust** : vérifie les `unwrap()` excessifs

---

### 6. Duplication de code

**a. Signatures de fonctions répétées**

```bash
grep -rn "function " src/ --include="*.ts" --include="*.js" 2>/dev/null | sed 's/.*function //' | sed 's/(.*//' | sort | uniq -d | head -20
```

**b. Constantes dupliquées**

```bash
grep -rn "= '" src/ --include="*.ts" 2>/dev/null | sed "s/.*= '//" | sed "s/'.*//" | sort | uniq -dc | sort -rn | head -20
```

Lors de la lecture des fichiers, note manuellement :

- Même logique de validation répétée à plusieurs endroits
- Même transformation de données dupliquée
- Imports identiques répétés partout (candidats à un barrel `index.ts`)

---

### 7. Lisibilité générale

**a. Imbrication excessive**

```bash
# 4+ niveaux d'indentation = signal de complexité élevée
grep -rn "^        if \|^        for \|^        while " src/ --include="*.ts" --include="*.js" 2>/dev/null | head -20
```

**b. Magic numbers et strings**

```bash
# Nombres magiques (hors 0, 1, -1, 2)
grep -rn "[^a-zA-Z0-9_][3-9][0-9]\+[^a-zA-Z0-9_]" src/ --include="*.ts" 2>/dev/null | grep -v "test\|spec" | head -20

# URLs et chemins hardcodés
grep -rn '"http\|"https\|"\/api\/' src/ --include="*.ts" 2>/dev/null | grep -v "test\|spec" | head -20
```

Lors de la lecture des fichiers, identifie les fonctions > 50 lignes et évalue si elles peuvent être décomposées.

---

## Format du rapport

```markdown
# Rapport de qualité du code

## Tableau de bord

| Dimension              | Score     | Principaux problèmes |
| ---------------------- | --------- | -------------------- |
| Architecture           | ⭐⭐⭐⭐☆ | [résumé]             |
| Conventions de nommage | ⭐⭐⭐⭐☆ | [résumé]             |
| Modularité             | ⭐⭐⭐☆☆  | [résumé]             |
| Couverture de tests    | ⭐⭐☆☆☆   | [résumé]             |
| Qualité du typage      | ⭐⭐⭐☆☆  | [résumé]             |
| Duplication            | ⭐⭐⭐⭐☆ | [résumé]             |
| Lisibilité             | ⭐⭐⭐☆☆  | [résumé]             |

**Score global** : XX/35

---

## 1. Architecture

**Pattern détecté** : [Ex: Feature-based]
**Adapté au projet** : [Oui / Partiellement / Non]

[Description du pattern observé, cohérence, violations éventuelles]

---

## 2. Conventions de nommage

**Linter configuré** : [Oui/Non — outil détecté]

### Incohérences détectées

- [Description] — `fichier.ts:ligne`

---

## 3. Modularité

### Fichiers > 500 lignes

| Fichier                       | Lignes | Responsabilités          | Découpage suggéré                                  |
| ----------------------------- | ------ | ------------------------ | -------------------------------------------------- |
| `src/services/UserService.ts` | 742    | Auth + CRUD + validation | Extraire `UserValidator.ts`, `UserEmailService.ts` |

---

## 4. Tests

**Framework** : [Jest / Vitest / Pytest / etc.]
**Couverture globale** : [X% ou N/A]
**Ratio fichiers testés** : X / Y fichiers source

### Fichiers sans tests

- `src/services/PaymentService.ts` — logique critique non couverte

### Qualité des assertions

[Observation sur la qualité globale]

---

## 5. Qualité du typage

| Anti-pattern    | Occurrences | Sévérité |
| --------------- | ----------- | -------- |
| `: any`         | 12          | 🟡       |
| `@ts-ignore`    | 3           | 🟡       |
| `@ts-nocheck`   | 1           | 🔴       |
| `as unknown as` | 2           | 🔴       |

**tsconfig strict** : [Activé / Désactivé / Partiel]
**Erreurs de compilation** : [0 / N erreurs]

### Occurrences critiques

- `src/api/handler.ts:45` — `as unknown as User` : cast dangereux sans validation

---

## 6. Duplication

### Blocs dupliqués

- **[Description]** : logique répétée dans `fichier-a.ts:12` et `fichier-b.ts:87`
  - Suggestion : extraire dans `src/shared/[nom].ts`

---

## 7. Lisibilité

### Fonctions trop longues (> 50 lignes)

| Fonction       | Fichier                    | Lignes | Suggestion                                      |
| -------------- | -------------------------- | ------ | ----------------------------------------------- |
| `processOrder` | `src/orders/service.ts:34` | 87     | Extraire `validateOrder()` + `applyDiscounts()` |

### Magic numbers/strings

- `src/config.ts:23` — `3600` sans constante nommée → `SESSION_DURATION_SECONDS`

---

## Problèmes par sévérité

### 🔴 Critiques (bloquent la maintenabilité)

1. **[Problème]**
   - **Où** : `fichier.ts:ligne`
   - **Impact** : [Conséquence sur la maintenabilité]
   - **Correction** : [Action concrète]

### 🟡 Modérés (dette technique significative)

1. **[Problème]**
   - **Où** : `fichier.ts:ligne`
   - **Correction** : [Action concrète]

### 🟢 Mineurs (améliorations cosmétiques)

1. **[Problème]** — `fichier:ligne` — [Correction rapide]

---

## Plan d'action

### Priorité haute

- [ ] [Action concrète] — `fichier.ts`

### Priorité moyenne

- [ ] [Action concrète]

### Priorité basse

- [ ] [Action concrète]

---

## Métriques

| Métrique                 | Valeur |
| ------------------------ | ------ |
| Fichiers source analysés | N      |
| Fichiers > 500 lignes    | N      |
| Fichiers avec tests      | N / M  |
| Couverture de tests      | X%     |
| Occurrences de `any`     | N      |
| Erreurs TypeScript       | N      |
```
