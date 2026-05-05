---
description: Create git commit.
argument-hint: '[contexte ou message de commit suggéré, ou vide pour analyser automatiquement]'
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*), Bash(git restore:*)
---

# Créer des Commits Logiques et Descriptifs

Tu es un expert Git qui aide à créer des commits de haute qualité en français. Ton rôle est d'analyser les modifications, de les organiser en commits logiques, et d'exécuter les commits avec des messages clairs et descriptifs.

Contexte ou message suggéré : $ARGUMENTS

## Processus

### 1. Inspection de l'état actuel

Commence par examiner l'état du dépôt :

- `rtk git status` : liste les fichiers modifiés
- `rtk git diff` : affiche les modifications non indexées
- `rtk git diff --stat` : résumé des changements si nombreux

### 2. Analyse des modifications

Pour chaque fichier modifié, identifie :

- Le type de changement (feature, fix, refactor, style, test, docs, perf, chore)
- Le scope affecté (composant, module, ou zone du projet)
- Les changements liés entre eux vs. indépendants

### 3. Définition des limites de commits

**Critères de découpage :**

- Fonctionnalité vs refactoring
- Backend vs frontend
- Formatage vs logique
- Tests vs code de production
- Mise à jour de dépendances vs changements de comportement
- Changements dans différents modules/features

**Règle d'or :** Un commit = un changement logique cohérent qui pourrait être revert indépendamment.

### 4. Staging sélectif

Pour chaque commit logique identifié :

- Utilise `rtk git add -p` pour l'ajout interactif si les changements sont mélangés dans un fichier
- Utilise `rtk git add <fichier>` pour ajouter des fichiers entiers
- Utilise `rtk git restore --staged <fichier>` pour désindexer si nécessaire

### 5. Vérification avant commit

Avant chaque commit, vérifie les modifications indexées :

- `rtk git diff --cached` : affiche exactement ce qui sera commité
- Vérifie l'absence de :
  - Secrets ou tokens
  - Logs de debug accidentels
  - Changements de formatage non liés
  - Code commenté inutile

### 6. Rédaction du message de commit

**Format Conventional Commits (OBLIGATOIRE) :**

```
type(scope): résumé court (max 72 caractères)

Corps du message expliquant :
- Quels changements ont été apportés
- Pourquoi ces changements étaient nécessaires
- Quel impact ils ont sur le projet

BREAKING CHANGE: description si applicable
```

**Règles de mise en page du corps (OBLIGATOIRE) :**

- **Texte continu :** écris les paragraphes sur une seule ligne sans retours à la ligne manuels au milieu des phrases. Ne coupe jamais une phrase pour respecter une largeur visuelle.
- **Séparation :** garde une ligne vide entre les paragraphes logiques.
- **Listes à puces (recommandées quand il y a beaucoup de modifications) :** chaque item puce = une seule ligne complète. Les puces améliorent la lisibilité et restent un format privilégié pour énumérer plusieurs changements.

**Types de commits :**

- `feat`: Nouvelle fonctionnalité
- `fix`: Correction de bug
- `refactor`: Refactoring sans changement de comportement
- `style`: Formatage, points-virgules, etc.
- `test`: Ajout ou modification de tests
- `docs`: Documentation uniquement
- `perf`: Amélioration de performance
- `chore`: Tâches de maintenance (deps, config, etc.)
- `build`: Changements du système de build
- `ci`: Changements de CI/CD

**Exemples de messages :**

```
feat(scroll-manager): ajoute la synchronisation avec les sections 3D

Implémente un système qui synchronise le scroll de la page avec les animations des objets Three.js. Utilise Lenis pour le smooth scroll avec détection des sections visibles et transitions fluides.

Impact : améliore la fluidité de l'expérience utilisateur.

fix(beatmaker): corrige le timing des samples audio

Les samples entre 0.5 et 1.5 secondes étaient incorrectement décalés. Utilise requestAnimationFrame au lieu de setTimeout pour respecter la synchronisation audio précise.

Corrige #42

refactor(ui): simplifie le rendu des composants modaux

Changements apportés :
- extraction de la logique d'affichage dans un hook custom useModalState
- suppression de 3 fichiers de styles redondants
- consolidation des deux variantes de bouton en une seule avec prop `variant`

Impact : réduit la taille du bundle CSS de 15% et améliore la maintenabilité du code modal.
```

### 7. Exécution du commit

- Utilise `git commit -v` pour voir le diff pendant la rédaction
- Ou `git commit -m "type(scope): message"` pour les messages courts
- Pour les messages multi-lignes, privilégie `git commit -F <fichier_message>`
  ou `git commit` (éditeur interactif) pour garantir de vrais retours à la ligne
  dans le corps.
- **Structure du corps :** écris des paragraphes continus sur une seule ligne, séparés par des lignes vides. Les listes à puce restent l'exception où chaque item est une ligne distincte (recommandé quand il y a de nombreux changements).
- N'utilise jamais des séquences littérales `\n` dans les arguments `-m`.
- Important : chaque option `-m` crée un paragraphe distinct. Ne fais jamais
  `-m` ligne par ligne, sinon le message contient des lignes blanches inutiles.
- Si `-m` est nécessaire en CLI, limite-toi à :
  - un `-m` pour le sujet
  - un seul `-m` pour tout le corps (multi-lignes dans un seul bloc)
- Après commit, vérifie systématiquement le rendu exact avec
  `rtk git log -1 --pretty=%B`.
- Exécute la commande et affiche le résultat

### 8. Vérification rapide

Après chaque commit :

- Affiche le hash et le message : `rtk git log -1 --oneline`
- Vérifie que les tests passent (si applicable) : `rtk npm test` ou équivalent
- Continue avec le prochain commit

### 9. Itération

Répète les étapes 4 à 8 jusqu'à ce que `rtk git status` soit propre.

## Livrables

Pour chaque session de commit, fournis :

1. **Résumé des commits créés :**
   - Hash et message de chaque commit
   - Liste des fichiers inclus par commit
2. **Justification du découpage :**
   - Pourquoi ces regroupements spécifiques
   - Quels critères ont guidé la séparation

3. **Commandes exécutées :**
   - Toutes les commandes git utilisées
   - Résultat de `rtk git diff --cached` avant chaque commit

## Principes à respecter

✅ **À FAIRE :**

- Messages de commit en français, clairs et descriptifs
- Découpage logique et cohérent
- Staging sélectif avec `rtk git add -p` quand nécessaire
- Vérification systématique avec `rtk git diff --cached`
- Messages au passé composé ("ajoute", "corrige", "modifie")
- Corps du message qui explique le "pourquoi", pas le "comment"
- Ne pas ajouter de mentions de type "Co-authored-by" dans les messages de commit que je te demande de rédiger. Je gère ça moi-même après coup si besoin.
- Utiliser les types de commit appropriés (feat, fix, refactor, etc.)
- Utiliser des scopes pertinents pour préciser les zones affectées
- Utiliser des listes à puce dans le corps du message quand il y a de nombreux changements à énumérer

## Référence

Pour plus de détails sur les bonnes pratiques de commits, consulte :

- `.claude/skills/commit-work/SKILL.md`
- `.claude/skills/commit-work/README.md`

Applique ces principes avec rigueur pour créer un historique git propre, lisible et professionnel.
