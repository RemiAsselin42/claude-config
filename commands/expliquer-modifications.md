---
description: 'Analyse et explique les modifications depuis le dernier commit.'
argument-hint: '[fichiers spécifiques à expliquer, ou vide pour tout expliquer]'
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read, Grep, Glob
context: fork
agent: agent
---

## Périmètre

"$ARGUMENTS"

## État actuel du dépôt

!`git status`

## Résumé des modifications

!`git diff --stat`

## Objectif

Fournir une explication claire et structurée des changements récents pour faciliter la compréhension et la communication au sein de l'équipe.

## Processus

### 1. Collecte des modifications

**a. Inspection de l'état Git**

```bash
rtk git diff                      # Différences détaillées
rtk git log -1 --stat            # Dernier commit (si déjà commité)
```

**b. Lecture du contexte**

- Utilise `Read` pour examiner les fichiers modifiés
- Utilise `Grep` pour comprendre l'usage des fonctions ajoutées

**c. Catégorisation des changements**

- **Nouvelles fonctionnalités** : Ajouts de features
- **Corrections** : Résolution de bugs
- **Refactoring** : Amélioration du code existant
- **Style** : Formatage et conventions
- **Tests** : Ajout ou modification de tests
- **Documentation** : Mises à jour de docs
- **Infrastructure** : Config, build, dépendances

### 3. Génération du rapport

Produis un rapport structuré et concis :

```markdown
# Synthèse des modifications

**X fichiers modifiés** | +Y lignes | -Z lignes

## Résumé exécutif

[2-3 phrases décrivant l'objectif global des modifications]

## Détail par fichier

### src/sections/01-hero/hero.ts (+45, -12)

Ajoute l'animation de rotation automatique du modèle 3D avec contrôle de vitesse.

### src/core/scrollManager.ts (+23, -8)

Améliore la synchronisation du scroll avec affichage de la progression et transitions fluides.

### src/sections/sectionManager.test.ts (+78, -0)

Crée une suite de tests complète couvrant les cas nominaux et les edge cases de gestion des sections.

### src/sections/01-hero/README.md (+15, -3)

Met à jour la documentation avec les nouveaux paramètres d'animation et exemples d'usage.

### src/sections/registry.ts (+2, -1)

Enregistre la nouvelle section hero avec ses animations dans le registre des sections.

## Changements significatifs

1. **Nouvelle logique d'animation** : Ajout du contrôle de rotation avec vitesse paramétrable
2. **Amélioration du scroll** : Synchronisation plus fluide avec indicateur de progression
3. **Couverture de tests** : +78 lignes de tests pour garantir la robustesse
4. **Documentation à jour** : README enrichi avec exemples pratiques

## Impact

- **Fonctionnalité** : Animation plus fluide et contrôles améliorés
- **UX** : Interface plus responsive et informative
- **Qualité** : Couverture de tests améliorée à 92%
- **Maintenance** : Documentation facilitant l'onboarding

## Type de changement

[Feature | Fix | Refactor | Docs | Tests | Style | Perf | Chore]
```

## Format de sortie

### Pour chaque fichier, utilise ce format concis :

**Fichiers de production**

```
### chemin/vers/fichier.ts (+XX, -YY)
[Une ligne décrivant le changement principal]
```

**Tests**

```
### tests/fichier.test.ts (+XX, -YY)
[Une ligne décrivant ce qui est testé]
```

**Documentation**

```
### docs/fichier.md (+XX, -YY)
[Une ligne sur la mise à jour de la doc]
```

**Configuration**

```
### fichier.config.ts (+XX, -YY)
[Une ligne sur le changement de config]
```

**Styles**

```
### styles/fichier.scss (+XX, -YY)
[Une ligne sur les changements de style]
```

## Principes de rédaction

### À FAIRE

- **Clarté** : Langage simple et accessible
- **Concision** : Une ligne par fichier, phrases courtes
- **Contexte** : Explique le "pourquoi" en plus du "quoi"
- **Structure** : Utilise les emojis pour la lisibilité
- **Hiérarchie** : Synthèse → Détails → Impact
- **Objectivité** : Décris factuellement sans jugement

## Exemples de descriptions concises

✅ **Bonnes descriptions (une ligne) :**

- "Ajoute la validation des emails avec regex conforme RFC 5322"
- "Corrige le bug de fermeture modale lors du clic sur overlay"
- "Refactorise le hook useScan pour réduire les re-renders inutiles"
- "Extrait les constantes en fichier dédié pour améliorer la maintenabilité"
- "Améliore le contraste des boutons pour accessibilité WCAG 2.1 AA"

## Outils

- `Bash` : Exécuter les commandes git
- `Read` : Examiner les fichiers modifiés si nécessaire
- `Grep` : Comprendre le contexte d'un changement

## Cas d'usage

1. **Stand-up meeting** : Expliquer rapidement ce qui a été fait
2. **Pull request** : Aider les reviewers à comprendre les changements
3. **Documentation** : Préparer des notes de release
4. **Onboarding** : Aider nouveaux membres à comprendre l'évolution
5. **Communication** : Partager les avancées avec des non-techniques

Fournis une explication claire, structurée et facile à comprendre qui permet à quiconque de saisir rapidement l'essentiel des modifications.
