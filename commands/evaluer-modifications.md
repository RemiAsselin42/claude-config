---
description: 'Analyse et évalue les modifications depuis le dernier commit.'
argument-hint: '[fichiers ou features spécifiques à analyser, ou vide pour tout analyser]'
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read, Grep, Glob
context: fork
agent: agent
---

## Périmètre d'analyse

"$ARGUMENTS"

## État actuel du dépôt

!`git status`

## Résumé des modifications

!`git diff --stat`

## Objectif

Fournir une analyse critique et constructive des modifications récentes pour assurer la qualité, la maintenabilité et l'évolution saine du projet.

## Processus d'évaluation

### 1. Collecte des modifications

**a. Inspection de l'état Git**

```bash
rtk git diff                      # Différences détaillées
rtk git log -1 --stat            # Dernier commit (si déjà commité)
```

**b. Lecture du contexte**

- Utilise `Read` pour examiner les fichiers modifiés
- Utilise `Grep` pour comprendre l'usage des fonctions ajoutées
- Utilise `Glob` pour explorer la structure du projet

**c. Catégorisation des changements**

- **Nouvelles fonctionnalités** : Ajouts de features
- **Corrections** : Résolution de bugs
- **Refactoring** : Amélioration du code existant
- **Style** : Formatage et conventions
- **Tests** : Ajout ou modification de tests
- **Documentation** : Mises à jour de docs
- **Infrastructure** : Config, build, dépendances

### 2. Analyse des changements significatifs

Pour chaque fichier modifié, identifie :

**a. Nature des changements**

- Lignes ajoutées vs supprimées
- Complexité (simple formatage vs logique métier complexe)
- Portée (local vs impact global)
- Type de code (production, tests, config)

**b. Impact fonctionnel**

- Nouveaux comportements introduits
- Comportements existants modifiés
- Fonctionnalités supprimées
- APIs changées (breaking changes ?)

**c. Impact technique**

- Architecture : Nouveaux patterns, dépendances entre modules
- Performance : Optimisations ou dégradations potentielles
- Sécurité : Nouvelles vulnérabilités ou corrections
- Maintenabilité : Lisibilité, complexité, duplication

### 3. Évaluation qualitative

**a. Intégration architecturale**

- ✅ Les changements suivent-ils l'architecture existante ?
- ✅ Les nouveaux modules/composants sont-ils bien placés ?
- ✅ Les dépendances sont-elles gérées correctement ?
- ✅ Y a-t-il du couplage excessif introduit ?
- ⚠️ Des abstractions manquent-elles ?

**b. Qualité du code**

- ✅ Le code est-il lisible et compréhensible ?
- ✅ Les noms sont-ils explicites et cohérents ?
- ✅ La complexité est-elle maîtrisée ?
- ✅ Y a-t-il de la duplication de code ?
- ✅ Les types TypeScript sont-ils bien utilisés ?
- ⚠️ Présence de `any`, magic numbers, code mort ?

**c. Tests et validation**

- ✅ Des tests accompagnent-ils les nouveaux codes ?
- ✅ La couverture de tests est-elle maintenue/améliorée ?
- ✅ Les tests sont-ils pertinents et complets ?
- ⚠️ Y a-t-il des cas limites non testés ?

**d. Documentation**

- ✅ Le code est-il autodocumenté ?
- ✅ Des commentaires expliquent-ils la logique complexe ?
- ✅ La documentation externe est-elle à jour ?
- ⚠️ Des READMEs nécessitent-ils une mise à jour ?

### 4. Identification des risques

Analyse systématique des risques potentiels :

**🔴 Risques critiques**

- Breaking changes non documentés
- Vulnérabilités de sécurité introduites
- Fuites mémoire ou problèmes de performance graves
- Perte de données ou corruption possible
- Régression de fonctionnalités existantes

**🟡 Risques modérés**

- Complexité excessive dans la logique métier
- Dépendances circulaires
- Couplage fort entre modules
- Dette technique accrue
- Tests insuffisants pour nouveau code
- Fichier de code volumineux (>500 lignes) non maintenable

**🟢 Points d'attention mineurs**

- Conventions de nommage inconsistantes
- Formatage non standard
- Commentaires manquants
- Documentation incomplète
- Opportunités d'optimisation manquées

### 5. Identification des points positifs

Reconnaît les bonnes pratiques :

- Architecture bien pensée et extensible
- Code élégant et idiomatique
- Tests complets avec bonne couverture
- Documentation claire et exhaustive
- Performance optimisée
- Accessibilité prise en compte
- Gestion d'erreurs robuste

- Refactoring qui améliore la lisibilité
- Correction de bugs avec tests de non-régression
- Respect des conventions du projet
- Amélioration de la maintenabilité
- Réduction de la complexité

### 6. Suggestions d'amélioration

Propose des améliorations concrètes et actionnables :

**Améliorations prioritaires**

- Corrections de risques critiques
- Ajout de tests manquants
- Refactoring de code trop complexe
- Documentation de points obscurs

**Améliorations secondaires**

- Extraction de fonctions pour réduire la complexité
- Ajout de types plus stricts
- Amélioration de la gestion d'erreurs
- Optimisations de performance
- Réduction de duplication

**Améliorations recommandées**

- Refactoring cosmétique
- Ajout de commentaires utiles
- Harmonisation du style
- Améliorations de l'accessibilité

## Format du rapport

Génère un rapport structuré et actionnable :

````markdown
# Évaluation des modifications

## Fichiers analysés

### `src/sections/01-hero/hero.ts` (+45, -12)

**Type** : Nouvelle fonctionnalité
**Changements** : Ajout de l'animation de rotation automatique du modèle 3D
**Impact** : Majeur - Améliore l'expérience visuelle de la section hero

### `src/sections/sectionManager.test.ts` (+78, -0)

**Type** : Tests
**Changements** : Suite de tests complète pour la gestion des sections
**Impact** : Positif - Couverture à 95%

---

## Points positifs

### Architecture et design

- ✅ **Patterns cohérents** : Utilise les mêmes patterns que les autres features existantes

### Qualité du code

- ✅ **Types stricts** : Excellent usage de TypeScript avec zéro `any`
- ✅ **Lisibilité** : Noms de fonctions explicites et code autodocumenté
- ✅ **Gestion d'erreurs** : Try/catch appropriés avec messages clairs

### Tests et validation

- ✅ **Couverture excellent** : 95% de couverture sur le nouveau code
- ✅ **Tests pertinents** : Couvre les cas nominaux et les edge cases
- ✅ **Mocks appropriés** : Les objets Three.js sont bien mockés

### Documentation

- ✅ **README.md à jour** : Documentation claire de la nouvelle feature
- ✅ **Commentaires utiles** : Explications sur la logique complexe

---

## Risques et points d'attention

### 🔴 Risques critiques

- **Vulnérabilité potentielle** : Le rendu d'objets 3D complexes pourrait provoquer des lags sur des configurations faibles

### 🟡 Risques modérés

1. **Performance potentielle**
   - **Où** : `scrollManager.ts:45-67` - Calculs d'animation sur chaque frame
   - **Impact** : Possible dégradation de framerate sur scènes complexes (>500 objets)
   - **Mitigation** : Ajouter un système de LOD ou optimiser les calculs
2. **Couplage avec Three.js API**
   - **Où** : `glbModel.ts:23` - Dépendance directe aux propriétés internes de Three.js
   - **Impact** : Risque de breaking change si Three.js modifie son API
   - **Mitigation** : Ajouter une couche d'abstraction ou des guards

### 🟢 Points d'attention mineurs

1. **Formatage inconsistant**
   - Mélange de simple et double quotes dans `scrollManager.ts`
   - Suggestion : Exécuter Prettier sur le fichier

2. **Test edge case manquant**
   - Cas non testé : Section avec deltaTime=0 ET scroll à l'infini
   - Suggestion : Ajouter un test `shouldHandleZeroDelta()`

---

## Suggestions d'amélioration

### Priorité haute (recommandé d'implémenter)

1. **Limiter la complexité du rendu**

   ```typescript
   // Dans scrollManager.ts
   function updateSection(
     section: SectionLifecycle,
     deltaTime: number,
     maxDelta: number = 0.1
   ) {
     if (deltaTime > maxDelta) {
       console.warn('Delta trop élevé, limitation à', maxDelta);
       deltaTime = maxDelta;
     }
     section.update(deltaTime, this.elapsedTime);
   }
   ```

2. **Ajouter une couche d'abstraction pour Three.js**
   ```typescript
   // Nouveau fichier: src/core/objectHelpers.ts
   export const getObjectVisibility = (object: THREE.Object3D): boolean => {
     return object.visible && (object.userData.opacity ?? 1) > 0;
   };
   ```

### Priorité moyenne (amélioration de qualité)

3. **Extraire la logique de scoring**
   - Le calcul du score est dupliqué dans plusieurs endroits
   - Suggestion : Centraliser dans `shared/score.ts`

4. **Améliorer les messages d'erreur**
   - Les erreurs actuelles sont génériques
   - Suggestion : Ajouter du contexte (nom du node, type)

5. **Ajouter des tests de performance**
   - Créer des benchmarks pour les scènes complexes
   - Fichier suggéré : `tests/performance/rendering.bench.ts`

### Priorité basse (nice-to-have)

6. **Harmoniser le style de code**
   - Exécuter Prettier avec `--write` sur tous les fichiers modifiés

7. **Améliorer l'accessibilité de l'interface**
   - Ajouter des `aria-label` sur les contrôles interactifs
   - Ajouter un `role="status"` sur les indicateurs de chargement

8. **Documentation technique**
   - Ajouter un diagramme de séquence pour le flow de détection
   - Documenter la complexité algorithmique du parcours

---

## Actions recommandées

### Avant de merger

- [ ] Implémenter la limitation du deltaTime (risque modéré)
- [ ] Ajouter le test edge case manquant (deltaTime nul)
- [ ] Exécuter Prettier sur les fichiers modifiés

### Après le merge

- [ ] Créer une issue pour la couche d'abstraction Three.js
- [ ] Implémenter les tests de performance (benchmark)
- [ ] Mettre à jour le diagramme d'architecture dans `/docs`

### Optionnel

- [ ] Refactoring du système de scoring (peut être fait plus tard)
- [ ] Amélioration de l'accessibilité (améliorations progressives)

---

## 📈 Métriques

| Métrique                | Avant | Après | Évolution    |
| ----------------------- | ----- | ----- | ------------ |
| Lignes de code          | 2,345 | 2,468 | +123 (+5.2%) |
| Couverture tests        | 87%   | 91%   | +4% ✅       |
| Complexité cyclomatique | 245   | 267   | +22 ⚠️       |
| Fichiers                | 42    | 45    | +3           |
| Dépendances             | 18    | 18    | =            |
````
