---
description: 'Audit de la pile technologique : langages, dépendances, versions, APIs, outils et synergie.'
argument-hint: '[aspect spécifique à analyser, ou vide pour un audit complet]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(cat:*), Bash(npm outdated:*), Bash(npm audit:*), Bash(npm ls:*)
context: fork
agent: agent
---

## Périmètre d'analyse

"$ARGUMENTS"

## Objectif

Produire un audit complet de la pile technologique du projet : pertinence des langages, qualité et état des dépendances, cohérence avec la documentation, intégrations externes, outils de build et synergie globale. Cette analyse ne porte pas sur la logique métier, mais sur les choix technologiques eux-mêmes.

## Processus

### 0. Orientation initiale

```bash
# Fichiers de manifeste de dépendances présents
find . -maxdepth 2 -not -path '*/node_modules/*' \
  \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" \
     -o -name "go.mod" -o -name "pom.xml" -o -name "build.gradle" \
     -o -name "requirements*.txt" -o -name "Gemfile" \) | sort

# Version de runtime
node --version 2>/dev/null
python --version 2>/dev/null
go version 2>/dev/null
```

Lis `package.json` (ou l'équivalent) pour obtenir la liste complète des dépendances avant de continuer.

Si `$ARGUMENTS` est fourni, concentre l'analyse sur cet aspect ou ce sous-système.

---

### 1. Langages utilisés

**a. Détection et proportion**

```bash
# Compter les fichiers par extension (hors node_modules, dist, build)
find . -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/.git/*' -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20
```

**b. Valeur ajoutée du langage**

Évalue si le langage choisi apporte une valeur réelle dans le contexte du projet :

| Situation                                                        | Signal             | Recommandation                 |
| ---------------------------------------------------------------- | ------------------ | ------------------------------ |
| Fichiers `.js` et `.ts` coexistent sans raison                   | Mélange incohérent | Migrer vers TypeScript complet |
| TypeScript présent mais `strict: false` et `any` partout         | TS sous-exploité   | Activer strict progressivement |
| Python sans annotations de type sur un projet > 500 lignes       | Typage manquant    | Ajouter mypy / pyright         |
| Shell scripts complexes qui pourraient être du TypeScript/Python | Mauvais outil      | Considérer une réécriture      |

```bash
# Détecter les fichiers .js à côté de .ts (mélange)
find src/ -name "*.js" -not -name "*.config.js" -not -name "*.test.js" 2>/dev/null | head -20
```

**c. Version du runtime**

Vérifie la version déclarée dans `.nvmrc`, `engines` du `package.json`, `.python-version`, etc. :

```bash
cat .nvmrc 2>/dev/null
cat .node-version 2>/dev/null
```

- Node.js LTS actuel : v20 / v22 (2025). Versions < 18 = EOL.
- Python LTS actuel : 3.11+. Versions < 3.9 = fin de support.

---

### 2. Dépendances directes — pertinence et redondance

**a. Liste complète**

```bash
# Dépendances npm (production + dev)
cat package.json 2>/dev/null | grep -A200 '"dependencies"'
```

**b. Dépendances inutilisées**

Pour chaque dépendance listée, vérifie si elle est effectivement importée dans le code source :

```bash
# Vérifier si un package est importé dans le code
# (à faire pour chaque package listé dans dependencies)
grep -rn "from '[PACKAGE_NAME]'\|require('[PACKAGE_NAME]')" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -5
```

Identifie les packages présents dans `package.json` mais sans aucune occurrence d'import dans `src/`.

**c. Dépendances redondantes**

Cherche les chevauchements fonctionnels :

| Catégorie        | Signe de redondance             |
| ---------------- | ------------------------------- |
| HTTP client      | `axios` + `node-fetch` + `got`  |
| Dates            | `moment` + `date-fns` + `dayjs` |
| State management | `redux` + `zustand` + `jotai`   |
| Validation       | `joi` + `zod` + `yup`           |
| ORM              | `prisma` + `typeorm`            |
| Utilitaires      | `lodash` + `ramda`              |

```bash
# Chercher les imports de bibliothèques concurrentes
grep -rn "from 'axios'\|from 'node-fetch'\|from 'got'\|from 'ky'" src/ --include="*.ts" --include="*.js" 2>/dev/null
grep -rn "from 'moment'\|from 'date-fns'\|from 'dayjs'" src/ --include="*.ts" --include="*.js" 2>/dev/null
```

**d. Remplaçables par des API natives**

Identifie les dépendances superflues compte tenu des APIs modernes disponibles :

| Package              | Alternative native                             |
| -------------------- | ---------------------------------------------- |
| `lodash.clonedeep`   | `structuredClone()` (Node 17+)                 |
| `lodash.isequal`     | Comparaison native ou `JSON.stringify`         |
| `moment`             | `Intl.DateTimeFormat`, `date-fns` (plus léger) |
| `request` (déprécié) | `fetch` natif (Node 18+)                       |
| `uuid`               | `crypto.randomUUID()` (Node 14.17+)            |
| `mkdirp`             | `fs.mkdir({ recursive: true })`                |

**e. Dépendances mal classées (dev vs prod)**

```bash
cat package.json 2>/dev/null
```

Signale :

- Outils de build (`typescript`, `vite`, `esbuild`) dans `dependencies` → doivent être en `devDependencies`
- Types (`@types/*`) dans `dependencies` → doivent être en `devDependencies`
- Bibliothèques runtime (`express`, `zod`) en `devDependencies` → doivent être en `dependencies`

---

### 3. Versions, mise à jour et cycle de vie

**a. Dépendances obsolètes**

```bash
rtk npm outdated
```

**b. Audit de vulnérabilités**

```bash
rtk npm audit
```

**c. Dépendances abandonnées ou dépréciées**

```bash
# Vérifier les messages de dépréciation dans npm
rtk npm ls | grep -i "deprecated\|WARN"
```

Lors de l'analyse, signale les packages :

- Sans mise à jour depuis > 2 ans et avec peu d'activité (à remplacer)
- Marqués `deprecated` sur npm
- Dont le mainteneur a annoncé la fin de maintenance (ex: `node-sass`, `request`, `tslint`)

**d. Classification des retards de version**

| Retard                              | Sévérité | Action                                             |
| ----------------------------------- | -------- | -------------------------------------------------- |
| Version majeure (ex: v1 → v3)       | 🔴       | Mise à jour planifiée — risque de breaking changes |
| Version mineure (ex: v3.1 → v3.4)   | 🟡       | Mise à jour recommandée                            |
| Version patch (ex: v3.4.0 → v3.4.2) | 🟢       | Mise à jour simple                                 |

---

### 4. Sécurité des dépendances

```bash
rtk npm audit --json | head -100
```

Classe les vulnérabilités par sévérité :

| Niveau             | Action                                   |
| ------------------ | ---------------------------------------- |
| 🔴 Critical / High | Corriger immédiatement (`npm audit fix`) |
| 🟡 Moderate        | Planifier la mise à jour                 |
| 🟢 Low             | Surveiller                               |

Pour chaque vulnérabilité critique, indique : package concerné, CVE, version fixée disponible, commande de correction.

---

### 5. Adéquation avec la documentation

**a. Stack déclarée dans la documentation**

```bash
# Lire les fichiers de documentation principaux
cat README.md 2>/dev/null | head -100
find . -maxdepth 2 -name "CONTRIBUTING.md" -o -name "ARCHITECTURE.md" -o -name "TECH_STACK.md" 2>/dev/null | xargs cat 2>/dev/null | head -100
```

Extraire la liste des technologies mentionnées explicitement.

**b. Comparaison documentation vs réalité**

| Situation                                                            | Sévérité                            |
| -------------------------------------------------------------------- | ----------------------------------- |
| Technologie dans les docs mais aucune trace dans le code             | 🔴 Documentation fausse ou obsolète |
| Technologie utilisée intensivement mais non mentionnée dans les docs | 🟡 Documentation incomplète         |
| Version mentionnée différente de la version installée                | 🟢 Documentation à rafraîchir       |

---

### 6. APIs et services externes

**a. Identification des intégrations**

```bash
# Variables d'environnement utilisées (indicateur d'intégrations externes)
grep -rn "process\.env\." src/ --include="*.ts" --include="*.js" 2>/dev/null | sed 's/.*process\.env\.\([A-Z_]*\).*/\1/' | sort -u

# Fichier .env.example
cat .env.example 2>/dev/null

# URLs externes dans le code
grep -rn "https://" src/ --include="*.ts" --include="*.js" 2>/dev/null | grep -v "test\|spec\|\.d\.ts" | head -30
```

**b. Évaluation de la qualité d'intégration**

Pour chaque service externe identifié, vérifie :

- **SDK officiel utilisé** ? (ex: `@aws-sdk/*`, `firebase`, `stripe`) ou client HTTP brut sans abstraction ?
- **Gestion des erreurs** : les erreurs de l'API tierce sont-elles interceptées et transformées ?
- **Configuration centralisée** : les clés/URLs sont-elles dans des fichiers de config dédiés ou dispersées ?
- **Clés hardcodées** :

```bash
# Clés API potentiellement hardcodées
grep -rn "sk_\|pk_\|api_key\|apiKey\|Bearer\|token.*=.*['\"]" src/ --include="*.ts" --include="*.js" 2>/dev/null | grep -v "process\.env\|\.env\|test\|spec" | head -20
```

---

### 7. Outils de build et chaîne de développement

**a. Identification de la chaîne**

```bash
cat package.json 2>/dev/null | grep -A30 '"scripts"'
find . -maxdepth 2 -not -path '*/node_modules/*' \
  \( -name "vite.config*" -o -name "webpack.config*" -o -name "rollup.config*" \
     -o -name "jest.config*" -o -name "vitest.config*" -o -name ".eslintrc*" \
     -o -name "biome.json" -o -name ".prettierrc*" -o -name "babel.config*" \
     -o -name "tsconfig*.json" \) | sort
```

**b. Cohérence et modernité de la chaîne**

Évalue chaque outil :

| Rôle        | Outil moderne préféré     | Outils legacy à signaler           |
| ----------- | ------------------------- | ---------------------------------- |
| Bundler     | Vite, esbuild, Rollup     | Webpack 4 (lent, config complexe)  |
| Compiler TS | tsc, SWC                  | Babel seul sans tsc pour les types |
| Linter      | ESLint + règles TS, Biome | TSLint (déprécié), JSHint          |
| Formatter   | Prettier, Biome           | Absence totale de formatter        |
| Test runner | Vitest, Jest              | Mocha seul sans assertion library  |

Signale les redondances : Babel + SWC en même temps, ESLint + Biome configurés tous les deux, etc.

**c. Scripts manquants**

Vérifie la présence des scripts essentiels dans `package.json` :

- `build` — compilation pour la production
- `test` — exécution des tests
- `lint` — vérification du style
- `dev` ou `start` — démarrage en développement
- `type-check` — vérification TypeScript sans emit

---

### 8. Synergie et cohérence de la stack

**a. Chevauchements de responsabilités**

Évalue si des bibliothèques se marchent dessus :

```bash
# Détecter les imports de bibliothèques concurrentes de state management
grep -rn "from 'redux'\|from '@reduxjs'\|from 'zustand'\|from 'jotai'\|from 'recoil'\|from 'mobx'" \
  src/ --include="*.ts" --include="*.tsx" 2>/dev/null | cut -d: -f3 | sort -u

# HTTP clients
grep -rn "from 'axios'\|from 'node-fetch'\|from 'got'\|from 'ky'\|fetch(" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | cut -d: -f3 | sort -u
```

**b. Adéquation de la stack avec le type de projet**

Évalue si les choix sont proportionnés au projet :

| Signal                                                   | Problème                                                 |
| -------------------------------------------------------- | -------------------------------------------------------- |
| Next.js pour une simple page statique                    | Sur-ingénierie                                           |
| Express.js pour une API complexe avec auth, jobs, events | Sous-dimensionné (NestJS, Fastify seraient plus adaptés) |
| React pour un projet avec 2 pages sans état complexe     | Overkill (HTML + Alpine.js suffirait)                    |
| Microservices pour un projet solo < 5K lignes            | Prématuré                                                |

**c. Couplage fort avec une bibliothèque**

Lors de la lecture des fichiers, signale si le code source est excessivement couplé à une API interne non-standard d'une bibliothèque (utilisation de méthodes privées, dépendance à la structure interne), ce qui rendrait une migration difficile.

---

### 9. Licences

**a. Inventaire des licences**

```bash
# Lister les licences des dépendances directes
cat package.json 2>/dev/null | grep -E '"dependencies"|"devDependencies"' -A100 | grep '"' | head -60
```

Lors de l'analyse, note la licence de chaque dépendance principale (disponible dans `node_modules/[package]/package.json` ou sur npm).

**b. Compatibilité**

| Licence             | Risque pour un projet propriétaire               |
| ------------------- | ------------------------------------------------ |
| MIT, ISC, BSD       | Aucun risque                                     |
| Apache 2.0          | Aucun risque (attribution requise)               |
| LGPL                | Risque si modification du code LGPL              |
| GPL                 | 🔴 Incompatible avec code propriétaire fermé     |
| AGPL                | 🔴 Très restrictif (usage réseau = distribution) |
| SSPL                | 🔴 Incompatible avec services commerciaux        |
| Licence commerciale | 🟡 Vérifier les droits d'utilisation             |

---

## Format du rapport

```markdown
# Audit de la pile technologique

## Tableau de bord

| Dimension                  | Score      | Résumé   |
| -------------------------- | ---------- | -------- |
| Langages                   | ⭐⭐⭐⭐☆  | [résumé] |
| Pertinence des dépendances | ⭐⭐⭐☆☆   | [résumé] |
| Versions et cycle de vie   | ⭐⭐⭐☆☆   | [résumé] |
| Sécurité                   | ⭐⭐⭐⭐☆  | [résumé] |
| Adéquation documentation   | ⭐⭐☆☆☆    | [résumé] |
| APIs et services externes  | ⭐⭐⭐⭐☆  | [résumé] |
| Outils de build            | ⭐⭐⭐☆☆   | [résumé] |
| Synergie de la stack       | ⭐⭐⭐⭐☆  | [résumé] |
| Licences                   | ⭐⭐⭐⭐⭐ | [résumé] |

**Score global** : XX/45

---

## 1. Langages

**Langages détectés** : TypeScript (85%), JavaScript (10%), Shell (5%)
**Version runtime** : Node.js 18.17.0 (LTS — ok)

### Points d'attention

- `src/utils/legacy.js` — fichier JavaScript non migré dans un projet TypeScript

---

## 2. Dépendances directes

### Inutilisées (aucun import trouvé)

| Package     | Classé dans  | Dernière utilisation trouvée    |
| ----------- | ------------ | ------------------------------- |
| `lodash`    | dependencies | Aucune — remplaçable par natif  |
| `cross-env` | dependencies | Devrait être en devDependencies |

### Redondantes

- `axios` ET `node-fetch` tous deux importés — choisir l'un ou utiliser `fetch` natif (Node 18+)

### Remplaçables par du natif

| Package  | Remplacement suggéré            | Gain          |
| -------- | ------------------------------- | ------------- |
| `uuid`   | `crypto.randomUUID()`           | -1 dépendance |
| `mkdirp` | `fs.mkdir({ recursive: true })` | -1 dépendance |

### Mal classées

- `typescript` dans `dependencies` → déplacer en `devDependencies`
- `@types/node` dans `dependencies` → déplacer en `devDependencies`

---

## 3. Versions et cycle de vie

### Dépendances obsolètes

| Package    | Actuelle | Dernière | Retard  | Urgence |
| ---------- | -------- | -------- | ------- | ------- |
| `express`  | 4.18.0   | 5.0.1    | Majeure | 🔴      |
| `zod`      | 3.20.0   | 3.23.8   | Mineure | 🟡      |
| `prettier` | 2.8.0    | 3.2.5    | Majeure | 🔴      |

### Dépendances dépréciées / abandonnées

- `node-sass` — déprécié, remplacer par `sass` (Dart Sass)
- `request` — archivé depuis 2020, remplacer par `fetch` natif

---

## 4. Sécurité

**Résultat** : N vulnérabilités (X critiques, Y modérées, Z basses)

### Vulnérabilités critiques

| Package  | CVE            | Sévérité | Version fixée | Commande                     |
| -------- | -------------- | -------- | ------------- | ---------------------------- |
| `lodash` | CVE-2021-23337 | Critical | 4.17.21       | `npm install lodash@4.17.21` |

---

## 5. Adéquation avec la documentation

### Écarts détectés

| Technologie | Dans les docs  | Dans le code                 | Statut                              |
| ----------- | -------------- | ---------------------------- | ----------------------------------- |
| PostgreSQL  | Mentionnée     | Aucune dépendance pg trouvée | 🔴 Documentation fausse             |
| Redis       | Non mentionnée | `ioredis` importé partout    | 🟡 Non documentée                   |
| Vue.js 2    | Mentionnée     | Vue 3 utilisé                | 🟢 Version incorrecte dans les docs |

---

## 6. APIs et services externes

### Services identifiés

| Service  | SDK                   | Qualité d'intégration       | Clé hardcodée ? |
| -------- | --------------------- | --------------------------- | --------------- |
| Stripe   | `stripe` (officiel)   | Bonne — erreurs gérées      | Non             |
| SendGrid | Client HTTP brut      | Moyenne — pas d'abstraction | Non             |
| Firebase | `firebase` (officiel) | Bonne                       | Non             |

### Clés potentiellement exposées

- `src/config/email.ts:12` — chaîne ressemblant à une clé API non lue depuis `.env`

---

## 7. Outils de build

**Chaîne détectée** :

- Bundler : Vite 5.x
- Compiler : tsc (strict)
- Linter : ESLint + @typescript-eslint
- Formatter : Prettier
- Tests : Vitest

### Problèmes

- `babel.config.js` présent mais Vite utilise esbuild — Babel est inutilisé, supprimer
- Script `type-check` absent du `package.json`

---

## 8. Synergie de la stack

### Chevauchements identifiés

- `axios` + `fetch` natif utilisés tous deux pour les appels HTTP — choisir l'un
- `react-query` + `redux` pour la gestion du state serveur — React Query suffit pour le state serveur

### Adéquation avec le projet

La stack (Next.js + Prisma + PostgreSQL + Zustand) est **bien dimensionnée** pour un projet de cette taille (15K lignes, équipe de 3).

---

## 9. Licences

| Package     | Licence | Risque                                 |
| ----------- | ------- | -------------------------------------- |
| `react`     | MIT     | Aucun                                  |
| `express`   | MIT     | Aucun                                  |
| `[package]` | GPL-3.0 | 🔴 Incompatible avec code propriétaire |

---

## Problèmes par sévérité

### 🔴 Critiques

1. **Vulnérabilité critique dans `lodash`**
   - **Correction** : `npm install lodash@4.17.21`

2. **Dépendance GPL dans un projet propriétaire**
   - **Correction** : Remplacer `[package]` par une alternative MIT

### 🟡 Modérés

1. **`express` en retard d'une version majeure** — migrer vers Express 5 ou Fastify

2. **`node-sass` déprécié** — `npm uninstall node-sass && npm install sass`

### 🟢 Mineurs

1. **`typescript` mal classé** — déplacer de `dependencies` vers `devDependencies`

---

## Plan d'action

### Priorité haute (sécurité et compatibilité)

- [ ] `npm audit fix` — corriger les vulnérabilités automatiquement corrigeables
- [ ] Remplacer la dépendance GPL incompatible
- [ ] `npm uninstall node-sass && npm install sass`

### Priorité moyenne (mise à jour et nettoyage)

- [ ] `npm install express@5` — mettre à jour Express
- [ ] `npm uninstall lodash axios` — supprimer les dépendances remplaçables par du natif
- [ ] Déplacer les devDependencies mal classées

### Priorité basse (optimisation)

- [ ] Supprimer `babel.config.js` inutilisé
- [ ] Ajouter le script `type-check` dans `package.json`
- [ ] Mettre à jour le README pour refléter la stack réelle

---

## Métriques

| Métrique                | Valeur            |
| ----------------------- | ----------------- |
| Langages détectés       | N                 |
| Dépendances directes    | N (X prod, Y dev) |
| Dépendances inutilisées | N                 |
| Dépendances outdated    | N                 |
| Vulnérabilités          | N (X critiques)   |
| Services externes       | N                 |
| Licences uniques        | N                 |
```
