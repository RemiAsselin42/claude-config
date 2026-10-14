// Acceptance tests for scripts/test-ablation.cjs (spec: docs/audit-tests-ts.md) on a toy
// TypeScript project generated in os.tmpdir(): a git repo with node_modules ignored,
// vitest@5.0.4 and typescript@6.0.3 installed once by npm. The script is spawned with
// process.execPath, like baseline-ratchet; units are located by their whitespace-normalized
// text_head, tests by their id. Also checks the frontmatter of agents/test-auditor.md and
// commands/audit-tests.md (acceptance test 19).
//
// CI (ci.yml) covers Linux and macOS only. The Windows paths of the script (node_modules
// linked as a junction, the process tree killed with taskkill /T /F on a timeout) are
// verified by hand on the owner's machine by running this file there.
//
// Skipped when npm is unavailable or node is below 22.12 (vitest@5.0.4 needs ^22.12).
// Needs npm's cache or the network for the install, and git. Takes a few minutes.
//
//   node --test tests/test-ablation.test.js
"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const REPO = path.join(__dirname, "..");
const SCRIPT = path.join(REPO, "scripts", "test-ablation.cjs");
const WIN = process.platform === "win32";
const RUN_CAP_MS = 900000; // a hung script fails the test instead of hanging the suite

const [NODE_MAJOR, NODE_MINOR] = process.versions.node.split(".").map(Number);
const nodeOk = NODE_MAJOR > 22 || (NODE_MAJOR === 22 && NODE_MINOR >= 12);
const npmWorks = spawnSync("npm", ["--version"], { encoding: "utf8", shell: WIN }).status === 0;
const skip = !nodeOk
  ? `node ${process.versions.node} is below 22.12, the minimum of vitest@5.0.4`
  : !npmWorks
    ? "npm not available"
    : false;

// ---------------------------------------------------------------- the toy project

const CALC = [
  '"use strict";',
  'import { OFFSET } from "./other";',
  "",
  "export function sign(n: number): number {",
  "  if (n > 0) {",
  "    return 1;",
  "  }",
  "  return n === 0 ? 0 : -1;",
  "}",
  "",
  "export function scale(x: number, factor: number): number {",
  "  if (x < 0) x = 0;",
  '  console.log("scale", x, factor);',
  "  return x * factor + OFFSET;",
  "}",
  "",
  "export function label(n: number): string {",
  "  if (n > 100) {",
  '    return "big";',
  "  } else if (n === 42) {",
  '    return "answer";',
  "  } else {",
  '    return "small";',
  "  }",
  "}",
  "",
  "export function makeBox(v: number): { value: number } {",
  "  const box = { value: v };",
  "  return box;",
  "}",
  "",
  "export const double = (n: number): number => n * 2;",
  "",
  "export function sumUntilNegative(rows: number[][]): number {",
  "  let total = 0;",
  "  outer: for (const row of rows) {",
  "    for (const v of row) {",
  "      if (v < 0) continue outer;",
  "      total += v;",
  "    }",
  "  }",
  "  return total;",
  "}",
  "",
].join("\n");

const CALC_TEST = [
  'import { test, expect } from "vitest";',
  'import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";',
  'import { sign, scale, label, makeBox, double, sumUntilNegative } from "./calc";',
  "",
  'test("sign of a positive, a zero and a negative", () => {',
  "  expect(sign(5)).toBe(1);",
  "  expect(sign(0)).toBe(0);",
  "  expect(sign(-3)).toBe(-1);",
  "});",
  "",
  'test("scale multiplies", () => {',
  "  expect(scale(2, 3)).toBe(6);",
  "});",
  "",
  'test("label of a big and a small number", () => {',
  '  expect(label(500)).toBe("big");',
  '  expect(label(1)).toBe("small");',
  "});",
  "",
  'test("makeBox holds its value", () => {',
  "  expect(makeBox(3).value).toBe(3);",
  "});",
  "",
  'test("sumUntilNegative stops a row at its first negative", () => {',
  "  expect(sumUntilNegative([[1, 2], [3, -1, 5]])).toBe(6);",
  "});",
  "",
  'test("doubles", () => {',
  "  expect(double(2)).toBe(4);",
  "});",
  "",
  'test("doubles", () => {',
  "  expect(double(5)).toBe(10);",
  "});",
  "",
  'test("asserts nothing about calc", () => {',
  "  expect(1 + 1).toBe(2);",
  "});",
  "",
  'test("runs with TZ=UTC and CI=1", () => {',
  '  expect(process.env.TZ).toBe("UTC");',
  '  expect(process.env.CI).toBe("1");',
  "});",
  "",
  'test("counts its runs", () => {',
  "  const file = process.env.TOY_RUNS_FILE;",
  '  if (file) appendFileSync(file, "run" + String.fromCharCode(10));',
  "});",
  "",
  'test("flaky alternates", () => {',
  '  const counter = new URL("./.flaky", import.meta.url);',
  '  const n = existsSync(counter) ? Number(readFileSync(counter, "utf8")) : 0;',
  "  writeFileSync(counter, String(n + 1));",
  "  expect(n % 2).toBe(0);",
  "});",
  "",
].join("\n");

const ORPHAN_TEST = [
  'import { test, expect } from "vitest";',
  "",
  'test("calls triple, which calc does not export", async () => {',
  '  const { triple } = await import("./calc");',
  "  expect(triple(3)).toBe(9);",
  "});",
  "",
].join("\n");

const BROKEN_TEST = [
  'import { test, expect } from "vitest";',
  'import { sign } from "./calc";',
  'import { gone } from "./gone";',
  "",
  'test("never loads", () => {',
  "  expect(sign(gone)).toBe(1);",
  "});",
  "",
].join("\n");

const OTHER = ["export const OFFSET = 0;", "", "export function other(): string {", '  return "other";', "}", ""].join("\n");
const OTHER_TEST = [
  'import { test, expect } from "vitest";',
  'import { other } from "./other";',
  "",
  'test("other", () => {',
  '  expect(other()).toBe("other");',
  "});",
  "",
].join("\n");
const STAR = ['export * from "./other";', "", "export function star(): number {", "  return 1;", "}", ""].join("\n");
const SPIN = [
  "export function countTo(n: number): number {",
  "  let i = 0;",
  "  while (i < n) {",
  "    i++;",
  "  }",
  "  return i;",
  "}",
  "",
].join("\n");
const SPIN_TEST = [
  'import { test, expect } from "vitest";',
  'import { countTo } from "./spin";',
  "",
  'test("countTo counts", () => {',
  "  expect(countTo(3)).toBe(3);",
  "});",
  "",
].join("\n");

const TOY_FILES = {
  "package.json": JSON.stringify({ name: "ablation-toy", private: true, type: "module" }, null, 2) + "\n",
  ".gitignore": "node_modules\n",
  "src/calc.ts": CALC,
  "src/calc.test.ts": CALC_TEST,
  "src/orphan.test.ts": ORPHAN_TEST,
  "src/broken.test.ts": BROKEN_TEST,
  "src/other.ts": OTHER,
  "src/other.test.ts": OTHER_TEST,
  "src/star.ts": STAR,
  "src/spin.ts": SPIN,
  "src/spin.test.ts": SPIN_TEST,
};

// ---------------------------------------------------------------- helpers

const cleanup = [];
after(() => {
  for (const fn of cleanup.reverse()) {
    try {
      fn();
    } catch {
      // best effort: a leftover temp dir is not a test failure
    }
  }
});

function once(fn) {
  let done = false;
  let value;
  let error;
  return () => {
    if (!done) {
      done = true;
      try {
        value = fn();
      } catch (e) {
        error = e;
      }
    }
    if (error) throw error;
    return value;
  };
}

function tempDir(prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  cleanup.push(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function writeFiles(dir, files) {
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), body);
  }
}

const git = (dir, ...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8" });

// Recursive file list of the project, the real node_modules walked (links not followed), .git aside.
function fileList(dir) {
  const out = [];
  (function walk(rel) {
    for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (r === ".git") continue;
      out.push(r);
      if (e.isDirectory()) walk(r);
    }
  })("");
  return out.sort();
}
const snapshot = (dir) => ({ status: git(dir, "status", "--porcelain"), files: fileList(dir) });
const tmpEntries = () => fs.readdirSync(os.tmpdir()).filter((n) => n.startsWith("test-ablation-")).sort();

const toy = once(() => {
  const dir = tempDir("ablation-toy-");
  writeFiles(dir, TOY_FILES);
  const npm = spawnSync("npm", ["install", "--no-audit", "--no-fund", "--silent", "vitest@5.0.4", "typescript@6.0.3"], {
    cwd: dir,
    encoding: "utf8",
    shell: WIN,
  });
  assert.equal(npm.status, 0, `npm install failed: ${npm.stdout}${npm.stderr}`);
  git(dir, "init", "-q");
  git(dir, "add", "-A");
  git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "toy");
  return { dir, before: snapshot(dir), tmpBefore: tmpEntries() };
});

// A file outside the toy for the run-counter test of the toy.
const runsFile = () => path.join(tempDir("ablation-runs-"), "runs.txt");

// The script, as a caller runs it: cwd = the project, a foreign TZ and CI, so the
// toy's env test only passes if the script sets them itself.
function ablate(cwd, args, { env = {}, timeout = RUN_CAP_MS } = {}) {
  const started = Date.now();
  const r = spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd,
    encoding: "utf8",
    timeout,
    env: { ...process.env, TZ: "Europe/Paris", CI: "0", TOY_RUNS_FILE: runsFile(), ...env },
  });
  const res = { code: r.status, signal: r.signal, stdout: r.stdout || "", stderr: r.stderr || "", ms: Date.now() - started };
  const last = lastLine(res.stdout);
  res.reportPath = last;
  res.raw = last && path.isAbsolute(last) && fs.existsSync(last) ? fs.readFileSync(last, "utf8") : null;
  return res;
}
function lastLine(text) {
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== "");
  return lines.length ? lines[lines.length - 1].trim() : "";
}
function reportOf(r) {
  assert.equal(r.code, 0, `exit ${r.code} (${r.signal || "no signal"}): ${r.stderr}`);
  assert.ok(r.raw, `no report file at the last stdout line: ${JSON.stringify(r.reportPath)}`);
  return JSON.parse(r.raw);
}

// One full run on the main source, no option but --source: shared by the tests that read it.
const fullRun = once(() => ablate(toy().dir, ["--source", "src/calc.ts"]));

// The second full run of test 7, inside the before/after snapshot of test 8, then an exit-2 run.
const secondRun = once(() => {
  const t = toy();
  fullRun();
  const run = ablate(t.dir, ["--source", "src/calc.ts"]);
  const after = snapshot(t.dir);
  const tmpAfterRuns = tmpEntries();
  const failing = ablate(t.dir, ["--source", "src/calc.ts", "--tests", "src/broken.test.ts"]);
  return { run, after, tmpAfterRuns, failing, afterFailing: snapshot(t.dir), tmpAfterFailing: tmpEntries() };
});

const norm = (s) => String(s).replace(/\s+/g, " ").trim().replace(/;$/, "");
function unitsWhere(rep, pred) {
  return rep.units.filter((u) => pred(norm(u.text_head)));
}
function unit(rep, head) {
  const found = unitsWhere(rep, (h) => h === norm(head));
  assert.equal(found.length, 1, `expected one unit with text_head ${JSON.stringify(head)}, found ${found.length}`);
  return found[0];
}
function unitStarting(rep, prefix) {
  const found = unitsWhere(rep, (h) => h.startsWith(norm(prefix)));
  assert.equal(found.length, 1, `expected one unit whose text_head starts with ${JSON.stringify(prefix)}, found ${found.length}`);
  return found[0];
}
// 1-based line of the first line of CALC containing `needle`.
const calcLine = (needle) => CALC.split("\n").findIndex((l) => l.includes(needle)) + 1;
// The 1-based line range of a top-level function of CALC, closing brace included.
function calcFunctionLines(name) {
  const lines = CALC.split("\n");
  const start = lines.findIndex((l) => l.startsWith(`export function ${name}(`));
  const end = lines.findIndex((l, i) => i > start && l === "}");
  return [start + 1, end + 1];
}

const T = (file, name) => `${file}::${name}`;
const CALC_T = (name) => T("src/calc.test.ts", name);
const ORPHAN_ID = T("src/orphan.test.ts", "calls triple, which calc does not export");
const BROKEN_ID = "src/broken.test.ts::*";
const FLAKY_ID = CALC_T("flaky alternates");
const FACT_BUCKETS = ["survived_reached", "unreached", "crash_only", "never_failing_tests", "orphan_tests"];

function expectExit2(cwd, args) {
  const out = path.join(tempDir("ablation-out-"), "report.json");
  const r = ablate(cwd, [...args, "--out", out]);
  assert.equal(r.code, 2, `exit ${r.code}: ${r.stderr}`);
  const lines = r.stderr.split(/\r?\n/).filter((l) => l.trim() !== "");
  assert.equal(lines.length, 1, `exactly one stderr line, got: ${r.stderr}`);
  assert.equal(fs.existsSync(out), false, "no report is written on exit 2");
  return lines[0];
}

// ---------------------------------------------------------------- acceptance tests 1-17

test("a full run classifies the clamp as survived_reached, the else-if branch as unreached, console.log as side_effect_only and the crash-only statement as crash_only", { skip }, () => {
  const rep = reportOf(fullRun());
  const clamp = unit(rep, "if (x < 0) x = 0;");
  assert.ok(rep.facts.survived_reached.includes(clamp.id), `clamp ${clamp.id} not in survived_reached`);
  const answer = unit(rep, 'return "answer";');
  assert.equal(answer.reached, false);
  assert.ok(rep.facts.unreached.includes(answer.id), `${answer.id} not in unreached`);
  const log = unit(rep, 'console.log("scale", x, factor);');
  assert.ok(log.flags.includes("side_effect_only"), `flags of the console.log unit: ${JSON.stringify(log.flags)}`);
  const box = unit(rep, "const box = { value: v };");
  assert.ok(rep.facts.crash_only.includes(box.id), `${box.id} not in crash_only`);
});

test("every unit of the fully asserted function is killed by an assertion", { skip }, () => {
  const rep = reportOf(fullRun());
  const [from, to] = calcFunctionLines("sign");
  const inside = rep.units.filter((u) => u.start.line > from && u.start.line < to);
  assert.ok(inside.length >= 3, `units of sign: ${inside.map((u) => u.id).join(", ")}`);
  for (const u of inside) {
    assert.equal(u.status, "killed", `${u.id} is ${u.status}`);
    assert.ok(u.kills.some((k) => k.kind === "assertion"), `${u.id} has no assertion kill: ${JSON.stringify(u.kills)}`);
  }
});

test("the body of an expression-bodied arrow is a unit, reached and killed", { skip }, () => {
  const rep = reportOf(fullRun());
  const body = unit(rep, "n * 2");
  assert.equal(body.reached, true);
  assert.equal(body.status, "killed");
});

test("the units of a labeled loop with continue outer are reached and the run exits 0", { skip }, () => {
  const r = fullRun();
  const rep = reportOf(r);
  const labeled = unitStarting(rep, "outer:");
  const inLoop = rep.units.filter((u) => u.start.line >= labeled.start.line && u.start.line <= labeled.end.line);
  assert.ok(inLoop.length >= 4, `units of the labeled loop: ${inLoop.map((u) => u.id).join(", ")}`);
  for (const u of inLoop) assert.equal(u.reached, true, `${u.id} not reached`);
  assert.ok(inLoop.some((u) => norm(u.text_head) === "continue outer"), "continue outer is a unit");
});

test("baseline and facts: never-failing tests, the env test passing, orphans with missing_symbol, the flaky test only in baseline.flaky", { skip }, () => {
  const rep = reportOf(fullRun());
  const nothing = CALC_T("asserts nothing about calc");
  const envTest = CALC_T("runs with TZ=UTC and CI=1");
  assert.ok(rep.facts.never_failing_tests.includes(nothing), `${nothing} not in never_failing_tests`);
  assert.ok(rep.facts.never_failing_tests.includes(envTest), `${envTest} not in never_failing_tests`);
  assert.ok(rep.baseline.passing.includes(envTest), `${envTest} not in baseline.passing: TZ/CI not set by the script?`);

  const failing = (id) => rep.baseline.failing.find((f) => f.test === id);
  assert.ok(rep.facts.orphan_tests.includes(ORPHAN_ID), `${ORPHAN_ID} not in orphan_tests`);
  assert.equal(failing(ORPHAN_ID)?.reason, "missing_symbol");
  assert.ok(
    rep.static.missing_exports.some((m) => m.test_file === "src/orphan.test.ts" && m.name === "triple"),
    `missing_exports: ${JSON.stringify(rep.static.missing_exports)}`,
  );
  assert.equal(failing(BROKEN_ID)?.reason, "missing_symbol");
  assert.ok(rep.facts.orphan_tests.includes(BROKEN_ID), `${BROKEN_ID} not in orphan_tests`);

  assert.deepEqual(rep.baseline.flaky, [FLAKY_ID]);
  const occurrences = fullRun().raw.split(JSON.stringify(FLAKY_ID)).length - 1;
  assert.equal(occurrences, 1, "the flaky test appears in baseline.flaky and nowhere else");
});

test("two tests with the same title get the title and the title #2 as ids", { skip }, () => {
  const rep = reportOf(fullRun());
  assert.ok(rep.baseline.passing.includes(CALC_T("doubles")), "first `doubles`");
  assert.ok(rep.baseline.passing.includes(CALC_T("doubles #2")), "second `doubles`");
  assert.ok(!rep.baseline.passing.includes(CALC_T("doubles #3")));
});

test("two runs give byte-identical reports once meta is removed, with no absolute path", { skip }, () => {
  const first = fullRun();
  const { run: second } = secondRun();
  reportOf(first);
  reportOf(second);
  const strip = (raw) => {
    const o = JSON.parse(raw);
    delete o.meta;
    return JSON.stringify(o);
  };
  assert.equal(strip(second.raw), strip(first.raw));

  const roots = [os.tmpdir(), fs.realpathSync(os.tmpdir()), toy().dir, fs.realpathSync(toy().dir)];
  const forms = roots.flatMap((p) => [p, p.replace(/\\/g, "/"), JSON.stringify(p).slice(1, -1)]);
  for (const raw of [first.raw, second.raw]) {
    for (const f of forms) assert.ok(!raw.toLowerCase().includes(f.toLowerCase()), `the report contains ${f}`);
  }
});

test("the audited project, its node_modules and os.tmpdir() are unchanged by the runs, an exit-2 run included", { skip }, () => {
  const t = toy();
  const s = secondRun();
  assert.equal(fullRun().code, 0, `first run: ${fullRun().stderr}`);
  assert.equal(s.run.code, 0, `second run: ${s.run.stderr}`);
  assert.equal(s.failing.code, 2, `exit-2 run: ${s.failing.stderr}`);
  assert.equal(s.after.status, t.before.status, "git status --porcelain");
  assert.deepEqual(s.after.files, t.before.files, "file list, node_modules walked");
  assert.deepEqual(s.afterFailing.files, t.before.files, "file list after the exit-2 run");
  for (const cache of [".vite", ".vitest", ".vitest-cache"]) {
    assert.equal(fs.existsSync(path.join(t.dir, "node_modules", cache)), false, `node_modules/${cache} exists`);
  }
  assert.deepEqual(s.tmpAfterRuns, t.tmpBefore, "test-ablation-* temp dirs after the full runs");
  assert.deepEqual(s.tmpAfterFailing, t.tmpBefore, "test-ablation-* temp dirs after the exit-2 run");
});

test("every mutant of the main source parses: no unit is invalid", { skip }, () => {
  const rep = reportOf(fullRun());
  assert.ok(rep.units.length > 0);
  assert.deepEqual(rep.units.filter((u) => u.status === "invalid").map((u) => u.id), []);
});

test("not_ablated holds the import and the prologue; a unit names its parent; the clamp id is <function>/<index>:IfStatement", { skip }, () => {
  const rep = reportOf(fullRun());
  const importLine = calcLine("import { OFFSET }");
  const imp = rep.not_ablated.find((n) => n.start.line === importLine);
  assert.ok(imp, `no not_ablated entry on line ${importLine}`);
  assert.equal(imp.reason, "import");
  assert.equal(imp.kind, "ImportDeclaration");
  const prologue = rep.not_ablated.find((n) => n.start.line === 1);
  assert.ok(prologue, "no not_ablated entry for the use strict prologue");
  assert.equal(typeof prologue.reason, "string");
  assert.ok(prologue.reason.length > 0 && prologue.reason !== "import", `prologue reason: ${prologue.reason}`);
  assert.equal(rep.units.filter((u) => u.start.line <= importLine).length, 0, "the prologue and the import are not units");

  const clamp = unit(rep, "if (x < 0) x = 0;");
  assert.match(clamp.id, /^scale\/\d+:IfStatement$/);
  assert.equal(unit(rep, "x = 0;").parent, clamp.id);
});

test("without --tests, the test files importing the source are discovered, sorted, project-relative", { skip }, () => {
  const rep = reportOf(fullRun());
  const expected = ["src/broken.test.ts", "src/calc.test.ts", "src/orphan.test.ts"];
  assert.deepEqual(rep.tests, expected);
  assert.deepEqual(rep.static.test_files_importing_source, expected);
});

test("stdout has one count line per facts bucket, then the report path alone as the last line", { skip }, () => {
  const r = fullRun();
  const rep = reportOf(r);
  const lines = r.stdout.split(/\r?\n/).filter((l) => l.trim() !== "");
  const last = lines.pop();
  assert.ok(path.isAbsolute(last.trim()) && fs.existsSync(last.trim()), `last line is not the report path: ${last}`);
  assert.equal(lines.length, FACT_BUCKETS.length, `count lines: ${JSON.stringify(lines)}`);
  for (const bucket of FACT_BUCKETS) {
    const matching = lines.filter((l) => new RegExp(`(^|[^\\w])${bucket}([^\\w]|$)`).test(l));
    assert.equal(matching.length, 1, `one line names ${bucket}: ${JSON.stringify(lines)}`);
    const n = rep.facts[bucket].length;
    assert.match(matching[0], new RegExp(`(^|\\D)${n}(\\D|$)`), `${bucket} line carries its count ${n}`);
  }
});

test("--out inside the audited project writes the report there and prints that path last", { skip }, () => {
  const t = toy();
  const out = path.join(t.dir, "ablation-report.json");
  cleanup.push(() => fs.rmSync(out, { force: true }));
  try {
    const r = ablate(t.dir, ["--source", "src/calc.ts", "--out", out]);
    assert.equal(r.code, 0, r.stderr);
    assert.ok(fs.existsSync(out), "report not written at --out");
    assert.equal(fs.realpathSync(lastLine(r.stdout)), fs.realpathSync(out));
    assert.equal(JSON.parse(fs.readFileSync(out, "utf8")).schema, 1);
  } finally {
    fs.rmSync(out, { force: true });
  }
});

test("static.exports lists the source's exports; export * makes exports_complete false", { skip }, () => {
  const rep = reportOf(fullRun());
  assert.deepEqual([...rep.static.exports].sort(), ["double", "label", "makeBox", "scale", "sign", "sumUntilNegative"]);
  assert.equal(rep.static.exports_complete, true);

  const star = ablate(toy().dir, ["--source", "src/star.ts", "--tests", "src/other.test.ts", "--dry-run"]);
  const starRep = reportOf(star);
  assert.equal(starRep.dry_run, true);
  assert.equal(starRep.static.exports_complete, false);
});

test("--dry-run runs the baseline only: units without kills, dry_run true, the baseline ran exactly twice", { skip }, () => {
  const counter = runsFile();
  const r = ablate(toy().dir, ["--source", "src/calc.ts", "--dry-run", "--baseline-runs", "2"], { env: { TOY_RUNS_FILE: counter } });
  const rep = reportOf(r);
  assert.equal(rep.dry_run, true);
  assert.ok(rep.units.length > 0, "the units are listed");
  for (const u of rep.units) assert.ok(!u.kills || u.kills.length === 0, `${u.id} has kills in a dry run`);
  assert.ok(fs.existsSync(lastLine(r.stdout)));
  const runs = fs.readFileSync(counter, "utf8").split(/\r?\n/).filter((l) => l !== "");
  assert.equal(runs.length, 2, "two baseline runs, no reach run, no mutant");
});

test("a mutant that loops forever is killed by a timeout and the script still exits 0", { skip }, () => {
  const r = ablate(toy().dir, ["--source", "src/spin.ts"], { timeout: 300000 });
  assert.equal(r.signal, null, `the script hung (${r.ms} ms): its process tree was not killed`);
  const rep = reportOf(r);
  const inc = unit(rep, "i++;");
  assert.deepEqual(inc.kills, [{ test: "*", kind: "timeout" }]);
  assert.equal(inc.status, "killed");
});

test("exit 2 with one stderr line and no report on each blind spot", { skip }, async (t) => {
  await t.test("no node_modules: the line names typescript and vitest", () => {
    const dir = tempDir("ablation-bare-");
    writeFiles(dir, { "package.json": '{ "type": "module" }\n', "a.ts": "export const a = (): number => 1;\n" });
    const line = expectExit2(dir, ["--source", "a.ts"]);
    assert.match(line, /typescript/);
    assert.match(line, /vitest/);
  });

  await t.test("a source with a syntax error: the line says syntax", () => {
    const dir = toy().dir;
    const bad = path.join(dir, "src", "bad.ts");
    fs.writeFileSync(bad, "export function broken( {\n  return 1;\n");
    try {
      assert.match(expectExit2(dir, ["--source", "src/bad.ts", "--tests", "src/calc.test.ts"]), /syntax/i);
    } finally {
      fs.rmSync(bad, { force: true });
    }
  });

  await t.test("every test failing in the baseline: the line says no stable passing test", () => {
    assert.match(expectExit2(toy().dir, ["--source", "src/calc.ts", "--tests", "src/broken.test.ts"]), /no stable passing test/i);
  });

  await t.test("typescript 7.0.2 without createSourceFile: the line names both", () => {
    const dir = tempDir("ablation-ts7-");
    writeFiles(dir, {
      "package.json": '{ "type": "module" }\n',
      "src/one.ts": "export const one = (): number => 1;\n",
      "src/one.test.ts": 'import { test, expect } from "vitest";\nimport { one } from "./one";\ntest("one", () => expect(one()).toBe(1));\n',
      "node_modules/typescript/package.json": JSON.stringify({ name: "typescript", version: "7.0.2", main: "index.js" }) + "\n",
      "node_modules/typescript/index.js": 'module.exports = { version: "7.0.2", versionMajorMinor: "7.0" };\n',
    });
    const link = path.join(dir, "node_modules", "vitest");
    fs.symlinkSync(path.join(toy().dir, "node_modules", "vitest"), link, "junction");
    try {
      const line = expectExit2(dir, ["--source", "src/one.ts"]);
      assert.match(line, /7\.0\.2/);
      assert.match(line, /createSourceFile/);
    } finally {
      fs.unlinkSync(link); // the junction first, so no cleanup ever walks into the toy's vitest
    }
  });
});

// ---------------------------------------------------------------- spec requirements the plan's list does not name

test("the report is canonical: keys sorted, units by source position, id lists sorted", { skip }, () => {
  const rep = reportOf(fullRun());
  // Code-unit order (Array.prototype.sort): a locale-aware order would differ between machines.
  (function keysSorted(v, where) {
    if (Array.isArray(v)) return v.forEach((x, i) => keysSorted(x, `${where}[${i}]`));
    if (v && typeof v === "object") {
      const keys = Object.keys(v);
      assert.deepEqual(keys, [...keys].sort(), `keys of ${where}`);
      for (const k of keys) keysSorted(v[k], `${where}.${k}`);
    }
  })(rep, "report");
  const pos = rep.units.map((u) => [u.start.line, u.start.col]);
  const sortedPos = [...pos].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  assert.deepEqual(pos, sortedPos, "units by start");
  const lists = {
    tests: rep.tests,
    "baseline.passing": rep.baseline.passing,
    "baseline.flaky": rep.baseline.flaky,
    ...Object.fromEntries(FACT_BUCKETS.map((b) => [`facts.${b}`, rep.facts[b]])),
  };
  for (const [name, list] of Object.entries(lists)) assert.deepEqual(list, [...list].sort(), name);
  for (const u of rep.units) {
    const ids = (u.kills || []).map((k) => k.test);
    assert.deepEqual(ids, [...ids].sort(), `kills of ${u.id}`);
  }
});

test("the report header names schema 1, typescript, the source and the tool versions; units carry 1-based positions and a 12-hex text_sha1", { skip }, () => {
  const rep = reportOf(fullRun());
  assert.equal(rep.schema, 1);
  assert.equal(rep.language, "typescript");
  assert.equal(rep.dry_run, false);
  assert.equal(rep.source, "src/calc.ts");
  assert.deepEqual(rep.tool_versions, { node: process.versions.node, typescript: "6.0.3", vitest: "5.0.4" });
  const clamp = unit(rep, "if (x < 0) x = 0;");
  assert.deepEqual(clamp.start, { line: calcLine("if (x < 0) x = 0;"), col: 3 });
  for (const u of rep.units) assert.match(u.text_sha1, /^[0-9a-f]{12}$/, `text_sha1 of ${u.id}`);
});

test("without --out the report lands in <os.tmpdir()>/test-ablation/<12 hex>.json", { skip }, () => {
  const r = fullRun();
  reportOf(r);
  const p = lastLine(r.stdout);
  assert.match(path.basename(p), /^[0-9a-f]{12}\.json$/);
  assert.equal(fs.realpathSync(path.dirname(p)), fs.realpathSync(path.join(os.tmpdir(), "test-ablation")));
});

// ---------------------------------------------------------------- acceptance test 19: the prompt files

function frontmatter(rel) {
  const text = fs.readFileSync(path.join(REPO, rel), "utf8");
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
  assert.ok(m, `${rel} has no frontmatter`);
  const fields = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^([\w-]+):\s*(.*?)\s*$/.exec(line);
    if (!kv) continue;
    let v = kv[2];
    if (/^'.*'$/.test(v)) v = v.slice(1, -1).replace(/''/g, "'");
    else if (/^".*"$/.test(v)) v = JSON.parse(v);
    fields[kv[1]] = v;
  }
  return fields;
}

test("test-auditor is read-only on opus; /audit-tests is owner-started, unforked, limited to agents, reads and the script", () => {
  const agent = frontmatter("agents/test-auditor.md");
  assert.equal(agent.tools, "Read, Grep, Glob");
  assert.equal(agent.model, "opus");
  const cmd = frontmatter("commands/audit-tests.md");
  assert.equal(cmd["disable-model-invocation"], "true");
  assert.equal(cmd.context, undefined, "no context: fork, the command spawns agents");
  assert.equal(cmd["allowed-tools"], "Agent, Read, Grep, Glob, Bash(node ~/.claude/scripts/test-ablation.cjs:*)");
});

test("test-auditor is named and described as spawned by /audit-tests; /audit-tests takes a source and test files", () => {
  const agent = frontmatter("agents/test-auditor.md");
  assert.equal(agent.name, "test-auditor");
  assert.match(agent.description, /Read-only, spawned by \/audit-tests/);
  const cmd = frontmatter("commands/audit-tests.md");
  assert.equal(cmd["argument-hint"], "<source file> [test files…]");
  assert.ok(cmd.description && cmd.description.length > 0, "the command has a description");
});
