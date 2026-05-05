---
description: 'Analyse les commentaires du code : présence, pertinence, qualité, langue et dette technique.'
argument-hint: '[répertoire ou fichier spécifique, ou vide pour analyser tout le projet]'
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(wc:*), Bash(git log:*)
context: fork
agent: agent
---

## Périmètre d'analyse

"$ARGUMENTS"

## Objectif

Produire un audit complet des commentaires du projet : leur présence, leur utilité réelle, leur qualité rédactionnelle, les langues utilisées, la dette documentée (TODO/FIXME) et le code mort masqué par des commentaires. Cette analyse ne juge pas la logique du code, uniquement ce qui est écrit _à propos_ du code.

## Processus

### 0. Collecte du périmètre

```bash
# Fichiers source à analyser
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \) \
  | sort

# Volume total de lignes
find . -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" \) \
  -exec wc -l {} \; 2>/dev/null | tail -1
```

Si `$ARGUMENTS` est fourni, restreins l'analyse à ce chemin.

---

### 1. Présence et densité des commentaires

**a. Ratio global commentaires / code**

```bash
# Lignes de commentaires (// et #)
grep -rn "^\s*//" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
grep -rn "^\s*#" src/ --include="*.py" 2>/dev/null | wc -l

# Blocs de commentaires /* ... */
grep -rn "^\s*/\*" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l

# Total de lignes de code source (hors commentaires et lignes vides)
grep -rn "^\s*[^/# \t]" src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
```

**b. Distribution par fichier**

Pour chaque fichier, calcule le ratio commentaires/code. Identifie :

- Fichiers **sur-commentés** (> 40% de commentaires, souvent du code mort ou redondance)
- Fichiers **sous-commentés** (0% de commentaires malgré une complexité visible)

```bash
# Fichiers sans aucune ligne de commentaire
for f in $(find src/ -name "*.ts" -not -name "*.d.ts" 2>/dev/null); do
  count=$(grep -c "^\s*//" "$f" 2>/dev/null || echo 0)
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ] && [ "$lines" -gt 30 ]; then
    echo "$lines lignes, 0 commentaire : $f"
  fi
done
```

**c. Zones silencieuses critiques**

Lors de la lecture des fichiers, note les fonctions > 20 lignes sans aucun commentaire ET dont la logique n'est pas triviale. Ce sont des candidats prioritaires à documenter.

---

### 2. Pertinence et utilité

Pour un échantillon représentatif de commentaires (lire les fichiers les plus commentés), classe chaque commentaire dans une catégorie :

| Catégorie     | Définition                                                  | Exemple                                                                     |
| ------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Utile**     | Explique le _pourquoi_, un choix non-évident, un workaround | `// On désactive le cache ici car l'API tiers renvoie des données périmées` |
| **Redondant** | Paraphrase ce que le code dit déjà                          | `// Incrémente le compteur` devant `counter++`                              |
| **Obsolète**  | Référence à du code supprimé, ticket fermé, API inexistante | `// cf. issue #234` alors que le ticket n'existe plus                       |
| **Trompeur**  | Contredit ce que le code fait réellement                    | `// Retourne null si erreur` alors que la fonction throw                    |

```bash
# Chercher des indicateurs de commentaires obsolètes
grep -rn "TODO\|FIXME\|deprecated\|old\|legacy\|remove\|dead\|unused" src/ \
  --include="*.ts" --include="*.js" -i 2>/dev/null | grep "//" | head -30

# Chercher les commentaires d'une seule ligne très courts (potentiellement redondants)
grep -rn "^\s*//.\{1,15\}$" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -30
```

Lors de la lecture des fichiers, évalue manuellement la pertinence des commentaires trouvés.

---

### 3. Qualité rédactionnelle

**a. Style et cohérence**

```bash
# Proportion //  vs /* */ vs /** */ (JSDoc)
echo "// inline :" && grep -rn "^\s*//" src/ --include="*.ts" 2>/dev/null | grep -v "^\s*///" | wc -l
echo "/** JSDoc :" && grep -rn "^\s*/\*\*" src/ --include="*.ts" 2>/dev/null | wc -l
echo "/* bloc   :" && grep -rn "^\s*/\*[^*]" src/ --include="*.ts" 2>/dev/null | wc -l
```

Détecte les incohérences : même type d'élément (fonction utilitaire) documenté avec `//` dans un fichier et `/** */` dans un autre.

**b. Qualité des notes rapides**

```bash
# Commentaires vagues d'une ligne (signaux de mauvaise qualité)
grep -rn "^\s*// \(fix\|temp\|old\|test\|todo\|hack\|wip\|remove\|check\|wtf\|idk\|????\|!!!\)" \
  src/ --include="*.ts" --include="*.js" -i 2>/dev/null | head -30
```

**c. Complétude de la documentation formelle (JSDoc/TSDoc)**

```bash
# Fonctions/méthodes exportées sans JSDoc
grep -rn "^export function\|^export const.*=.*(" src/ --include="*.ts" 2>/dev/null | head -40
```

Pour chaque fonction/classe publique exportée, vérifie si elle est précédée d'un bloc `/** */`. Évalue la complétude :

- `@param` présent pour chaque paramètre ?
- `@returns` présent si la fonction retourne une valeur non-triviale ?
- `@throws` présent si la fonction peut lever une exception ?
- `@example` présent pour les utilitaires complexes ?

---

### 4. Langue(s) utilisée(s)

**a. Détection des langues**

Analyse les commentaires textuels pour identifier la ou les langues utilisées. Patterns indicatifs :

```bash
# Mots français courants dans les commentaires
grep -rn "//.*\b\(le\|la\|les\|de\|du\|des\|et\|est\|un\|une\|pour\|avec\|sur\|dans\|par\|qui\|que\)\b" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l

# Mots anglais courants dans les commentaires
grep -rn "//.*\b\(the\|this\|that\|with\|from\|when\|where\|should\|return\|handle\|check\|get\|set\)\b" \
  src/ --include="*.ts" --include="*.js" 2>/dev/null | wc -l
```

**b. Fichiers multilingues**

Lors de la lecture des fichiers, identifie ceux qui contiennent des commentaires dans plusieurs langues différentes — c'est souvent le signe de contributions de développeurs différents sans convention établie.

**c. Inventaire et recommandation**

Produis un tableau :

| Langue   | Estimé (%) | Fichiers principaux           |
| -------- | ---------- | ----------------------------- |
| Anglais  | X%         | `src/api/...`, `src/core/...` |
| Français | Y%         | `src/services/...`            |
| Autre    | Z%         |                               |

Propose la langue cible de normalisation en tenant compte de la proportion actuelle et du contexte du projet (équipe, public cible de la doc).

---

### 5. TODOs / FIXMEs / HACKs (dette documentée)

**a. Inventaire exhaustif**

```bash
# Tous les marqueurs de dette
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|TEMP\|NOTE:" \
  src/ --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --include="*.py" --include="*.go" 2>/dev/null | grep -v node_modules | sort
```

**b. Datation via Git**

Pour les marqueurs critiques (`FIXME`, `BUG`, `HACK`), tente d'estimer leur ancienneté :

```bash
# Date du dernier commit ayant touché ces lignes (nécessite git)
rtk git log --all -p --follow -- src/ | grep -A2 "FIXME\|BUG\|HACK" | head -40
```

**c. Classification par criticité**

| Niveau      | Marqueurs               | Action suggérée                  |
| ----------- | ----------------------- | -------------------------------- |
| 🔴 Critique | `FIXME`, `BUG`          | Traiter avant tout merge en prod |
| 🟡 Modéré   | `HACK`, `XXX`           | Planifier dans le backlog        |
| 🟢 Mineur   | `TODO`, `NOTE:`, `TEMP` | À faire mais non bloquant        |

---

### 6. Code commenté (dead code masqué)

**a. Détection de blocs de code commenté**

```bash
# Blocs de plusieurs lignes consécutives commentées avec du code (présence de ; ou () ou = )
grep -rn "^\s*//.*[;(){}\[\]=]" src/ --include="*.ts" --include="*.js" 2>/dev/null | head -40

# Même chose pour Python
grep -rn "^\s*#.*[()=:\[\]]" src/ --include="*.py" 2>/dev/null | head -20
```

Lors de la lecture des fichiers, identifie les blocs de code commenté (lignes consécutives commençant par `//` ou `#` qui contiennent de la syntaxe de code, pas du texte).

**b. Classification par taille**

- **🔴 > 10 lignes** : Suppression fortement recommandée — git history conserve le code
- **🟡 3-10 lignes** : Supprimer ou convertir en test désactivé (`it.skip`)
- **🟢 1-2 lignes** : Surveiller, souvent un debug temporaire oublié

---

## Format du rapport

```markdown
# Rapport d'analyse des commentaires

## Tableau de bord

| Dimension              | Score     | Résumé   |
| ---------------------- | --------- | -------- |
| Présence et densité    | ⭐⭐⭐☆☆  | [résumé] |
| Pertinence et utilité  | ⭐⭐⭐⭐☆ | [résumé] |
| Qualité rédactionnelle | ⭐⭐☆☆☆   | [résumé] |
| Cohérence des langues  | ⭐⭐⭐☆☆  | [résumé] |
| Dette (TODOs/FIXMEs)   | ⭐⭐⭐☆☆  | [résumé] |
| Code commenté          | ⭐⭐⭐⭐☆ | [résumé] |

**Score global** : XX/30

---

## 1. Présence et densité

**Ratio global** : ~X% des lignes sont des commentaires

### Zones sous-documentées (fichiers complexes sans commentaires)

| Fichier              | Lignes | Commentaires | Complexité estimée |
| -------------------- | ------ | ------------ | ------------------ |
| `src/core/parser.ts` | 312    | 0            | Élevée             |

### Zones sur-commentées (> 40%)

| Fichier                 | Lignes | % Commentaires | Cause probable |
| ----------------------- | ------ | -------------- | -------------- |
| `src/legacy/old-api.ts` | 180    | 55%            | Code commenté  |

---

## 2. Pertinence et utilité

### Commentaires utiles (exemples notables)

- `src/auth/jwt.ts:34` — Explique pourquoi le token est vérifié deux fois (race condition connue)

### Commentaires redondants

- `src/utils/format.ts:12` — `// formate la date` devant `formatDate(date)` — à supprimer

### Commentaires obsolètes

- `src/api/user.ts:78` — Référence à `#issue-123` et à `OldUserAPI` qui n'existent plus

### Commentaires trompeurs

- `src/db/query.ts:45` — Indique `// retourne null si non trouvé` mais la fonction `throw` une erreur

---

## 3. Qualité rédactionnelle

**Style dominant** : `//` inline (X%), `/** JSDoc */` (Y%), `/* bloc */` (Z%)

### Incohérences de style

- `src/services/` : mélange `//` et `/** */` pour les mêmes types de fonctions

### Notes vagues identifiées

| Commentaire | Fichier                 | Problème                  |
| ----------- | ----------------------- | ------------------------- |
| `// fix`    | `src/api/handler.ts:23` | Aucun contexte            |
| `// temp`   | `src/cache/index.ts:67` | Depuis combien de temps ? |

### Couverture JSDoc des exports publics

- **Fonctions exportées avec JSDoc** : X / Y (Z%)
- **Sans @param** : N occurrences
- **Sans @returns** : N occurrences

---

## 4. Langue(s) utilisée(s)

| Langue   | Estimé | Fichiers                      |
| -------- | ------ | ----------------------------- |
| Anglais  | 65%    | `src/core/`, `src/api/`       |
| Français | 33%    | `src/services/`, `src/utils/` |
| Mixte    | 2%     | `src/legacy/`                 |

**Recommandation** : Normaliser en **[anglais / français]**
**Raison** : [langue majoritaire / langue de l'équipe / convention du projet]

### Fichiers multilingues à traiter en priorité

- `src/services/UserService.ts` — 12 commentaires FR, 8 commentaires EN dans le même fichier

---

## 5. TODOs / FIXMEs / HACKs

**Total** : N marqueurs (X critiques, Y modérés, Z mineurs)

### 🔴 Critiques (FIXME / BUG)

| Marqueur | Fichier                  | Contenu                                        | Âge estimé |
| -------- | ------------------------ | ---------------------------------------------- | ---------- |
| `FIXME`  | `src/auth/session.ts:34` | `// FIXME: session expire too early on mobile` | ~6 mois    |

### 🟡 Modérés (HACK / XXX)

| Marqueur | Fichier             | Contenu                                 |
| -------- | ------------------- | --------------------------------------- |
| `HACK`   | `src/db/pool.ts:12` | `// HACK: workaround for pg driver bug` |

### 🟢 Mineurs (TODO / NOTE)

- `src/utils/date.ts:56` — `// TODO: add timezone support`
- `src/api/routes.ts:23` — `// TODO: add rate limiting`

---

## 6. Code commenté

### 🔴 Blocs > 10 lignes (à supprimer)

- `src/legacy/old-api.ts:45-67` — 23 lignes de code commenté (`OldApiClient`)
  - Action : supprimer — le code est dans l'historique git

### 🟡 Blocs 3-10 lignes

- `src/utils/cache.ts:12-15` — 4 lignes d'implémentation alternative commentée

### 🟢 Lignes isolées

- `src/api/handler.ts:89` — `// console.log(response)` — debug oublié

---

## Plan d'action

### Priorité haute

- [ ] Traiter les N `FIXME`/`BUG` — voir section 5
- [ ] Supprimer les blocs de code commenté > 10 lignes — voir section 6
- [ ] Corriger les commentaires trompeurs — voir section 2

### Priorité moyenne

- [ ] Normaliser la langue vers [anglais/français] dans les fichiers multilingues
- [ ] Ajouter JSDoc sur les N fonctions publiques non documentées
- [ ] Supprimer ou compléter les notes vagues (`// fix`, `// temp`)

### Priorité basse

- [ ] Harmoniser le style de commentaires (`//` vs `/** */`)
- [ ] Traiter les TODO mineurs dans le backlog

---

## Métriques

| Métrique                                 | Valeur   |
| ---------------------------------------- | -------- |
| Fichiers analysés                        | N        |
| Ratio commentaires/code                  | X%       |
| Fichiers sans commentaires (> 30 lignes) | N        |
| TODOs/FIXMEs total                       | N        |
| Blocs de code commenté                   | N        |
| Langues détectées                        | [FR, EN] |
| Exports publics sans JSDoc               | N / M    |
```
