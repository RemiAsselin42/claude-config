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
//     mypy.ini, arch-gates.json, .github/workflows/*), to baselines (*-baseline.json,
//     .dependency-cruiser-known-violations.json) and, in pyproject.toml, to the
//     [tool.ruff*] [tool.mypy*] [tool.mutmut*] [tool.pytest*] sections only —
//     [project] and [dependency-groups] stay editable;
//   - shell commands that skip or regenerate a gate (git commit --no-verify,
//     --update-baseline, lint:arch:baseline), that merge or label a PR (gh pr
//     merge, gh pr edit --add-label, the REST endpoints behind them), or that
//     write one of the files above from the shell (>, sed -i, tee, cp, mv, rm,
//     Set-Content, Out-File, Add-Content, Copy-Item, Move-Item, Remove-Item);
//   - git merge and any push that lands on main/master (explicit refspec, HEAD,
//     --all/--mirror, or a bare push from main), unless the latest message the
//     human typed is /create-commit (see typedCreateCommit);
//   - the harness itself: ~/.claude/settings.json, ~/.claude/hooks/*, any
//     .claude/settings*.json, and the session transcripts that carry the
//     /create-commit marker. These stay blocked even with PROTECT_GATES=off.
//
// PROTECT_GATES=off (set by the human owner for one session) lets everything else through
// and shows a visible warning each time a call would have been blocked.
// The pattern list is deliberately short: this hook is a speed bump, the CI
// workflow baseline-ratchet is what actually holds.
"use strict";
const fs = require("node:fs");
const { spawnSync } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");

const GATE_BASENAMES = [
  /^\.dependency-cruiser/, // .dependency-cruiser.cjs|.js|.json and the known-violations baseline
  /^eslint\.config\./,
  /^\.?ruff\.toml$/,
  /^mypy\.ini$/,
  /^arch-gates\.json$/, // layer declarations read by gates/python/check_imports.py
  /-baseline\.json$/,
  /^pyproject\.toml$/, // content-aware for Edit/Write (see pyprojectDecision), whole-file for shell writes
];
const GATE_PATHS = [/\/\.github\/workflows\/[^/]+$/];
const SELF_PATHS = [/\/\.claude\/settings(\.local)?\.json$/, /\/\.claude\/hooks\//, /\/\.claude\/projects\/.*\.jsonl$/];
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
  // lowercased: Windows paths are case-insensitive, so ARCH-GATES.JSON is the same file
  const n = String(p).replace(/\\/g, "/").toLowerCase();
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

// Merging and pushing to main are the human's gesture: allowed only inside a
// /create-commit they typed. Feature-branch pushes (what /create-pr does) stay free.
const PROTECTED_BRANCH = /^(main|master)$/;
const GIT_GLOBAL_WITH_VALUE = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"]);
const PUSH_OPT_WITH_VALUE = new Set(["-o", "--push-option", "--repo", "--receive-pack", "--exec"]);
// Walks the command segment by segment so a "cd" or "git -C" moves the directory whose
// branch a bare push is checked against, and a "git switch main" earlier in the chain counts.
// ponytail: quoted ";" or "&&" split a segment; a fancier shell parse if that ever matters.
function humanOnlyGit(cmd, cwd) {
  let dir = cwd || process.cwd();
  const switchedTo = new Map(); // dir -> main|master after "git switch main" in this command
  for (const seg of cmd.split(/&&|\|\||[;|\n]/)) {
    const t = (seg.match(/"[^"]*"|'[^']*'|\S+/g) || []).map((a) => a.replace(/^["']|["']$/g, ""));
    if (/^(cd|Set-Location|sl|pushd)$/i.test(t[0] || "")) { dir = t[1] ? resolveDir(dir, t[1]) : null; continue; }
    let i = t.findIndex((a) => /(^|[\\/])git(\.exe)?$/i.test(a));
    if (i < 0) continue;
    let repo = dir;
    for (i++; i < t.length && t[i].startsWith("-"); i++) {
      if (!GIT_GLOBAL_WITH_VALUE.has(t[i])) continue; // --no-pager, --git-dir=x, -c=… forms carry no separate value
      if (t[i] === "-C") repo = repo && t[i + 1] ? resolveDir(repo, t[i + 1]) : null;
      i++;
    }
    const [sub, ...args] = t.slice(i);
    if (sub === "merge") return "git merge";
    if ((sub === "switch" || sub === "checkout") && PROTECTED_BRANCH.test(args[args.length - 1] || "")) switchedTo.set(repo, args[args.length - 1]);
    if (sub !== "push") continue;
    const positional = [];
    let tags = false;
    for (let k = 0; k < args.length; k++) {
      const a = args[k];
      if (/^--(all|mirror)$/.test(a)) return "git push --all/--mirror reaches main";
      if (a === "--tags") tags = true;
      else if (PUSH_OPT_WITH_VALUE.has(a)) k++;
      else if (!a.startsWith("-")) positional.push(a);
    }
    const refs = positional.slice(1); // first positional is the remote
    if (!refs.length && tags) continue; // --tags alone pushes refs/tags/* only
    for (const ref of refs.length ? refs : ["HEAD"]) {
      let dest = ref.split(":").pop().replace(/^\+/, "").replace(/^refs\/heads\//, "");
      if (dest === "HEAD") dest = repo === null ? "main" : switchedTo.get(repo) || currentBranch(repo); // an unresolvable directory is not trusted
      if (PROTECTED_BRANCH.test(dest)) return `git push to ${dest}`;
    }
  }
  return null;
}
// A directory from the command line, as Git Bash or PowerShell spell it; null when it does not exist.
function resolveDir(from, p) {
  if (/^~([\\/]|$)/.test(p)) p = os.homedir() + p.slice(1);
  if (process.platform === "win32") p = p.replace(/^\/([a-z])(\/|$)/i, "$1:/"); // MSYS /c/Users -> c:/Users
  const d = path.resolve(from, p);
  return fs.existsSync(d) ? d : null;
}
function currentBranch(cwd) {
  const r = spawnSync("git", ["branch", "--show-current"], { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}
// The latest turn the human typed (origin.kind "human"; tool results, and so the
// answers to Claude's own questions, carry no origin) invoked /create-commit.
// create-commit.md sets disable-model-invocation, so Claude cannot start it itself.
function typedCreateCommit(transcriptPath) {
  let lines;
  try { lines = fs.readFileSync(transcriptPath, "utf8").trimEnd().split("\n"); } catch { return false; }
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try { e = JSON.parse(lines[i]); } catch { continue; }
    if (e.type !== "user" || e.origin?.kind !== "human") continue;
    const c = e.message?.content;
    const text = typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => x.text || "").join("") : "";
    return text.includes("<command-name>/create-commit</command-name>");
  }
  return false;
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
  if (/^(Bash|PowerShell)$/.test(tool)) {
    const cmd = String(ti.command || "");
    d = shellDecision(cmd);
    const git = !d && humanOnlyGit(cmd, input.cwd);
    if (git && !typedCreateCommit(input.transcript_path)) d = { why: `${git}: merging and pushing to main are the human's gesture, through a /create-commit they type` };
  }
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
