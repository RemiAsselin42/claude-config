---
description: 'Analyse et évalue un dépôt fraîchement cloné : but du projet, fonctionnalités, qualité du code, problèmes et recommandations.'
argument-hint: '[focus particulier ou aspect à approfondir, ou vide pour une revue complète]'
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git branch:*), Bash(git tag:*), Bash(find:*), Bash(cat:*), Bash(wc:*)
context: fork
agent: agent
---

## Périmètre d'analyse

"$ARGUMENTS"

## Objectif

Produire une revue complète d'un codebase découvert pour la première fois : comprendre ce que fait le projet, évaluer la qualité du code, identifier les fonctionnalités implémentées, repérer les problèmes et formuler des recommandations actionnables.

## Processus

### 1. Orientation initiale

**a. Structure du dépôt**

```bash
find . -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' | sort
```

**b. Fichiers d'entrée et de configuration**

- Lis `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` si présents
- Lis les fichiers de config racine : `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`, `docker-compose.yml`, etc.
- Lis les configs de build/CI : `.github/workflows/`, `Dockerfile`, `.env.example`

**c. Historique Git**

```bash
rtk git log --oneline -30
rtk git branch -a
git tag --sort=-creatordate | head -10
```

**d. Métriques brutes**

```bash
# Nombre de fichiers par type
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20

# Volume de code
wc -l $(find . -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null) 2>/dev/null | tail -1
```

### 2. Compréhension du projet

**a. But et domaine**

- Quel problème le projet résout-il ?
- Qui sont les utilisateurs cibles ?
- Quel est le modèle de données principal ?

**b. Architecture générale**

- Identifie le pattern architectural (MVC, hexagonal, microservices, monolithe, etc.)
- Cartographie les modules/packages principaux et leurs responsabilités
- Identifie les points d'entrée (main, index, app, server, etc.)
- Identifie les dépendances externes majeures et leur rôle

**c. Stack technique**

- Langage(s) et version(s)
- Framework(s) principaux
- Base de données / stockage
- Infrastructure / déploiement
- Outils de build, de test, de lint

### 3. Inventaire des fonctionnalités

Pour chaque module/répertoire significatif, identifie :

**a. Fonctionnalités implémentées et opérationnelles**

- Features complètes avec code, tests, et documentation
- Endpoints / commandes / interfaces exposés

**b. Fonctionnalités partiellement implémentées**

- Code présent mais incomplet (TODO, FIXME, stubs, placeholders)
- Features mentionnées dans le README mais absentes du code
- Branches de code jamais atteintes

**c. Fonctionnalités manquantes ou abandonnées**

- Code commenté
- Fichiers vides ou squelettes
- Références à des modules inexistants

### 4. Qualité du code

**a. Lisibilité et conventions**

- Les noms (variables, fonctions, modules) sont-ils explicites ?
- Le style est-il cohérent dans tout le projet ?
- Y a-t-il un linter/formateur configuré et utilisé ?
- Les conventions du langage sont-elles respectées ?

**b. Architecture et design**

- Le code respecte-t-il le principe de responsabilité unique ?
- Y a-t-il du couplage fort ou des dépendances circulaires ?
- Les abstractions sont-elles au bon niveau ?
- Y a-t-il de la duplication de code significative ?

**c. Robustesse**

- La gestion d'erreurs est-elle cohérente et complète ?
- Les cas limites sont-ils pris en compte ?
- Y a-t-il des magic numbers ou des valeurs hardcodées ?
- Les entrées externes (API, utilisateurs, fichiers) sont-elles validées ?

**d. Sécurité**

- Secrets ou credentials exposés dans le code ou l'historique Git
- Injections potentielles (SQL, commandes shell, XSS)
- Authentification / autorisation correctement implémentées
- Dépendances avec des vulnérabilités connues

**e. Performance**

- Algorithmes avec complexité problématique
- Requêtes N+1 ou appels réseau dans des boucles
- Absence de cache là où ce serait pertinent
- Fuites mémoire potentielles

**f. Tests**

- Présence et localisation des tests
- Types de tests (unitaires, intégration, e2e)
- Couverture estimée
- Qualité des assertions (trop permissives, cas triviaux)
- Tests flaky ou ignorés

**g. Documentation**

- README : présent, à jour, utile ?
- Commentaires : absents, redondants, ou véritablement explicatifs ?
- Documentation d'API ou de configuration
- Exemples d'utilisation

### 5. Identification des problèmes

Classe chaque problème trouvé par sévérité :

**🔴 Critique**

- Bugs fonctionnels avérés (logique incorrecte, crash probable)
- Vulnérabilités de sécurité
- Perte de données possible
- Le projet ne peut pas démarrer ou fonctionner

**🟡 Modéré**

- Dette technique bloquante pour l'évolution
- Absence de tests sur des chemins critiques
- Gestion d'erreurs manquante sur des opérations risquées
- Couplage fort rendant les modifications dangereuses

**🟢 Mineur**

- Conventions non respectées
- Documentation lacunaire
- Code mort ou commenté
- Opportunités d'amélioration cosmétiques

### 6. Points forts

Identifie et valorise ce qui est bien fait :

- Patterns élégants et idiomatiques
- Architecture bien pensée
- Tests complets et pertinents
- Documentation claire
- Gestion d'erreurs robuste
- Sécurité prise en compte

## Format du rapport

```markdown
# Revue de codebase : [Nom du projet]

## Vue d'ensemble

**But** : [Ce que fait le projet en 1-2 phrases]
**Domaine** : [Ex: API REST, CLI, bibliothèque, application web, etc.]
**Stack** : [Langage, framework, BDD, infra]
**Maturité estimée** : [Prototype / En développement / Stable / Maintenu activement]

---

## Architecture

[Description de l'organisation du code, des modules principaux et de leurs interactions]

### Modules principaux

| Module      | Responsabilité       | Qualité estimée |
| ----------- | -------------------- | --------------- |
| `src/auth/` | Authentification JWT | ✅ Bonne        |
| `src/api/`  | Endpoints REST       | ⚠️ Incomplète   |
| `src/db/`   | Accès données        | ✅ Bonne        |

---

## Fonctionnalités

### Implémentées et opérationnelles

- ✅ **[Feature A]** : [Description, où c'est dans le code]
- ✅ **[Feature B]** : [Description]

### Partiellement implémentées

- ⚠️ **[Feature C]** : [Ce qui manque, `fichier.ts:42` — TODO présent]
- ⚠️ **[Feature D]** : [Stub sans implémentation]

### Absentes ou abandonnées

- ❌ **[Feature E]** : Mentionnée dans le README, aucun code trouvé
- ❌ **[Feature F]** : Code commenté dans `legacy/old.ts`

---

## Points forts

### Architecture et design

- ✅ **[Point fort]** : [Pourquoi c'est bien]

### Qualité du code

- ✅ **[Point fort]** : [Pourquoi c'est bien]

### Tests

- ✅ **[Point fort]** : [Pourquoi c'est bien]

---

## Problèmes identifiés

### 🔴 Critiques

1. **[Problème]**
   - **Où** : `src/auth/middleware.ts:87`
   - **Impact** : [Conséquence concrète]
   - **Suggestion** : [Correction recommandée]

### 🟡 Modérés

1. **[Problème]**
   - **Où** : [Fichier:ligne]
   - **Impact** : [Conséquence]
   - **Suggestion** : [Correction]

### 🟢 Mineurs

1. **[Problème]** — `[fichier:ligne]` — [Correction rapide]

---

## Qualité globale

| Dimension      | Note      | Commentaire   |
| -------------- | --------- | ------------- |
| Lisibilité     | ⭐⭐⭐⭐☆ | [Commentaire] |
| Architecture   | ⭐⭐⭐☆☆  | [Commentaire] |
| Tests          | ⭐⭐☆☆☆   | [Commentaire] |
| Sécurité       | ⭐⭐⭐⭐☆ | [Commentaire] |
| Documentation  | ⭐⭐⭐☆☆  | [Commentaire] |
| Maintenabilité | ⭐⭐⭐☆☆  | [Commentaire] |

---

## Recommandations

### Priorité haute (à faire avant tout développement)

- [ ] [Action concrète] — `[fichier]`
- [ ] [Action concrète]

### Priorité moyenne (à planifier)

- [ ] [Action concrète]
- [ ] [Action concrète]

### Priorité basse (améliorations continues)

- [ ] [Action concrète]
- [ ] [Action concrète]

---

## Metriques

| Métrique                | Valeur |
| ----------------------- | ------ |
| Fichiers source         | N      |
| Lignes de code (estimé) | N      |
| Fichiers de test        | N      |
| Dépendances directes    | N      |
| Commits                 | N      |
| Contributeurs           | N      |
```
