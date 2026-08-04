---
description: 'Switch the active terse mode: ponytail, caveman, or off — never both at once.'
argument-hint: '[ponytail|caveman|off|status] [level]  — empty = status'
allowed-tools: Bash(bash *style-toggle*)
---

# Style Toggle

Arguments: $ARGUMENTS

Run the switch and report its output:

```bash
bash ~/.claude/scripts/style-toggle.sh $ARGUMENTS
```

- No argument → `status`: show each plugin's session mode and persistent default.
- `ponytail [lite|full|ultra]` — enable ponytail, disable caveman.
- `caveman [lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra]` — enable caveman, disable ponytail.
- `off` — disable both.

The script writes each plugin's user config (`defaultMode`) for persistence and the session flag files for an immediate statusline update.

After a mode change, tell the user the new mode fully applies at the **next session** — the current session keeps the instructions its hooks injected at startup — and adopt the requested style yourself for the rest of this session as a best effort.
