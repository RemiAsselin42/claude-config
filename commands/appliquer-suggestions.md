---
description: 'Applique les recommandations de modifications au code, valide l`intégration et exécute les tests. Use when: appliquer suggestions, implémenter recommandations, corriger problèmes identifiés, apply changes, fix issues, implement suggestions, mettre en œuvre corrections.'
argument-hint: '[recommandations à appliquer ou référence à une analyse précédente]'
allowed-tools: Read, Edit, Bash, Grep, Glob, TodoWrite
context: fork
agent: agent
---

## Contexte

Ce prompt s'utilise **après** une phase d'analyse ou de revue de code qui a identifié des problèmes, du code mort, des problèmes de commentaires, des problèmes de performance, d'architecture, de qualité ou des améliorations à apporter. Tu dois prendre les recommandations faites précédemment et les implémenter de manière rigoureuse.

$ARGUMENTS

## Détection automatique de la source d'analyse

Ce prompt tourne en contexte isolé (`fork`) — il ne voit pas le stdout des commandes précédentes.

**Si `$ARGUMENTS` est vide**, applique cette stratégie dans l'ordre :

1. **Re-lancer l'analyse** : détecte le type de projet (Shell/TS/JS/Python…) et exécute la commande d'analyse adaptée pour obtenir les recommandations à jour :
   - Code mort → relance `/trouver-code-mort` en lisant les fichiers directement
   - Qualité → grep patterns suspects dans les sources
2. **Demander** : si tu ne peux pas déduire la portée, pose une question précise : _"Quel type d'analyse appliquer, et dans quel répertoire ?"_

**Ne jamais répondre "aucune analyse visible"** sans avoir d'abord tenté la détection.

## Sources d'analyse reconnues

### Rapport `/trouver-code-mort`

Format de sortie : sections `🔴 Certain`, `🟡 Probable`, `🟢 Suspect` avec des entrées `### fichier — ligne(s)`.

Mapping vers les priorités internes :

| Sévérité `/trouver-code-mort` | Priorité `appliquer-suggestions` |
| ----------------------------- | --------------------------------- |
| 🔴 Certain                    | **Critique** — appliquer en premier |
| 🟡 Probable                   | **Importante** — appliquer après vérification |
| 🟢 Suspect                    | **Mineure** — appliquer si confirmé |

Pour chaque entrée 🟡 Probable, vérifie l'absence d'appel dynamique avant de supprimer (grep du symbole dans tout le projet).

### Rapport `/evaluer-qualite`, `/evaluer-commentaires`, `/evaluer-documentation`

Ces rapports utilisent des sections numérotées ou des listes de recommandations — extrait chaque item comme une modification à appliquer.

## Cas d'usage typiques

1. **Après une revue de code** : Implémenter les suggestions d'un reviewer
2. **Après un audit** : Corriger les problèmes de qualité détectés
3. **Après une recommandation d'architecture** : Refactorer selon les best practices
4. **Après une analyse de sécurité** : Corriger les vulnérabilités
5. **Après une optimisation** : Appliquer les améliorations de performance
6. **Après une analyse de dépendances** : Mettre à jour les versions et corriger les problèmes liés
7. **Après une analyse de couverture** : Ajouter les tests manquants
8. **Après une analyse de style** : Corriger les problèmes de linting
9. **Après une analyse de documentation** : Mettre à jour les commentaires et la documentation
10. **Après une analyse de performance** : Optimiser les parties identifiées comme lentes

## Processus

### 1. Récapitulatif des recommandations

Commence par lister clairement :

- Les problèmes identifiés dans l'analyse précédente
- Les solutions recommandées pour chaque problème
- La priorité de chaque modification (critique, importante, mineure)
- Les fichiers à modifier

**Si les recommandations proviennent de `/trouver-code-mort`**, utilise le tableau de mapping ci-dessus pour assigner les priorités automatiquement — pas besoin de demander.

**Si les recommandations ne sont pas claires ou qu'un choix architectural est nécessaire**, demande des clarifications.

### 2. Analyse de l'impact

Avant toute modification, évalue :

- **Architecture** : Comment ces changements s'intègrent-ils dans la structure actuelle ?
- **Dépendances** : Quels autres modules/composants sont affectés ?
- **Standards** : Quelles conventions de code doivent être respectées ?
- **Tests** : Quels tests doivent être ajoutés ou modifiés ?

### 3. Planification des modifications

Organise les changements par ordre logique :

1. Modifications d'infrastructure/types/interfaces (base)
2. Modifications de logique métier
3. Modifications d'UI/composants
4. Ajout/mise à jour des tests
5. Mise à jour de la documentation

**Utilise `TodoWrite` pour suivre l'avancement.**

### 4. Application des modifications

Pour chaque changement :

**a. Lire le contexte existant**

- Utilise `Read` pour comprendre le code actuel
- Identifie les patterns et conventions utilisés
- Note les imports, types, et dépendances existants

**b. Implémenter la modification**

- Utilise `Edit` pour appliquer les changements
- Respecte le style de code existant (indentation, nommage, structure)
- Ajoute des commentaires si la logique est complexe
- Assure la cohérence avec les conventions TypeScript/React du projet

**c. Vérifier les erreurs**

- Utilise `Bash` pour exécuter `rtk lint` et détecter les erreurs
- Corrige immédiatement les problèmes détectés
- Continue jusqu'à avoir zéro erreur

### 5. Vérification de l'intégration

Après chaque série de modifications :

**a. Cohérence architecturale**

- Les nouveaux composants suivent-ils les patterns établis ?
- Les imports sont-ils organisés correctement ?
- Les types sont-ils cohérents avec le reste du projet ?

**b. Standards de code**

- Vérifie l'absence de `any` types
- Vérifie que les hooks React sont utilisés correctement
- Vérifie que les noms de fichiers suivent la convention du projet
- Vérifie l'accessibilité (aria-labels, roles, etc.)

**c. Analyse des erreurs**

```bash
rtk lint                 # Vérifier le linting
rtk npm run type-check   # Vérifier les types TypeScript (si disponible)
```

### 6. Validation fonctionnelle

**a. Exécuter les tests existants**

```bash
rtk npm test                    # Tous les tests
rtk npm test -- --coverage      # Avec couverture
rtk npm test -- <fichier>       # Tests spécifiques
```

**b. Tests manuels si nécessaire**

- Décris les scénarios de test manuels à effectuer
- Note les comportements attendus
- Documente les résultats observés

**c. Vérifier les effets de bord**

- Les fonctionnalités existantes fonctionnent-elles toujours ?
- Les modifications ont-elles introduit de nouveaux warnings ?
- Les performances sont-elles affectées ?

### 7. Ajout/Mise à jour des tests

Si les tests doivent être créés ou modifiés :

**a. Tests unitaires**

- Crée des tests pour les nouvelles fonctions/composants
- Couvre les cas nominaux et les cas d'erreur
- Vise une couverture > 80% pour le code modifié

**b. Tests d'intégration**

- Teste les interactions entre composants modifiés
- Vérifie les flux de données

**c. Exécute et valide**

```bash
rtk npm test -- --run           # Vitest
rtk npm test -- --watch         # Mode watch pour itérer
```

### 8. Documentation

Mets à jour la documentation si nécessaire :

- README.md si l'API publique a changé
- Fichiers README.md des features modifiées
- Commentaires JSDoc pour les fonctions publiques
- CHANGELOG.md si applicable

### 9. Rapport final

Fournis un résumé structuré :

```markdown
## ✅ Modifications appliquées

### Fichiers modifiés

- `src/sections/01-hero/hero.ts` : Description du changement
- `src/sections/sectionManager.test.ts` : Tests ajoutés

### Problèmes corrigés

1. ✅ [Problème 1] : Solution appliquée
2. ✅ [Problème 2] : Solution appliquée

### Tests

- ✅ Tous les tests passent (X/X)
- ✅ Couverture : XX%
- ✅ Pas d'erreurs TypeScript
- ✅ Pas d'erreurs ESLint

### Vérifications

- ✅ Intégration architecturale conforme
- ✅ Standards de code respectés
- ✅ Pas de régression détectée
- ✅ Documentation mise à jour

### Changements restants (si applicable)

- [ ] Modification optionnelle non appliquée : raison
```

## Principes directeurs

### ✅ À FAIRE

- **Lire avant d'écrire** : Comprendre le contexte existant
- **Modifications incrémentales** : Appliquer par petits lots testables
- **Vérification continue** : Utiliser `get_errors` fréquemment
- **Tests systématiques** : Exécuter les tests après chaque modification
- **Communication** : Expliquer ce qui est fait et pourquoi
- **Cohérence** : Respecter les patterns et conventions du projet

## Gestion des problèmes

### Si une modification échoue

1. Analyse l'erreur avec `Bash` (lint/type-check)
2. Reviens sur le changement si nécessaire
3. Propose une solution alternative
4. Documente pourquoi la recommandation initiale n'a pas pu être appliquée

### Si les tests échouent

1. Identifie le test qui échoue
2. Comprends pourquoi (régression vs test obsolète)
3. Corrige le code ou adapte le test selon le cas
4. Réexécute jusqu'à succès

### Si l'intégration pose problème

1. Identifie les conflits avec l'architecture existante
2. Propose des ajustements
3. Demande validation si le changement est significatif

## Outils recommandés

- `Read` : Lire le code existant
- `Edit` : Appliquer les modifications
- `Bash` : Exécuter tests et commandes de validation
- `TodoWrite` : Suivre l'avancement des modifications
- `Grep` : Trouver les occurrences d'un pattern dans le code
- `Glob` : Explorer la structure du projet

## Exemple de flux

```
Utilisateur : "Applique les suggestions de refactoring que tu as faites"

Assistant :
1. 📋 Récapitulatif : 5 modifications identifiées
2. 🔍 Analyse d'impact : 3 fichiers à modifier
3. ✅ Modification 1/5 appliquée + tests OK
4. ✅ Modification 2/5 appliquée + tests OK
5. ⚠️  Modification 3/5 : erreur détectée, correction alternative
6. ✅ Modification 4/5 appliquée + tests OK
7. ✅ Modification 5/5 appliquée + tests OK
8. ✅ Tous les tests passent (42/42)
9. 📊 Rapport final : 5/5 appliquées, zéro régression
```

Applique ces principes avec rigueur pour garantir des modifications de qualité professionnelle qui s'intègrent parfaitement dans le projet existant.
