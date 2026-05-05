---
description: 'Trouve le code mort (unreachable, unused, deprecated) dans le projet.'
argument-hint: '[langage] [chemin] — ex: shell, typescript src/, python, javascript src/utils.js'
allowed-tools: Read, Grep, Glob, Bash(npm run type-check:*), Bash(npx tsc:*)
context: fork
agent: agent
---

## Arguments

"$ARGUMENTS"

Parse `$ARGUMENTS` :
- **Langage** (obligatoire) : premier mot — ex: `shell`, `typescript`, `javascript`, `python`, `go`, `rust`…
- **Chemin** (optionnel) : deuxième argument — sinon, scanner tout le projet

Si le langage est absent, détecte automatiquement à partir des fichiers du projet (ex: présence de `package.json` → probablement JavaScript/TypeScript).

---

## Objectif

Identifier tout le code mort dans le périmètre donné : branches inatteignables, fonctions/symboles jamais utilisés, variables déclarées mais ignorées, conditions toujours vraies/fausses.

---

## Processus

### 1. Découverte du périmètre

Liste les fichiers source du langage cible dans le chemin spécifié (ou tout le projet). Adapte les extensions et les dossiers à exclure selon le langage (ex: `node_modules/`, `dist/`, `*.d.ts`, `__pycache__/`…).

### 2. Catégories universelles de code mort

Pour **chaque** catégorie ci-dessous, adapte les outils et patterns de détection au langage cible :

#### A. Symboles définis mais jamais utilisés

Fonctions, méthodes, classes, constantes, types définis dans le code mais dont aucun appel ou référence n'est trouvé dans le projet.

- Grep le nom du symbole dans tout le projet (hors sa propre définition)
- Tiens compte des exports publics qui peuvent être consommés dynamiquement (→ Probable, pas Certain)

#### B. Code après un point de sortie non conditionnel

Toute instruction après un `return` / `exit` / `throw` / `break` / `continue` non conditionnel — la ligne suivante ne peut jamais être atteinte.

- Lis chaque fichier, trace le flow de contrôle
- Cherche les lignes non vides et non commentaires après un point de sortie garanti

#### C. Branches conditionnelles logiquement inatteignables

Conditions dont la valeur est statiquement déterminable au point d'évaluation :

- Variable assignée à une valeur fixe juste avant le test
- `if (true)` / `if (false)` explicites ou équivalents
- `else` / `default` après un `if`/`switch`/`case` qui couvre exhaustivement tous les cas possibles
- Early return sur une condition, suivi d'un test redondant sur la même condition

#### D. Variables assignées mais jamais lues

Variable locale déclarée et affectée, mais `$var` / `var` / `self.var` jamais lu dans son scope de vie.

#### E. Imports / includes / sources non utilisés

Module importé, fichier sourcé, header inclus, dont aucun symbole n'est référencé dans le fichier qui l'importe.

#### F. Code marqué comme abandonné

```
TODO: remove
FIXME: dead
DEPRECATED
unused
```

Grep ces patterns dans le périmètre — souvent du code mort auto-documenté.

### 3. Analyse file par file

Pour chaque fichier du périmètre :

1. **Lis** avec `Read`
2. **Symboles exportés** → grep leur usage dans tout le projet
3. **Flow de contrôle** → repère les sorties garanties, les conditions fixées
4. **Variables locales** → trace leur cycle de vie dans le scope

### 4. Critères de sévérité

| Sévérité    | Critère                                                                      |
| ----------- | ---------------------------------------------------------------------------- |
| 🔴 Certain  | Inatteignable par raisonnement statique pur                                  |
| 🟡 Probable | Aucun usage trouvé, mais appel dynamique / reflection / eval possible        |
| 🟢 Suspect  | Logiquement difficile à déclencher, mais un chemin d'exécution reste ouvert  |

---

## Format du rapport

````markdown
# Rapport : Code Mort — <Langage> — <Chemin>

## Résumé

- **Fichiers analysés** : N
- **Occurrences** : X certaines, Y probables, Z suspectes

---

## 🔴 Certain

### `chemin/fichier.ext` — ligne(s) N-M

**Type** : <catégorie>
**Raison** : <explication du flow qui rend ce code inatteignable>

**Code mort** :
```
<extrait>
```

**Correction** : <action concrète>

---

## 🟡 Probable

### `chemin/fichier.ext` — `<symbole>`

**Raison** : Aucun appel trouvé dans le projet.
**Caveat** : <raison pour laquelle un usage dynamique reste possible>

---

## 🟢 Suspect

### `chemin/fichier.ext` — ligne N

**Type** : <catégorie>
**Raison** : <pourquoi c'est suspect sans être certain>

---

## Actions recommandées

- [ ] Supprimer les blocs morts certains
- [ ] Vérifier les symboles probables avant suppression
- [ ] Annoter les cas exhaustifs intentionnels
````
