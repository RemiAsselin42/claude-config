---
description: Analyse les retours de Copilot (review) sur une PR, juge chaque point (bonne pratique / manque de contexte / faux) avant d'appliquer
argument-hint: "[numéro(s) de PR]  — vide = PR de la branche courante"
allowed-tools: Bash(gh *), Bash(git *), Read, Grep, Glob, Edit
---

Tu analyses les retours de **GitHub Copilot** sur une Pull Request de ce repo, puis tu juges chaque point avant toute modification. Langue : **français**.

## 1. Cibler la PR

Argument fourni : `$ARGUMENTS`

- Si un numéro est fourni → c'est le numéro de PR (`N`).
- Si plusieurs numéros sont fournis (ex. après `/create-pr` qui a créé plusieurs PR) → traite chaque PR l'une après l'autre (étapes 2 à 4 pour chacune, restitution séparée par PR).
- Sinon → récupère la PR de la branche courante :
  `gh pr view --json number,title,headRefName`
  (si aucune PR n'existe pour la branche, arrête-toi et dis-le clairement.)

## 2. Récupérer les retours Copilot

Copilot écrit à la fois des **commentaires inline** (les plus utiles) et un **résumé de review**. Récupère les deux (`{owner}/{repo}` sont résolus automatiquement par `gh` dans le repo) :

Commentaires inline :
```
gh api repos/{owner}/{repo}/pulls/<N>/comments --paginate \
  -q '.[] | select(.user.login | test("copilot";"i")) | "[\(.path):\(.line // .original_line)]\n\(.body)\n---"'
```

Résumés de review :
```
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  -q '.[] | select(.user.login | test("copilot";"i")) | .body' 
```

S'il n'y a aucun retour Copilot : dis-le et arrête-toi (Copilot n'a peut-être pas encore terminé sa review).

## 3. Juger chaque point — NE JAMAIS appliquer aveuglément

Pour **chaque** remarque Copilot :

1. **Lis l'état ACTUEL du fichier** (`path:line`). Beaucoup de retours portent sur un état intermédiaire **déjà corrigé** par un commit/une PR ultérieure → marquer « déjà résolu ».
2. Confronte la remarque aux règles du projet (`CLAUDE.md`, `docs/`, DS strict, RLS/JWT, types stricts, métier moteur de règles).
3. **Copilot se trompe parfois** — il manque de contexte projet. Exemple réel : il a affirmé à tort que Zod v4 ne supporte pas `z.number({ error })` (c'est l'API v3). Donc classe, ne suis pas.
4. **Sceptique par défaut** : une remarque n'est classée ✅ que si tu peux la justifier toi-même après lecture du code — jamais parce que « Copilot l'a dit ». En cas de doute → ⚠️, pas ✅.

Classe chaque point :
- ✅ **Bonne pratique** — remarque valide, à appliquer.
- ⚠️ **Manque de contexte** — Copilot a raison « dans l'absolu » mais ignore une contrainte/convention projet qui justifie le code actuel → à laisser, avec la justification.
- ❌ **Faux** — Copilot se trompe techniquement → à ignorer, avec l'explication.
- 🔁 **Déjà résolu** — corrigé depuis le commit visé.

## 4. Restituer

Produis un tableau récap : `fichier:ligne` · remarque (résumée) · verdict · justification courte.

Puis : pour les points ✅ uniquement, propose les correctifs. **Demande validation avant d'éditer** (sauf si l'utilisateur a déjà dit d'appliquer directement). Travaille en PR / commits groupés par thème (cf. commande `/create-pr`), jamais de commit/push non demandé. Les correctifs validés s'appliquent en nouveaux commits sur la branche de la PR concernée.
