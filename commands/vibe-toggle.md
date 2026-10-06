---
description: 'Turn VibeWise learning mode on or off for this project, or show its state.'
argument-hint: '[on|off|status]  — empty = status'
allowed-tools: Bash(bash *vibe-toggle*)
---

# Vibe Toggle

Arguments: $ARGUMENTS

Run the switch and report its output:

```bash
bash ~/.claude/scripts/vibe-toggle.sh $ARGUMENTS
```

- No argument → `status`: `on` (with the checkpoint frequency), `off` (paused) or `none` (this project has no learning notes).
- `off` — pause learning mode for this project.
- `on` — resume it.

The mode belongs to the project, not to the machine: the vibe-wise plugin keeps it as the `Learning mode:` line of the project's `.vibe-wise/profile.md`. The script rewrites that line and the statusline reads it (`VibeWise │ On · Normal`, `VibeWise │ Off`, no line without notes).

After `off`, stop the learning loop (checkpoints, questions before coding) for the rest of this session.

After `on`, tell the user the plugin restores learning mode at the **next session start, `/clear` or compaction**, and that typing `/vibe-wise:learn` starts it now.

On `none`, tell the user to type `/vibe-wise:learn`: the first activation in a project is the plugin's own onboarding, which only they can start.
