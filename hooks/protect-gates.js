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
//     a core.hooksPath set or passed with -c, HUSKY=0, --update-baseline,
//     lint:arch:baseline), that merge or label a PR (gh pr merge, gh pr edit
//     --add-label, the REST endpoints behind them), that post a commit status
//     (the /statuses/ endpoint), or that write one of the files above from the
//     shell (>, sed -i, tee, cp, mv, rm, Set-Content, Out-File, Add-Content,
//     Copy-Item, Move-Item, Remove-Item);
//   - git merge and any push that lands on main/master (explicit refspec, HEAD,
//     --all/--mirror, or a bare push from main), unless the latest message the
//     human typed is /create-commit (see typedCommand);
//   - any push that deletes a remote ref (--delete, -d, ":ref") or rewrites one
//     ("+ref"): release tags never move, and a remote branch is deleted by a
//     human; no exemption, the tag ruleset on GitHub refuses it either way;
//   - one exemption: while the latest message the human typed is /init-gates,
//     Claude may create one of the files that command creates (INIT_GATES_FILES)
//     when it does not exist yet (Write to an absent file, or a redirect to one,
//     resolved after any "cd"), and may add a [tool.mutmut] section to a
//     pyproject.toml that has none, the other tool sections untouched; changing
//     or deleting an existing one, or creating any other gate file, stays blocked;
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
  [/\bcore\.hookspath(\s*=|\s+\S)/i, "core.hooksPath moves the git hooks away from the pre-commit gates"], // -c, --config-env, git config, GIT_CONFIG_*; a read or --unset passes
  [/\bHUSKY\s*=\s*["']?0\b|\bHUSKY_SKIP_HOOKS\s*=\s*["']?1\b/i, "HUSKY=0 skips the husky pre-commit hooks"],
  [/\/statuses\/\S/, "commit status endpoint: a check result is posted by CI, never by hand"], // POST /repos/o/r/statuses/<sha>; GET is /commits/<sha>/statuses
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

// The only files /init-gates creates; any other absent gate file (a new workflow, ruff.toml...) stays blocked.
// mutation-baseline.json is not here on purpose: it comes from the PR's first CI run, never from Claude.
const INIT_GATES_FILES = /(^|\/)(arch-gates\.json|(import-cycles|import-layers|complexity|duplication)-baseline\.json|\.dependency-cruiser\.cjs|\.dependency-cruiser-known-violations\.json|\.github\/workflows\/(arch-gates|baseline-ratchet|mutation-gate|quality-gates)\.yml)$/;
const creatable = (p) => INIT_GATES_FILES.test(String(p).replace(/\\/g, "/").toLowerCase());

// Gate files a command redirects into, each with the directory its segment runs in
// (a preceding "cd" moves it; null once a "cd" cannot be resolved).
function redirectTargets(cmd, cwd) {
  let dir = cwd || process.cwd();
  const out = [];
  for (const seg of cmd.split(/&&|\|\||[;|\n]/)) {
    const cd = seg.trim().match(/^(?:cd|Set-Location|sl|pushd)(?:\s+("[^"]*"|'[^']*'|\S+))?/i);
    if (cd) { dir = dir && cd[1] ? resolveDir(dir, cd[1].replace(/^["']|["']$/g, "")) : null; continue; }
    for (const m of seg.matchAll(REDIRECT)) if (classify(m[1])) out.push({ target: m[1], dir });
  }
  return out;
}

function shellDecision(cmd, cwd) {
  const tokens = cmd.split(/[\s"'`;|&<>()]+/).filter(Boolean);
  const targets = tokens.filter(classify);
  const commandWrites = WRITE_CMD.test(cmd) || SED_INPLACE.test(cmd);
  const redirects = redirectTargets(cmd, cwd);
  const writes = commandWrites || redirects.length > 0;
  // reading a protected file is fine; a write to the harness itself is hard and wins over any soft rule below
  const write = targets.length && writes
    ? {
        why: `shell write to ${targets.join(", ")}`,
        hard: targets.some((t) => classify(t) === "self"),
        // only a redirect names its target for sure; it creates when every gate file it writes is absent
        create: !commandWrites && redirects.every(({ target, dir }) => dir !== null && creatable(target) && resolveDir(dir, target) === null),
      }
    : null;
  if (write && write.hard) return write;
  for (const [re, why] of SHELL_RULES) if (re.test(cmd)) return { why };
  return write;
}

// Merging and pushing to main are the human's gesture: allowed only inside a
// /create-commit they typed ({ human: true }). Feature-branch pushes (what /create-pr
// does) stay free. Deleting or rewriting a remote ref has no exemption at all.
const human = (what) => ({ why: `${what}: merging and pushing to main are the human's gesture, through a /create-commit they type`, human: true });
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
    if (sub === "merge") return human("git merge");
    if ((sub === "switch" || sub === "checkout") && PROTECTED_BRANCH.test(args[args.length - 1] || "")) switchedTo.set(repo, args[args.length - 1]);
    if (sub !== "push") continue;
    const positional = [];
    let tags = false;
    let del = false;
    for (let k = 0; k < args.length; k++) {
      const a = args[k];
      if (/^--(all|mirror)$/.test(a)) return human("git push --all/--mirror reaches main");
      if (a === "--tags") tags = true;
      else if (a === "--delete" || a === "-d") del = true;
      else if (PUSH_OPT_WITH_VALUE.has(a)) k++;
      else if (!a.startsWith("-")) positional.push(a);
    }
    const refs = positional.slice(1); // first positional is the remote
    if (!refs.length && tags) continue; // --tags alone pushes refs/tags/* only
    for (const ref of refs.length ? refs : ["HEAD"]) {
      let dest = ref.split(":").pop().replace(/^\+/, "").replace(/^refs\/heads\//, "");
      if (dest === "HEAD") dest = repo === null ? "main" : switchedTo.get(repo) || currentBranch(repo); // an unresolvable directory is not trusted
      if (PROTECTED_BRANCH.test(dest)) return human(`git push to ${dest}`);
      if (del || /^[+:]/.test(ref)) return { why: `git push ${del ? "--delete " : ""}${ref} deletes or rewrites a remote ref: release tags never move, and a remote branch is deleted by a human` };
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
// answers to Claude's own questions, carry no origin) invoked /<name>.
// create-commit.md and init-gates.md set disable-model-invocation, so Claude cannot start them itself.
function typedCommand(transcriptPath, name) {
  let lines;
  try { lines = fs.readFileSync(transcriptPath, "utf8").trimEnd().split("\n"); } catch { return false; }
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try { e = JSON.parse(lines[i]); } catch { continue; }
    if (e.type !== "user" || e.origin?.kind !== "human") continue;
    const c = e.message?.content;
    const text = typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => x.text || "").join("") : "";
    return text.includes(`<command-name>/${name}</command-name>`);
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
  return { why: `${p} is a gate config or baseline`, create: tool === "Write" && creatable(p) && !fs.existsSync(p) };
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
  if (toolSections(before) === toolSections(after)) return null;
  // A [tool.mutmut] section added to a file that has none is a creation, like an
  // absent gate file: /init-gates may do it (main checks the marker) as long as the
  // other gate sections read exactly as before. Changing an existing one never passes.
  const create = !hasSection(before, MUTMUT_SECTION) && hasSection(after, MUTMUT_SECTION) && toolSections(after, (l) => !MUTMUT_SECTION.test(l)) === toolSections(before);
  return { why: `${p}: a [tool.ruff|mypy|mutmut|pytest] section changed`, create };
}
const MUTMUT_SECTION = /^\[\[?tool\.mutmut\b/;
const hasSection = (text, re) => text.split(/\r?\n/).some((raw) => re.test(raw.trim()));
function applyEdit(text, e) {
  if (text === null || !e.old_string || !text.includes(e.old_string)) return null;
  const repl = e.new_string ?? "";
  return e.replace_all ? text.split(e.old_string).join(repl) : text.replace(e.old_string, () => repl);
}
function toolSections(text, also = () => true) {
  const kept = [];
  let inside = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("[")) inside = TOOL_SECTION.test(line) && also(line);
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
    d = shellDecision(cmd, input.cwd);
    const git = !d && humanOnlyGit(cmd, input.cwd);
    if (git && !(git.human && typedCommand(input.transcript_path, "create-commit"))) d = git;
  }
  else if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) d = fileDecision(tool, ti);
  // /init-gates may create the gate files a repo does not have yet; changing an existing one stays blocked
  if (d && d.create && !d.hard && typedCommand(input.transcript_path, "init-gates")) return 0;
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
