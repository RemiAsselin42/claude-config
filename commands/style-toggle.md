---
description: 'Switch the ponytail terse mode on or off, or show its state.'
argument-hint: '[ponytail|off|status] [level]  — empty = status'
allowed-tools: Bash(bash *style-toggle*)
---

# Style Toggle

Arguments: $ARGUMENTS

Run the switch and report its output:

```bash
bash ~/.claude/scripts/style-toggle.sh $ARGUMENTS
```

- No argument → `status`: show ponytail's session mode and persistent default.
- `ponytail [lite|full|ultra]` — enable ponytail at that level (`full` by default).
- `off` — disable it.

The script writes the plugin's user config (`defaultMode`) for persistence and the session flag file for an immediate statusline update.

After a mode change, tell the user the new mode fully applies at the **next session** — the current session keeps the instructions its hooks injected at startup — and adopt the requested style yourself for the rest of this session as a best effort.
