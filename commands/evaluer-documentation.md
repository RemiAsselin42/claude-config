---
description: 'Vérifie la cohérence entre documentation et code.'
argument-hint: '[sections ou fichiers spécifiques à vérifier, ou vide pour tout auditer]'
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: agent
---

## Périmètre de vérification

"$ARGUMENTS"

## Objectif

Identifier les incohérences entre ce que la documentation dit et ce que le code fait réellement, puis proposer des corrections.

## Processus

### 1. Inventaire de la documentation

Liste tous les fichiers de documentation :

```bash
find . -type f -name "*.md" -o -name "*.mdx" -o -name "package.json" -o -name "CHANGELOG.md"
```

Sources à vérifier :

- `/README.md`
- `/docs/*.md`
- `src/*/README.md`
- Commentaires JSDoc
- `package.json` (scripts, description)
- `CHANGELOG.md`

### 2. Vérification par catégorie

**A. Features documentées vs implémentées**

- La feature existe-t-elle dans le code ?
- Les paramètres documentés correspondent-ils ?
- Le comportement décrit est-il correct ?

**B. API et signatures**

- Types documentés vs types réels
- Paramètres requis/optionnels
- Valeurs de retour
- Erreurs possibles

**C. Exemples de code**

- Les exemples sont-ils syntaxiquement corrects ?
- Utilisent-ils les bonnes APIs ?
- Fonctionnent-ils réellement ?

**D. Commandes et scripts**

- Les commandes `npm run` existent-elles ?
- Les options documentées sont-elles valides ?
- Les résultats attendus sont-ils corrects ?

**E. Configuration**

- Les fichiers de config mentionnés existent-ils ?
- Les options documentées sont-elles supportées ?
- Les valeurs par défaut sont-elles exactes ?

### 3. Identification des écarts

Pour chaque incohérence trouvée, note :

- **Type** : Feature manquante, exemple cassé, API changée, config obsolète
- **Sévérité** : 🔴 Critique (information fausse) | 🟡 Modérée (incomplet) | 🟢 Mineure (détail)
- **Localisation** : Fichier et ligne
- **Impact** : Qui est affecté (utilisateurs, contributeurs, déploiement)

### 4. Génération du rapport

Produis un rapport d'audit :

```markdown
# Audit Documentation vs Code

## Résumé

- **Fichiers vérifiés** : X docs, Y fichiers code
- **Écarts trouvés** : Z problèmes
- **Sévérité** : A critiques 🔴, B modérés 🟡, C mineurs 🟢

---

## 🔴 Écarts critiques

### 1. Section "scroll-manager" non documentée

- **Doc** : Aucune mention dans README.md
- **Code** : `src/core/scrollManager.ts` existe et fonctionnel
- **Impact** : Utilisateurs ne savent pas que la feature existe
- **Correction** : Ajouter section dans README.md avec usage

### 2. API `updateSection()` paramètres obsolètes

- **Doc** : `updateSection(section: SectionLifecycle)`
- **Code** : `updateSection(section: SectionLifecycle, options?: UpdateOptions)`
- **Impact** : Exemples ne compilent pas avec nouvelles options
- **Correction** : Mettre à jour JSDoc et README avec param options

---

## 🟡 Écarts modérés

### 3. Script npm run test manquant

- **Doc** : README mentionne `npm run test`
- **Code** : package.json a ce script
- **Impact** : Aucun - le script existe
- **Correction** : Aucune correction nécessaire

---

## 🟢 Écarts mineurs

### 4. Capture d'écran UI obsolète

- **Doc** : Screenshot montre ancien design
- **Code** : UI a été redesignée
- **Impact** : Confusion visuelle mineure
- **Correction** : Mettre à jour screenshot

---

## Actions recommandées

### Priorité 1 (Critique)

1. [ ] Documenter section scroll-manager dans README.md
2. [ ] Corriger signature updateSection() dans docs et JSDoc

### Priorité 2 (Modéré)

3. [ ] Ajouter script test ou retirer de doc
4. [ ] Vérifier tous les exemples de code compilent

### Priorité 3 (Mineur)

5. [ ] Mettre à jour captures d'écran UI
6. [ ] Harmoniser format des exemples

---

## Corrections proposées

### README.md

\`\`\`diff

- ## Scroll Manager
- Synchronise le scroll de la page avec les animations 3D.
-
- \`\`\`typescript
- import { ScrollManager } from './core/scrollManager';
- const manager = new ScrollManager({ smooth: true });
- \`\`\`
  \`\`\`

### src/core/scrollManager.ts

\`\`\`diff
/\*\*

- - - Synchronise une section avec le scroll
- - - @param section - La section à mettre à jour
- - - @param options - Options de mise à jour (optionnel)
- - - @param options.smooth - Activer le smooth scroll
      \*/
      \`\`\`
```

### 5. Validation

Après corrections, vérifie :

- ✅ Tous les exemples dans la doc compilent
- ✅ Toutes les commandes documentées fonctionnent
- ✅ Les captures d'écran correspondent à l'UI actuelle
- ✅ Les types documentés correspondent au code
- ✅ Aucune feature non documentée

## Checklist de vérification

### Documentation générale

- [ ] README.md reflète les features actuelles
- [ ] Table des matières à jour
- [ ] Badges (CI, coverage) corrects
- [ ] Installation/setup valide
- [ ] Exemples fonctionnent

### Documentation technique

- [ ] Architecture diagrams à jour
- [ ] API docs correspondent au code
- [ ] Types/interfaces documentés
- [ ] Guides de contribution valides

### Exemples de code

- [ ] Syntaxe correcte
- [ ] Imports valides
- [ ] APIs existantes utilisées
- [ ] Résultats attendus corrects

### Configuration

- [ ] Scripts npm documentés existent
- [ ] Options de config supportées
- [ ] Valeurs par défaut exactes
- [ ] Fichiers référencés existent

## Outils

- `Grep` : Trouver mentions et patterns dans le code
- `Read` : Examiner docs et code
- `Glob` : Lister les fichiers de documentation
- `Bash` : Tester commandes documentées

Fournis un audit complet et actionnable qui facilite la mise en conformité de la documentation avec le code réel.
