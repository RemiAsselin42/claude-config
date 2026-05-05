---
description: 'Analyse les modifications récentes et met à jour la documentation en conséquence.'
argument-hint: '[fichiers de documentation à mettre à jour, ou vide pour tout analyser]'
allowed-tools: Read, Edit, Bash, Grep, Glob
context: fork
agent: agent
---

## Fichiers ciblés

"$ARGUMENTS"

## Objectif

Mettre à jour la documentation pour refléter les modifications récentes du code, en assurant clarté et exactitude.

## Processus

### 1. Identifier les modifications

Collecte les changements récents :

```bash
rtk git diff --stat           # Fichiers modifiés
rtk git diff                  # Détails des changements
```

Identifie :

- Nouvelles fonctionnalités ajoutées
- Fonctions/APIs modifiées ou supprimées
- Changements de comportement
- Nouvelles dépendances ou configurations
- Modifications d'architecture

### 2. Localiser la documentation impactée

Trouve les docs à mettre à jour :

- `/README.md` : Vue d'ensemble du projet
- `/docs/*.md` : Documentation détaillée
- `src/features/*/README.md` : Docs par feature
- `/CHANGELOG.md` : Historique des versions
- `package.json` : Description et scripts
- Commentaires JSDoc dans le code

### 3. Analyser l'écart

Pour chaque modification, vérifie :

- ✅ La doc mentionne-t-elle cette fonctionnalité ?
- ✅ Les exemples de code sont-ils toujours valides ?
- ✅ Les paramètres/types sont-ils à jour ?
- ✅ Les commandes/usage sont-ils corrects ?
- ⚠️ Des sections sont-elles obsolètes ?

### 4. Mettre à jour

**README.md principal**

- Description des nouvelles features
- Mise à jour des exemples d'utilisation
- Ajout de nouvelles commandes
- Mise à jour des screenshots si UI changée

**README.md des features**

- Explication de la nouvelle logique
- Exemples de code actualisés
- Paramètres et options à jour
- Cas d'usage ajoutés/modifiés

**Documentation technique**

- Diagrammes d'architecture si changements structurels
- Documentation API si endpoints modifiés
- Guides de contribution si workflow changé

**CHANGELOG.md**

- Ajoute une entrée pour la version courante
- Liste les changements par catégorie (Added, Changed, Fixed, Removed)
- Utilise le format Keep a Changelog

### 5. Vérifier la qualité

Assure-toi que :

- ✅ Les exemples sont testables et fonctionnels
- ✅ Le langage est clair et accessible
- ✅ La structure est logique et facile à naviguer
- ✅ Les liens internes fonctionnent
- ✅ Les captures d'écran sont à jour
- ✅ La table des matières est correcte

### 6. Rapport de mise à jour

Fournis un résumé :

```markdown
## Documentation mise à jour

### Fichiers modifiés

- ✅ README.md : Ajout section scroll-manager
- ✅ docs/architecture.md : Mise à jour diagramme
- ✅ src/sections/01-hero/README.md : Création
- ✅ CHANGELOG.md : Entrée v1.2.0

### Changements documentés

1. ✅ Nouvelle feature scroll-manager avec exemples
2. ✅ API scrollManager.ts avec JSDoc complet
3. ✅ Commande npm run dev ajoutée
4. ✅ Section troubleshooting enrichie

### Vérifications

- ✅ Tous les exemples testés et fonctionnels
- ✅ Liens internes vérifiés
- ✅ Captures d'écran actualisées
- ✅ Format markdown valide
```

## Principes de rédaction

### ✅ Bonnes pratiques

- **Clarté** : Langage simple, exemples concrets
- **Précision** : Informations techniques exactes
- **Complétude** : Couvre tous les cas d'usage
- **Maintainabilité** : Structure facile à mettre à jour
- **Accessibilité** : Compréhensible pour tous les niveaux

## Template de documentation feature

```markdown
# Feature Name

## Description

[Une phrase décrivant la feature]

## Utilisation

\`\`\`typescript
// Exemple concret et fonctionnel
\`\`\`

## API

### `functionName(params)`

- **Params** : Description des paramètres
- **Returns** : Type de retour et description
- **Throws** : Erreurs possibles

## Configuration

[Options disponibles]

## Exemples

[Cas d'usage réels]

## Troubleshooting

[Problèmes courants et solutions]
```

## Outils

- `Read` : Lire la doc existante
- `Grep` : Trouver références à mettre à jour
- `Edit` : Modifier la documentation
- `Bash` : Tester les exemples

Produis une documentation claire, précise et à jour qui aide les utilisateurs à comprendre et utiliser efficacement le projet.
