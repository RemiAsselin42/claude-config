#!/usr/bin/env node
// protect-gates.js — PreToolUse hook: Claude does not touch the quality gates.
//
// Registered in settings.json on Bash|PowerShell and on Edit|Write|MultiEdit|
// NotebookEdit. Exit 2 blocks the tool call and feeds the stderr text back to
// Claude; exit 0 lets the call through. Node only, no dependency: one hook for
// every platform instead of a .sh/.ps1 pair.
//
// Blocked:
//   - edits to gate configs (.dependency-cruiser.*, eslint.config.*, ruff.toml,
//     mypy.ini, .github/workflows/*), to baselines (*-baseline.json,
//     .dependency-cruiser-known-violations.json) and, in pyproject.toml, to the
//     [tool.ruff*] [tool.mypy*] [tool.mutmut*] [tool.pytest*] sections only —
//     [project] and [dependency-groups] stay editable;
//   - shell commands that skip or regenerate a gate (git commit --no-verify,
//     --update-baseline, lint:arch:baseline), that merge or label a PR (gh pr
//     merge, gh pr edit --add-label, the REST endpoints behind them), or that
//     write one of the files above from the shell (>, sed -i, tee, cp, mv, rm,
//     Set-Content, Out-File, Add-Content, Copy-Item, Move-Item, Remove-Item);
//   - the harness itself: ~/.claude/settings.json, ~/.claude/hooks/*, any
//     .claude/settings*.json. These stay blocked even with PROTECT_GATES=off.
//
// PROTECT_GATES=off (set by the human owner for one session) lets everything else through
// and shows a visible warning each time a call would have been blocked.
// The pattern list is deliberately short: this hook is a speed bump, the CI
// workflow baseline-ratchet is what actually holds.
"use strict";
const fs = require("node:fs");

const GATE_BASENAMES = [
  /^\.dependency-cruiser/, // .dependency-cruiser.cjs|.js|.json and the known-violations baseline
  /^eslint\.config\./,
  /^\.?ruff\.toml$/,
  /^mypy\.ini$/,
  /-baseline\.json$/,
  /^pyproject\.toml$/, // content-aware for Edit/Write (see pyprojectDecision), whole-file for shell writes
];
const GATE_PATHS = [/\/\.github\/workflows\/[^/]+$/];
const SELF_PATHS = [/\/\.claude\/settings(\.local)?\.json$/, /\/\.claude\/hooks\//];
const TOOL_SECTION = /^\[\[?tool\.(ruff|mypy|mutmut|pytest)\b/; // [tool.x] and [[tool.x.y]] array tables alike

const SHELL_RULES = [
  [/\bgit\b[^;&|]*\bcommit\b[^;&|]*\s(--no-verify|-n)(\s|$)/, "git commit --no-verify skips the pre-commit gates"],
  [/--update-baseline\b/, "--update-baseline rewrites a gate baseline"],
  [/\blint:arch:baseline\b/, "lint:arch:baseline rewrites the dependency-cruiser baseline"],
  [/\bgh\s+pr\s+merge\b/, "gh pr merge: merging is a human gesture, not Claude's"],
  [/\/pulls\/\d+\/merge\b/, "PR merge endpoint: merging is a human gesture, not Claude's"],
  [/\bgh\s+(pr|issue)\s+edit\b[^;&|]*--add-label/, "gh pr edit --add-label: PR labels are set by a human"],
  [/\/(issues|pulls)\/\d+\/labels\b/, "PR labels endpoint: PR labels are set by a human"],
];
const WRITE_CMD = /(^|[\s;&|(])(tee|cp|mv|rm|Set-Content|Out-File|Add-Content|Copy-Item|Move-Item|Remove-Item|New-Item)(\s|$)/i;
const SED_INPLACE = /(^|[\s;&|(])sed\s+(\S+\s+)*?(-\w*i\b|--in-place)/;
const REDIRECT = />{1,2}\s*["']?([^\s"'<>|;&]+)/g;

// "self" = the harness (never editable through Claude), "gate" = config or baseline.
function classify(p) {
  const n = String(p).replace(/\\/g, "/");
  if (SELF_PATHS.some((r) => r.test("/" + n))) return "self"; // "/" + n: a relative .claude/settings.json matches too
  const base = n.split("/").pop();
  if (GATE_BASENAMES.some((r) => r.test(base)) || GATE_PATHS.some((r) => r.test("/" + n))) return "gate";
  return null;
}

function shellDecision(cmd) {
  const tokens = cmd.split(/[\s"'`;|&<>()]+/).filter(Boolean);
  const targets = tokens.filter(classify);
  const writes = WRITE_CMD.test(cmd) || SED_INPLACE.test(cmd) || [...cmd.matchAll(REDIRECT)].some((m) => classify(m[1]));
  // reading a protected file is fine; a write to the harness itself is hard and wins over any soft rule below
  const write = targets.length && writes ? { why: `shell write to ${targets.join(", ")}`, hard: targets.some((t) => classify(t) === "self") } : null;
  if (write && write.hard) return write;
  for (const [re, why] of SHELL_RULES) if (re.test(cmd)) return { why };
  return write;
}

function fileDecision(tool, input) {
  const p = input.file_path || input.notebook_path;
  if (!p) return null;
  const kind = classify(p);
  if (kind === "self") return { why: `${p} is part of the harness itself`, hard: true };
  if (kind !== "gate") return null;
  if (/pyproject\.toml$/.test(p.replace(/\\/g, "/"))) return pyprojectDecision(tool, input, p);
  return { why: `${p} is a gate config or baseline` };
}

// Only the [tool.*] sections of the gates are frozen; compare them before/after.
function pyprojectDecision(tool, input, p) {
  let before = "";
  try { before = fs.readFileSync(p, "utf8"); } catch { /* new file: before stays empty */ }
  let after;
  if (tool === "Write") after = input.content ?? "";
  else if (tool === "Edit") after = applyEdit(before, input);
  else if (tool === "MultiEdit") after = (input.edits || []).reduce(applyEdit, before);
  else return null;
  if (after === null) return null; // old_string not found: the tool fails on its own
  return toolSections(before) === toolSections(after) ? null : { why: `${p}: a [tool.ruff|mypy|mutmut|pytest] section changed` };
}
function applyEdit(text, e) {
  if (text === null || !e.old_string || !text.includes(e.old_string)) return null;
  const repl = e.new_string ?? "";
  return e.replace_all ? text.split(e.old_string).join(repl) : text.replace(e.old_string, () => repl);
}
function toolSections(text) {
  const kept = [];
  let inside = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("[")) inside = TOOL_SECTION.test(line);
    if (inside && line) kept.push(line);
  }
  return kept.join("\n");
}

function main() {
  const input = JSON.parse(fs.readFileSync(0, "utf8"));
  const tool = input.tool_name || "";
  const ti = input.tool_input || {};
  let d = null;
  if (/^(Bash|PowerShell)$/.test(tool)) d = shellDecision(String(ti.command || ""));
  else if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) d = fileDecision(tool, ti);
  if (!d) return 0;
  const off = /^(off|0|false)$/i.test(process.env.PROTECT_GATES || "");
  if (off && !d.hard) {
    process.stdout.write(JSON.stringify({ systemMessage: `protect-gates is OFF (PROTECT_GATES=off): would have blocked ${tool} — ${d.why}` }));
    return 0;
  }
  process.stderr.write(
    `protect-gates: BLOCKED ${tool} — ${d.why}.\n` +
      "Gate configs, baselines and CI workflows are changed by a human, never by Claude; the CI baseline-ratchet enforces it either way.\n" +
      (d.hard
        ? "This path is the harness itself and stays protected even with PROTECT_GATES=off.\n"
        : "Ask the repository owner to make the change, or to start the session with PROTECT_GATES=off.\n"),
  );
  return 2;
}

process.exit(main());
