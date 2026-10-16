// Acceptance tests for scripts/test-ablation.cjs (specs: docs/audit-tests-ts.md, then
// docs/audit-tests-vitest-compat.md, then docs/audit-tests-effects.md, whose plan tests are
// numbered "effects N" below) on toy TypeScript projects generated in os.tmpdir():
// git repos with node_modules ignored and a minimal vitest.config.ts, installed by npm:
//   - the primary toy, vitest@5.0.4 + vite@8.3.4 + typescript@6.0.3, runs every test;
//   - vitest@3.2.7 + vite@7.3.7 + typescript@6.0.3 and vitest@4.1.11 + vite@8.3.4 +
//     typescript@6.0.3, each created lazily, run the per-major trio (facts buckets,
//     determinism, project and node_modules untouched) and, for 3.2.7, the config-load failure.
// Stub `vitest` packages (versions 2.1.9, 3.0.0, 3.1.0, 6.0.0, 3.2.7) cover the version gate
// (3.1 to 5.x) and the exit-2 line; their typescript is a junction to the primary toy's.
// The script is spawned with process.execPath, like baseline-ratchet; units are located by
// their whitespace-normalized text_head, tests by their id. Every run passes its own --out
// under a temp dir this file removes, except the one test of the default --out, which removes
// its report itself; the last test checks that os.tmpdir() holds nothing new from this file.
// Also checks the frontmatter of agents/test-auditor.md and commands/audit-tests.md.
//
// CI (ci.yml) covers Linux and macOS only. The Windows paths of the script (node_modules
// linked as a junction, the process tree killed with taskkill /T /F on a timeout) are
// verified by hand on the owner's machine by running this file there.
//
// Skipped when npm is unavailable or node is below the engine of the version under test:
// 22.12 for vitest@5.0.4 (the primary toy, the stubs and most tests), 20 for vitest@4.1.11,
// 18 for vitest@3.2.7. The 3.2.7 and 4.1.11 tests are also skipped when npm cannot install
// that version. Needs npm's cache or the network for the installs, and git. Takes minutes.
//
//   node --test tests/test-ablation.test.js
"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// The temp dir as it was before this file created anything (spec 4, plan test 15).
const TMP_BEFORE = fs.readdirSync(os.tmpdir());
const DEFAULT_REPORT_DIR = path.join(os.tmpdir(), "test-ablation");
const REPORTS_BEFORE = fs.existsSync(DEFAULT_REPORT_DIR) ? fs.readdirSync(DEFAULT_REPORT_DIR) : [];

const REPO = path.join(__dirname, "..");
const SCRIPT = path.join(REPO, "scripts", "test-ablation.cjs");
const WIN = process.platform === "win32";
const RUN_CAP_MS = 900000; // a hung script fails the test instead of hanging the suite

const [NODE_MAJOR, NODE_MINOR] = process.versions.node.split(".").map(Number);
const nodeAtLeast = (major, minor = 0) => NODE_MAJOR > major || (NODE_MAJOR === major && NODE_MINOR >= minor);
const npmWorks = spawnSync("npm", ["--version"], { encoding: "utf8", shell: WIN }).status === 0;
const skipFor = (version, major, minor = 0) =>
  !nodeAtLeast(major, minor)
    ? `node ${process.versions.node} is below ${major}.${minor}, the minimum of vitest@${version}`
    : !npmWorks
      ? "npm not available"
      : false;
const skip = skipFor("5.0.4", 22, 12);

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

// Spec 5: a value built, then dereferenced by a test that asserts nothing: really crash-only.
const DEREF = [
  "export function peek(v: number): number {",
  "  const holder = { inner: { value: v } };",
  "  return holder.inner.value;",
  "}",
  "",
].join("\n");
const DEREF_TEST = [
  'import { test } from "vitest";',
  'import { peek } from "./deref";',
  "",
  'test("peek runs", () => {',
  "  peek(1);",
  "});",
  "",
].join("\n");

// The `if` holds the only declaration of `hits` (a `var` in its block). Removing it used to
// remove the binding too (`return hits` threw a `ReferenceError`, a `binding` kill); since
// docs/audit-tests-effects.md requirement 3 the mutant keeps `var hits;`, so `countHits(3)`
// returns undefined and the assertion says so. `let last;` has no initializer (not ablated).
const HOIST = [
  "export function countHits(n: number): number {",
  "  if (n > 0) {",
  "    var hits = n;",
  "  }",
  "  return hits;",
  "}",
  "",
  "export function lastOf(values: number[]): number {",
  "  let last;",
  "  for (const v of values) last = v;",
  "  return last ?? -1;",
  "}",
  "",
].join("\n");
const HOIST_TEST = [
  'import { test, expect } from "vitest";',
  'import { countHits, lastOf } from "./hoist";',
  "",
  'test("countHits returns the hits of a positive", () => {',
  "  expect(countHits(3)).toBe(3);",
  "});",
  "",
  'test("lastOf returns the last value", () => {',
  "  expect(lastOf([1, 2])).toBe(2);",
  "});",
  "",
].join("\n");
// Effects 8: a second test file on hoist.ts that reads an undeclared `hits` itself when
// countHits(3) comes back undefined: its own ReferenceError, thrown in the test file. Passes in
// the baseline (countHits(3) is 3, `hits` never read).
const HOIST_GLOBAL_TEST = [
  'import { test, expect } from "vitest";',
  'import { countHits } from "./hoist";',
  "",
  'test("hits is read by the test when countHits returns undefined", () => {',
  "  const got = countHits(3);",
  "  if (got === undefined) {",
  "    // @ts-expect-error hits is not declared here: reading it throws a ReferenceError",
  "    expect(hits).toBe(3);",
  "  }",
  "  expect(got).toBe(3);",
  "});",
  "",
].join("\n");

// Effects 4 to 6: function-valued declarators are not units, their bodies are.
const FNVAL = [
  "const helper = (x: number) => x * 2;",
  "",
  "export function quad(x: number): number {",
  "  return helper(helper(x));",
  "}",
  "",
  "export function pick(): number {",
  "  const a = 1, f = () => a;",
  "  return f();",
  "}",
  "",
  "export function zero(): number {",
  "  const z = 0, g = () => z;",
  "  return g();",
  "}",
  "",
].join("\n");
const FNVAL_TEST = [
  'import { test, expect } from "vitest";',
  'import { quad, pick, zero } from "./fnval";',
  "",
  'test("quad applies helper twice", () => {',
  "  expect(quad(2)).toBe(8);",
  "});",
  "",
  'test("pick returns a", () => {',
  "  expect(pick()).toBe(1);",
  "});",
  "",
  'test("zero returns z", () => {',
  "  expect(zero()).toBe(0);",
  "});",
  "",
].join("\n");

// Spec 6: the test file mocks the source, so no unit of it ever runs.
const MOCKED = ["export function greet(name: string): string {", '  return "hello " + name;', "}", ""].join("\n");
const MOCKED_TEST = [
  'import { test, expect, vi } from "vitest";',
  'import { greet } from "./mocked";',
  "",
  'vi.mock("./mocked", () => ({ greet: (name: string) => "mocked " + name }));',
  "",
  'test("greet is replaced by its mock", () => {',
  '  expect(greet("x")).toBe("mocked x");',
  "});",
  "",
].join("\n");

const VITEST_CONFIG = 'export default { test: { include: ["src/**/*.test.ts"] } };\n';
const BROKEN_CONFIG = [
  'import { nothere } from "./missing-module";',
  "",
  'export default { test: { include: ["src/**/*.test.ts"] }, nothere };',
  "",
].join("\n");

const TOY_FILES = {
  "package.json": JSON.stringify({ name: "ablation-toy", private: true, type: "module" }, null, 2) + "\n",
  ".gitignore": "node_modules\n",
  "vitest.config.ts": VITEST_CONFIG,
  "src/calc.ts": CALC,
  "src/calc.test.ts": CALC_TEST,
  "src/orphan.test.ts": ORPHAN_TEST,
  "src/broken.test.ts": BROKEN_TEST,
  "src/other.ts": OTHER,
  "src/other.test.ts": OTHER_TEST,
  "src/star.ts": STAR,
  "src/spin.ts": SPIN,
  "src/spin.test.ts": SPIN_TEST,
  "src/deref.ts": DEREF,
  "src/deref.test.ts": DEREF_TEST,
  "src/hoist.ts": HOIST,
  "src/hoist.test.ts": HOIST_TEST,
  "src/hoist-global.test.ts": HOIST_GLOBAL_TEST,
  "src/fnval.ts": FNVAL,
  "src/fnval.test.ts": FNVAL_TEST,
  "src/mocked.ts": MOCKED,
  "src/mocked.test.ts": MOCKED_TEST,
};

const PRIMARY = { version: "5.0.4", vite: "8.3.4", typescript: "6.0.3" };
const EXTRA_MAJORS = [
  { version: "3.2.7", vite: "7.3.7", typescript: "6.0.3", skip: skipFor("3.2.7", 18) },
  { version: "4.1.11", vite: "8.3.4", typescript: "6.0.3", skip: skipFor("4.1.11", 20) },
];
const pkgsOf = (m) => [`vitest@${m.version}`, `vite@${m.vite}`, `typescript@${m.typescript}`];

// ---------------------------------------------------------------- helpers

const cleanup = [];
function runCleanup() {
  while (cleanup.length) {
    const fn = cleanup.pop();
    try {
      fn();
    } catch {
      // best effort here; the last test checks what is left in os.tmpdir()
    }
  }
}
after(runCleanup);

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

// A toy installed by npm; { dir, npmError } when npm fails, so a caller can skip.
function installToy(prefix, pkgs) {
  const dir = tempDir(prefix);
  writeFiles(dir, TOY_FILES);
  const npm = spawnSync("npm", ["install", "--no-audit", "--no-fund", "--silent", ...pkgs], {
    cwd: dir,
    encoding: "utf8",
    shell: WIN,
  });
  if (npm.status !== 0) return { dir, npmError: `${npm.stdout}${npm.stderr}` || `exit ${npm.status}` };
  git(dir, "init", "-q");
  git(dir, "add", "-A");
  git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "toy");
  return { dir, before: snapshot(dir), tmpBefore: tmpEntries() };
}

const toy = once(() => {
  const t = installToy("ablation-toy-", pkgsOf(PRIMARY));
  assert.equal(t.npmError, undefined, `npm install failed: ${t.npmError}`);
  return t;
});
for (const m of EXTRA_MAJORS) m.toy = once(() => installToy(`ablation-toy-v${m.version.split(".")[0]}-`, pkgsOf(m)));
const toyOf = (version) => EXTRA_MAJORS.find((m) => m.version === version);

// A file outside the toy for the run-counter test of the toy.
const runsFile = () => path.join(tempDir("ablation-runs-"), "runs.txt");

// The script, as a caller runs it: cwd = the project, a foreign TZ and CI, so the
// toy's env test only passes if the script sets them itself. Every run gets its own --out
// under a temp dir of this file, unless the args carry one or `defaultOut` is set.
function ablate(cwd, args, { env = {}, timeout = RUN_CAP_MS, defaultOut = false } = {}) {
  const out = args.includes("--out") || defaultOut ? null : path.join(tempDir("ablation-out-"), "report.json");
  const started = Date.now();
  const r = spawnSync(process.execPath, [SCRIPT, ...args, ...(out ? ["--out", out] : [])], {
    cwd,
    encoding: "utf8",
    timeout,
    env: { ...process.env, TZ: "Europe/Paris", CI: "0", TOY_RUNS_FILE: runsFile(), ...env },
  });
  const res = { code: r.status, signal: r.signal, stdout: r.stdout || "", stderr: r.stderr || "", ms: Date.now() - started, out };
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

// Two full runs on the main source (determinism), inside a before/after snapshot of the toy,
// then an exit-2 run: the same structure for every Vitest major.
function runsOn(toyFn) {
  const first = once(() => ablate(toyFn().dir, ["--source", "src/calc.ts"]));
  const rest = once(() => {
    const t = toyFn();
    first();
    const run = ablate(t.dir, ["--source", "src/calc.ts"]);
    const after = snapshot(t.dir);
    const tmpAfterRuns = tmpEntries();
    const failing = ablate(t.dir, ["--source", "src/calc.ts", "--tests", "src/broken.test.ts"]);
    return { run, after, tmpAfterRuns, failing, afterFailing: snapshot(t.dir), tmpAfterFailing: tmpEntries() };
  });
  return { first, rest };
}
const primaryRuns = runsOn(toy);
// One full run on the main source, no option but --source (and its own --out): shared by the tests that read it.
const fullRun = primaryRuns.first;
const secondRun = primaryRuns.rest;
for (const m of EXTRA_MAJORS) m.runs = runsOn(m.toy);

const spinRun = once(() => ablate(toy().dir, ["--source", "src/spin.ts"], { timeout: 300000 }));
const hoistRun = once(() => ablate(toy().dir, ["--source", "src/hoist.ts", "--tests", "src/hoist.test.ts"]));
const derefRun = once(() => ablate(toy().dir, ["--source", "src/deref.ts", "--tests", "src/deref.test.ts"]));
// Effects 8: its own run, so the kills of the `if` unit come from that test file alone.
const hoistGlobalRun = once(() => ablate(toy().dir, ["--source", "src/hoist.ts", "--tests", "src/hoist-global.test.ts"]));
const fnvalRun = once(() => ablate(toy().dir, ["--source", "src/fnval.ts", "--tests", "src/fnval.test.ts"]));

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
// 1-based line of the first line of `text` containing `needle`.
const lineIn = (text, needle) => text.split("\n").findIndex((l) => l.includes(needle)) + 1;
const calcLine = (needle) => lineIn(CALC, needle);
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
// The kill kinds of docs/audit-tests-effects.md: `binding` is gone, `test_error` is new.
const KILL_KINDS = ["assertion", "test_error", "crash", "timeout"];
const allKills = (rep) => rep.units.flatMap((u) => (u.kills || []).map((k) => ({ unit: u.id, ...k })));
const EXIT2_PREFIX = "test-ablation: ";

// Every exit-2 stderr line starts with `test-ablation: ` (effects plan); the line is returned whole.
function expectExit2(cwd, args, { env = {} } = {}) {
  const out = path.join(tempDir("ablation-out-"), "report.json");
  const r = ablate(cwd, [...args, "--out", out], { env });
  assert.equal(r.code, 2, `exit ${r.code}: ${r.stderr}`);
  const lines = r.stderr.split(/\r?\n/).filter((l) => l.trim() !== "");
  assert.equal(lines.length, 1, `exactly one stderr line, got: ${r.stderr}`);
  assert.ok(lines[0].startsWith(EXIT2_PREFIX), `the line does not start with ${JSON.stringify(EXIT2_PREFIX)}: ${lines[0]}`);
  assert.equal(fs.existsSync(out), false, "no report is written on exit 2");
  return lines[0];
}

// No absolute path in a stderr line: none of the roots (as given, realpath, native realpath),
// os.tmpdir() and the home directory, in either separator, case-insensitively; no drive letter
// followed by a separator; no file:// URL.
function assertNoAbsolutePath(line, roots) {
  const forms = new Set();
  for (const root of [...roots, os.tmpdir(), os.homedir()]) {
    const variants = [root];
    for (const real of [fs.realpathSync, fs.realpathSync.native]) {
      try {
        variants.push(real(root));
      } catch {
        // a root that no longer exists has no realpath
      }
    }
    for (const v of variants) {
      forms.add(v);
      forms.add(v.replace(/\\/g, "/"));
      forms.add(v.replace(/\//g, "\\"));
    }
  }
  const lower = line.toLowerCase();
  for (const f of forms) assert.ok(!lower.includes(f.toLowerCase()), `the line contains ${f}: ${line}`);
  assert.doesNotMatch(line, /(^|[^A-Za-z])[A-Za-z]:[\\/]/, `a drive-letter path in: ${line}`);
  assert.doesNotMatch(line, /file:\/\//i, `a file:// URL in: ${line}`);
}

// The fact buckets of the toy, the same on every Vitest major (plan tests 1 and 2).
function assertFactBuckets(rep) {
  const clamp = unit(rep, "if (x < 0) x = 0;");
  assert.ok(rep.facts.survived_reached.includes(clamp.id), `clamp ${clamp.id} not in survived_reached`);
  const answer = unit(rep, 'return "answer";');
  assert.equal(answer.reached, false);
  assert.ok(rep.facts.unreached.includes(answer.id), `${answer.id} not in unreached`);
  const log = unit(rep, 'console.log("scale", x, factor);');
  assert.ok(log.flags.includes("side_effect_only"), `flags of the console.log unit: ${JSON.stringify(log.flags)}`);
  const box = unit(rep, "const box = { value: v };");
  assert.ok(!rep.facts.crash_only.includes(box.id), `${box.id} is in crash_only`);
}
// Effects 1 and 12: `return box;` removed, `makeBox(3).value` throws a TypeError in the test
// file itself: a test_error kill, not a crash, so the unit is out of crash_only.
function assertReturnBoxTestError(rep) {
  const ret = unit(rep, "return box;");
  assert.equal(ret.status, "killed", `${ret.id} is ${ret.status}`);
  const kill = ret.kills.find((k) => k.test === CALC_T("makeBox holds its value"));
  assert.ok(kill, `${ret.id} is not killed by makeBox holds its value: ${JSON.stringify(ret.kills)}`);
  assert.equal(kill.kind, "test_error", `kills of ${ret.id}: ${JSON.stringify(ret.kills)}`);
  assert.ok(!rep.facts.crash_only.includes(ret.id), `${ret.id} is in crash_only`);
}
function assertTestFacts(rep, raw) {
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
  const occurrences = raw.split(JSON.stringify(FLAKY_ID)).length - 1;
  assert.equal(occurrences, 1, "the flaky test appears in baseline.flaky and nowhere else");
}
function assertDeterministic(first, second, dir) {
  reportOf(first);
  reportOf(second);
  const strip = (raw) => {
    const o = JSON.parse(raw);
    delete o.meta;
    return JSON.stringify(o);
  };
  assert.equal(strip(second.raw), strip(first.raw));

  const roots = [os.tmpdir(), fs.realpathSync(os.tmpdir()), dir, fs.realpathSync(dir)];
  const forms = roots.flatMap((p) => [p, p.replace(/\\/g, "/"), JSON.stringify(p).slice(1, -1)]);
  for (const raw of [first.raw, second.raw]) {
    for (const f of forms) assert.ok(!raw.toLowerCase().includes(f.toLowerCase()), `the report contains ${f}`);
  }
}
function assertUntouched(t, first, s) {
  assert.equal(first.code, 0, `first run: ${first.stderr}`);
  assert.equal(s.run.code, 0, `second run: ${s.run.stderr}`);
  assert.equal(s.failing.code, 2, `exit-2 run: ${s.failing.stderr}`);
  assert.equal(s.after.status, t.before.status, "git status --porcelain");
  assert.deepEqual(s.after.files, t.before.files, "file list, node_modules walked");
  assert.equal(s.afterFailing.status, t.before.status, "git status --porcelain after the exit-2 run");
  assert.deepEqual(s.afterFailing.files, t.before.files, "file list after the exit-2 run");
  for (const cache of [".vite", ".vite-temp", ".vitest", ".vitest-cache"]) {
    assert.equal(fs.existsSync(path.join(t.dir, "node_modules", cache)), false, `node_modules/${cache} exists`);
  }
  assert.deepEqual(s.tmpAfterRuns, t.tmpBefore, "test-ablation-* temp dirs after the full runs");
  assert.deepEqual(s.tmpAfterFailing, t.tmpBefore, "test-ablation-* temp dirs after the exit-2 run");
}

// ---------------------------------------------------------------- the primary toy (plan test 1)

test("a full run classifies the clamp as survived_reached, the else-if branch as unreached, console.log as side_effect_only, and the box declaration out of crash_only", { skip }, () => {
  // The previous unit expected `const box = { value: v };` in crash_only. That expectation
  // encoded the bug of docs/audit-tests-vitest-compat.md spec 5: removing the declaration made
  // `return box` throw a ReferenceError whatever the test asserted. Flipped by that spec.
  // Its sibling `return box;` was a `crash` kill for a TypeError thrown in the test file;
  // docs/audit-tests-effects.md makes it a `test_error` (effects 1, the next tests).
  assertFactBuckets(reportOf(fullRun()));
});

test("effects 1: return box; is killed by makeBox holds its value with kind test_error and is not crash_only", { skip }, () => {
  assertReturnBoxTestError(reportOf(fullRun()));
});

test("effects 2: no kill has kind binding, every kill kind is assertion, test_error, crash or timeout; the orphan stays missing_symbol", { skip }, () => {
  const rep = reportOf(fullRun());
  const kills = allKills(rep);
  assert.ok(kills.length > 0, "the full run has kills");
  assert.deepEqual(kills.filter((k) => k.kind === "binding"), [], "binding kills");
  assert.deepEqual(kills.filter((k) => !KILL_KINDS.includes(k.kind)), [], `kills outside ${KILL_KINDS.join(", ")}`);
  assert.equal(rep.baseline.failing.find((f) => f.test === ORPHAN_ID)?.reason, "missing_symbol", `baseline.failing: ${JSON.stringify(rep.baseline.failing)}`);
});

test("the box declaration is killed by the assertion of makeBox holds its value and is not crash_only", { skip }, () => {
  const rep = reportOf(fullRun());
  const box = unit(rep, "const box = { value: v };");
  assert.equal(box.status, "killed", `${box.id} is ${box.status}`);
  assert.ok(
    box.kills.some((k) => k.test === CALC_T("makeBox holds its value") && k.kind === "assertion"),
    `kills of ${box.id}: ${JSON.stringify(box.kills)}`,
  );
  assert.ok(!rep.facts.crash_only.includes(box.id), `${box.id} is in crash_only`);
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
  const r = fullRun();
  assertTestFacts(reportOf(r), r.raw);
});

test("two tests with the same title get the title and the title #2 as ids", { skip }, () => {
  const rep = reportOf(fullRun());
  assert.ok(rep.baseline.passing.includes(CALC_T("doubles")), "first `doubles`");
  assert.ok(rep.baseline.passing.includes(CALC_T("doubles #2")), "second `doubles`");
  assert.ok(!rep.baseline.passing.includes(CALC_T("doubles #3")));
});

test("two runs give byte-identical reports once meta is removed, with no absolute path", { skip }, () => {
  assertDeterministic(fullRun(), secondRun().run, toy().dir);
});

test("the audited project, its node_modules (.vite-temp included) and os.tmpdir() are unchanged by the runs, an exit-2 run included", { skip }, () => {
  const t = toy();
  const s = secondRun();
  assertUntouched(t, fullRun(), s);
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

test("--dry-run runs the baseline only: units without kills, dry_run true, the baseline ran exactly twice; stdout carries the unit lines, units: N, not_ablated: M, the estimate, the report path last", { skip }, () => {
  const counter = runsFile();
  const r = ablate(toy().dir, ["--source", "src/calc.ts", "--dry-run", "--baseline-runs", "2"], { env: { TOY_RUNS_FILE: counter } });
  const rep = reportOf(r);
  assert.equal(rep.dry_run, true);
  assert.ok(rep.units.length > 0, "the units are listed");
  for (const u of rep.units) assert.ok(!u.kills || u.kills.length === 0, `${u.id} has kills in a dry run`);
  assert.ok(fs.existsSync(lastLine(r.stdout)));
  const runs = fs.readFileSync(counter, "utf8").split(/\r?\n/).filter((l) => l !== "");
  assert.equal(runs.length, 2, "two baseline runs, no reach run, no mutant");

  const lines = r.stdout.split(/\r?\n/).map((l) => l.trim()).filter((l) => l !== "");
  for (const u of rep.units) assert.ok(lines.some((l) => l.startsWith(u.id)), `no stdout line for unit ${u.id}`);
  const unitsAt = lines.findIndex((l) => /^units: \d+$/.test(l));
  assert.ok(unitsAt >= 0, `no units: N line in ${JSON.stringify(lines)}`);
  assert.equal(lines[unitsAt], `units: ${rep.units.length}`);
  const notAblated = lines.filter((l) => /^not_ablated: \d+$/.test(l));
  assert.deepEqual(notAblated, [`not_ablated: ${rep.not_ablated.length}`]);
  const estimateAt = lines.findIndex((l) => l.startsWith("estimate:"));
  assert.ok(estimateAt > unitsAt, "the estimate line comes after the counts");
  assert.equal(lines[lines.length - 1], lastLine(r.stdout), "the report path is last");
});

test("a mutant that loops forever is killed by a timeout and the script still exits 0", { skip }, () => {
  const r = spinRun();
  assert.equal(r.signal, null, `the script hung (${r.ms} ms): its process tree was not killed`);
  const rep = reportOf(r);
  const inc = unit(rep, "i++;");
  assert.deepEqual(inc.kills, [{ test: "*", kind: "timeout" }]);
  assert.equal(inc.status, "killed");
});

test("exit 2 with one stderr line and no report on each blind spot", { skip }, async (t) => {
  await t.test("no node_modules: the line names typescript and vitest, the project as <project>, no absolute path", () => {
    const dir = tempDir("ablation-bare-");
    writeFiles(dir, { "package.json": '{ "type": "module" }\n', "a.ts": "export const a = (): number => 1;\n" });
    const line = expectExit2(dir, ["--source", "a.ts"]);
    assert.match(line, /typescript/);
    assert.match(line, /vitest/);
    assert.ok(line.includes("<project>"), `the line does not name <project>: ${line}`);
    assertNoAbsolutePath(line, [dir]);
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

test("without --out the report lands in <os.tmpdir()>/test-ablation/<12 hex>.json (own dry run, report removed)", { skip }, () => {
  const existed = fs.existsSync(DEFAULT_REPORT_DIR);
  let p = "";
  try {
    const r = ablate(toy().dir, ["--source", "src/other.ts", "--tests", "src/other.test.ts", "--dry-run"], { defaultOut: true });
    reportOf(r);
    p = lastLine(r.stdout);
    assert.match(path.basename(p), /^[0-9a-f]{12}\.json$/);
    assert.equal(fs.realpathSync(path.dirname(p)), fs.realpathSync(DEFAULT_REPORT_DIR));
  } finally {
    if (p && path.isAbsolute(p) && path.basename(path.dirname(p)) === "test-ablation") fs.rmSync(p, { force: true });
    if (!existed) fs.rmSync(DEFAULT_REPORT_DIR, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------- spec 5: declarations keep their binding

// Unchanged by docs/audit-tests-effects.md: the TypeError is thrown in the source (effects 3).
test("a value dereferenced but never asserted stays in crash_only with only crash kills", { skip }, () => {
  const rep = reportOf(derefRun());
  const holder = unit(rep, "const holder = { inner: { value: v } };");
  assert.ok(rep.facts.crash_only.includes(holder.id), `${holder.id} not in crash_only`);
  assert.ok(holder.kills.length > 0, `${holder.id} has no kill`);
  for (const k of holder.kills) assert.equal(k.kind, "crash", `kills of ${holder.id}: ${JSON.stringify(holder.kills)}`);
});

// Effects 7. Replaces the PR #40 test that asserted `binding` kills on the `if`: the spec
// docs/audit-tests-effects.md flips it. The report does not carry the mutant text; the kill
// kind stands in for it: with `var hits;` kept, countHits(3) returns undefined and the
// assertion says so; with the binding removed, the source would throw a ReferenceError.
test("effects 7: removing the block of a var keeps the name: the if is killed by an assertion, the var too, no binding kill anywhere", { skip }, () => {
  const rep = reportOf(hoistRun());
  const block = unitStarting(rep, "if (n > 0)");
  assert.equal(block.status, "killed", `${block.id} is ${block.status}`);
  const kill = block.kills.find((k) => k.test === T("src/hoist.test.ts", "countHits returns the hits of a positive"));
  assert.ok(kill, `${block.id} is not killed by the countHits test: ${JSON.stringify(block.kills)}`);
  assert.equal(kill.kind, "assertion", `kills of ${block.id}: ${JSON.stringify(block.kills)}`);
  assert.ok(!rep.facts.crash_only.includes(block.id), `${block.id} is in crash_only`);
  const hits = unit(rep, "var hits = n;");
  assert.equal(hits.status, "killed", `${hits.id} is ${hits.status}`);
  assert.ok(hits.kills.some((k) => k.kind === "assertion"), `kills of ${hits.id}: ${JSON.stringify(hits.kills)}`);
  assert.deepEqual(allKills(rep).filter((k) => k.kind === "binding"), [], "binding kills");
});

// Effects 8. The test file's own ReferenceError on `hits` (first copy frame in the test file) is
// the test touching the changed value: test_error, and the audit goes on (exit 0).
test("effects 8: a test file that reads an undeclared hits itself: exit 0, the if is killed by that test with kind test_error", { skip }, () => {
  const rep = reportOf(hoistGlobalRun());
  assert.deepEqual(rep.tests, ["src/hoist-global.test.ts"]);
  const block = unitStarting(rep, "if (n > 0)");
  assert.equal(block.status, "killed", `${block.id} is ${block.status}`);
  const kill = block.kills.find((k) => k.test === T("src/hoist-global.test.ts", "hits is read by the test when countHits returns undefined"));
  assert.ok(kill, `${block.id} is not killed by the hoist-global test: ${JSON.stringify(block.kills)}`);
  assert.equal(kill.kind, "test_error", `kills of ${block.id}: ${JSON.stringify(block.kills)}`);
  assert.ok(!rep.facts.crash_only.includes(block.id), `${block.id} is in crash_only`);
});

// ---------------------------------------------------------------- effects 4 to 6: function-valued declarators

const FNVAL_T = (name) => T("src/fnval.test.ts", name);
const fnvalLine = (needle) => lineIn(FNVAL, needle);
const variableUnitsStarting = (rep, prefix) => unitsWhere(rep, (h) => h.startsWith(norm(prefix))).filter((u) => u.kind === "VariableStatement");
function expectFunctionValue(rep, needle) {
  const line = fnvalLine(needle);
  const entries = rep.not_ablated.filter((n) => n.start.line === line);
  assert.ok(
    entries.some((n) => n.reason === "function_value"),
    `no not_ablated entry with reason function_value on line ${line} (${needle}): ${JSON.stringify(entries)}`,
  );
}

test("effects 4: a local const bound to an arrow is not a unit, not_ablated says function_value, its body is a unit under helper, killed by the quad test", { skip }, () => {
  const rep = reportOf(fnvalRun());
  assert.deepEqual(variableUnitsStarting(rep, "const helper").map((u) => u.id), [], "VariableStatement units of const helper");
  expectFunctionValue(rep, "const helper = (x: number) => x * 2;");
  const body = unit(rep, "x * 2");
  assert.match(body.id, /(^|\/)helper\//, `the body unit is not under a scope named helper: ${body.id}`);
  assert.equal(body.parent, null, `the body of helper is walked like a function declaration's, no parent unit: ${body.parent}`);
  assert.equal(body.status, "killed", `${body.id} is ${body.status}`);
  assert.ok(body.kills.some((k) => k.test === FNVAL_T("quad applies helper twice")), `kills of ${body.id}: ${JSON.stringify(body.kills)}`);
});

test("effects 5: a statement mixing a value and an arrow is one unit that empties the value only, killed by an assertion; the arrow body is its own unit", { skip }, () => {
  const rep = reportOf(fnvalRun());
  const units = variableUnitsStarting(rep, "const a = 1, f = () => a");
  assert.equal(units.length, 1, `VariableStatement units starting with const a = 1, f = () => a: ${units.map((u) => u.id).join(", ")}`);
  const stmt = units[0];
  assert.equal(stmt.status, "killed", `${stmt.id} is ${stmt.status}`);
  const kill = stmt.kills.find((k) => k.test === FNVAL_T("pick returns a"));
  assert.ok(kill, `${stmt.id} is not killed by the pick test: ${JSON.stringify(stmt.kills)}`);
  assert.equal(kill.kind, "assertion", `an emptied f would throw in the source; kills of ${stmt.id}: ${JSON.stringify(stmt.kills)}`);
  const body = unit(rep, "a");
  assert.notEqual(body.parent, stmt.id, `the body of f is nested under the statement unit ${stmt.id}`);
  assert.equal(body.status, "killed", `${body.id} is ${body.status}`);
});

test("effects 6: a statement whose only non-function declarator is already empty is not a unit, not_ablated says function_value; the arrow body is a unit", { skip }, () => {
  const rep = reportOf(fnvalRun());
  assert.deepEqual(variableUnitsStarting(rep, "const z = 0, g = () => z").map((u) => u.id), [], "VariableStatement units of const z = 0, g = () => z");
  expectFunctionValue(rep, "const z = 0, g = () => z;");
  unit(rep, "z");
});

test("a declaration already empty is not_ablated already_empty, one without initializer no_initializer, neither a unit; no mutant is invalid", { skip }, () => {
  const expectNotAblated = (rep, text, needle, reason) => {
    const line = lineIn(text, needle);
    const entry = rep.not_ablated.find((n) => n.start.line === line);
    assert.ok(entry, `no not_ablated entry on line ${line} (${needle})`);
    assert.equal(entry.reason, reason, `reason of ${needle}`);
    assert.equal(unitsWhere(rep, (h) => h === norm(needle)).length, 0, `${needle} is a unit`);
  };
  const calc = reportOf(fullRun());
  expectNotAblated(calc, CALC, "let total = 0;", "already_empty");
  const spin = reportOf(spinRun());
  expectNotAblated(spin, SPIN, "let i = 0;", "already_empty");
  const hoist = reportOf(hoistRun());
  expectNotAblated(hoist, HOIST, "let last;", "no_initializer");
  for (const rep of [calc, spin, hoist]) {
    assert.deepEqual(rep.units.filter((u) => u.status === "invalid").map((u) => u.id), [], `invalid units of ${rep.source}`);
  }
});

// ---------------------------------------------------------------- specs 3 and 6: dry-run counts, the reach probe

test("--dry-run with every test failing in the baseline: exit 2, stdout carries units: N > 0 and not_ablated: M, no report", { skip }, () => {
  const out = path.join(tempDir("ablation-out-"), "report.json");
  const r = ablate(toy().dir, ["--source", "src/calc.ts", "--tests", "src/broken.test.ts", "--dry-run", "--out", out]);
  assert.equal(r.code, 2, `exit ${r.code}: ${r.stderr}`);
  assert.equal(r.stderr.split(/\r?\n/).filter((l) => l.trim() !== "").length, 1, `exactly one stderr line, got: ${r.stderr}`);
  const lines = r.stdout.split(/\r?\n/).map((l) => l.trim());
  const counts = lines.map((l) => /^units: (\d+)$/.exec(l)).filter(Boolean);
  assert.equal(counts.length, 1, `one units: N line in ${JSON.stringify(r.stdout)}`);
  assert.ok(Number(counts[0][1]) > 0, `units: ${counts[0][1]}`);
  assert.equal(lines.filter((l) => /^not_ablated: \d+$/.test(l)).length, 1, `one not_ablated: M line in ${JSON.stringify(r.stdout)}`);
  assert.equal(fs.existsSync(out), false, "no report is written on exit 2");
});

test("a test file that vi.mocks the source: exit 2, the reach probe recorded nothing", { skip }, () => {
  const line = expectExit2(toy().dir, ["--source", "src/mocked.ts", "--tests", "src/mocked.test.ts"]);
  assert.ok(line.includes("reach probe recorded nothing"), line);
});

// ---------------------------------------------------------------- spec 1: the supported range; spec 2: the exit-2 line

const STUB_SOURCE = {
  "package.json": '{ "type": "module" }\n',
  "src/one.ts": "export const one = (): number => 1;\n",
  "src/one.test.ts": 'import { test, expect } from "vitest";\nimport { one } from "./one";\ntest("one", () => expect(one()).toBe(1));\n',
};
const MARKER_BIN = [
  'import { writeFileSync } from "node:fs";',
  'if (process.env.ABLATION_STUB_MARKER) writeFileSync(process.env.ABLATION_STUB_MARKER, "the vitest stub ran");',
  "",
].join("\n");
// The shape of an uncaught CAC parse error, as Vitest 3 to 5 print it.
const CAC_BIN = [
  "const here = import.meta.url;",
  'const dir = here.slice(0, here.lastIndexOf("/"));',
  "const nl = String.fromCharCode(10);",
  "process.stderr.write([",
  '  here + ":404",',
  "  " + JSON.stringify("          throw new CACError(`Unknown option ${name}`);") + ",",
  "  " + JSON.stringify("                ^") + ",",
  '  "",',
  "  " + JSON.stringify("CACError: Unknown option `--x`") + ",",
  '  "    at Command.checkUnknownOptions (" + dir + "/cac.js:404:17)",',
  '  "    at CAC.runMatchedCommand (" + dir + "/cac.js:604:13)",',
  '  "    at " + dir + "/cli.js:10:5",',
  '  "",',
  '  "Node.js " + process.version,',
  "].join(nl) + nl);",
  "process.exitCode = 1;",
  "",
].join("\n");
// No error header at all: the line falls back to the first non-empty line, scrubbed.
const SILENT_BIN = [
  "const nl = String.fromCharCode(10);",
  'process.stderr.write(nl + "stub gave up in " + process.cwd() + nl);',
  "process.exitCode = 1;",
  "",
].join("\n");

// A project whose vitest is a stub package; its typescript is a junction to the primary toy's.
// Returns the dir and the junction, which the caller unlinks in `finally` before any cleanup.
function stubToy(version, bin) {
  const dir = tempDir("ablation-stub-");
  writeFiles(dir, {
    ...STUB_SOURCE,
    "node_modules/vitest/package.json": JSON.stringify({ name: "vitest", version, bin: { vitest: "stub.mjs" } }) + "\n",
    "node_modules/vitest/stub.mjs": bin,
  });
  const link = path.join(dir, "node_modules", "typescript");
  fs.symlinkSync(path.join(toy().dir, "node_modules", "typescript"), link, "junction");
  return { dir, link };
}

// Effects 10.
test("a vitest outside 3.1 to 5.x: exit 2, one line naming the version and the range 3.1 to 5.x, no Vitest run started", { skip }, async (t) => {
  for (const version of ["2.1.9", "6.0.0"]) {
    await t.test(`vitest ${version}`, () => {
      const { dir, link } = stubToy(version, MARKER_BIN);
      const marker = path.join(tempDir("ablation-marker-"), "ran.txt");
      try {
        const line = expectExit2(dir, ["--source", "src/one.ts"], { env: { ABLATION_STUB_MARKER: marker } });
        assert.ok(line.includes(version), `the line does not name ${version}: ${line}`);
        assert.ok(line.includes("3.1 to 5.x"), `the line does not name the range 3.1 to 5.x: ${line}`);
        assert.ok(!line.includes("--configLoader"), `the line names --configLoader, the 3.0 reason: ${line}`);
        assert.equal(fs.existsSync(marker), false, "the vitest bin was run");
      } finally {
        fs.unlinkSync(link);
      }
    });
  }
});

// Effects 9: 3.0 writes node_modules/.vite-temp into the project, so it is refused before any run.
test("effects 9: vitest 3.0.0 is refused: exit 2, the line gives the 3.0 reason, no Vitest run started", { skip }, () => {
  const { dir, link } = stubToy("3.0.0", MARKER_BIN);
  const marker = path.join(tempDir("ablation-marker-"), "ran.txt");
  try {
    const line = expectExit2(dir, ["--source", "src/one.ts"], { env: { ABLATION_STUB_MARKER: marker } });
    const expected =
      "vitest 3.0.0 is not supported: 3.1 to 5.x (3.0 has no --configLoader and writes node_modules/.vite-temp into the project)";
    assert.ok(line.endsWith(expected), `the line does not end with ${JSON.stringify(expected)}: ${line}`);
    assert.equal(fs.existsSync(marker), false, "the vitest bin was run");
  } finally {
    fs.unlinkSync(link);
  }
});

// Effects 11: 3.1.0 is inside the range: the stub runs (and writes no report, hence the exit 2).
test("effects 11: vitest 3.1.0 is not refused for its version: the stub runs and the line does not say not supported", { skip }, () => {
  const { dir, link } = stubToy("3.1.0", MARKER_BIN);
  const marker = path.join(tempDir("ablation-marker-"), "ran.txt");
  try {
    const line = expectExit2(dir, ["--source", "src/one.ts"], { env: { ABLATION_STUB_MARKER: marker } });
    assert.ok(!line.includes("not supported"), `3.1.0 is refused: ${line}`);
    assert.equal(fs.existsSync(marker), true, "the vitest bin was not run");
  } finally {
    fs.unlinkSync(link);
  }
});

test("a Vitest that refuses its arguments: the exit-2 line quotes the CACError, with no absolute path", { skip }, () => {
  const { dir, link } = stubToy("3.2.7", CAC_BIN);
  try {
    const line = expectExit2(dir, ["--source", "src/one.ts"]);
    assert.ok(line.includes("CACError: Unknown option"), `the line does not quote the error: ${line}`);
    assert.ok(line.includes("--x"), `the line does not name the option: ${line}`);
    assertNoAbsolutePath(line, [dir]);
  } finally {
    fs.unlinkSync(link);
  }
});

// Spec 2 requirement the plan's list does not name: with no error header, the fallback line is scrubbed too.
test("a Vitest that fails without an error header: the exit-2 line is its first line, with no absolute path", { skip }, () => {
  const { dir, link } = stubToy("3.2.7", SILENT_BIN);
  try {
    const line = expectExit2(dir, ["--source", "src/one.ts"]);
    assert.ok(line.includes("stub gave up in"), `the line is not the first non-empty line: ${line}`);
    assertNoAbsolutePath(line, [dir]);
  } finally {
    fs.unlinkSync(link);
  }
});

// ---------------------------------------------------------------- spec 1: every supported major (plan test 2)

for (const m of EXTRA_MAJORS) {
  test(`vitest ${m.version} (vite ${m.vite}): facts buckets, determinism, project and node_modules untouched`, { skip: m.skip }, async (t) => {
    const tv = m.toy();
    if (tv.npmError) {
      t.skip(`npm could not install vitest@${m.version}: ${tv.npmError.split(/\r?\n/)[0]}`);
      return;
    }
    await t.test("facts buckets and tool_versions", () => {
      const r = m.runs.first();
      const rep = reportOf(r);
      assertFactBuckets(rep);
      assertTestFacts(rep, r.raw);
      assert.deepEqual(rep.tool_versions, { node: process.versions.node, typescript: m.typescript, vitest: m.version });
    });
    // Effects 12: the stack of failureMessages is read on this major too.
    await t.test("effects 12: return box; is killed by makeBox holds its value with kind test_error and is not crash_only", () => {
      assertReturnBoxTestError(reportOf(m.runs.first()));
    });
    await t.test("two runs give byte-identical reports once meta is removed, with no absolute path", () => {
      assertDeterministic(m.runs.first(), m.runs.rest().run, tv.dir);
    });
    await t.test("the project, its node_modules (.vite-temp included) and os.tmpdir() are unchanged, an exit-2 run included", () => {
      assertUntouched(tv, m.runs.first(), m.runs.rest());
    });
  });
}

// ---------------------------------------------------------------- spec 2: a config that fails to load (plan test 10)

test("a vitest.config.ts importing a missing module: exit 2, one line naming missing-module, no absolute path", async (t) => {
  const cases = [
    { label: "vitest 3.2.7", skip: toyOf("3.2.7").skip, toyFn: toyOf("3.2.7").toy },
    { label: "vitest 5.0.4", skip, toyFn: toy },
  ];
  for (const c of cases) {
    await t.test(c.label, { skip: c.skip }, (st) => {
      const tv = c.toyFn();
      if (tv.npmError) {
        st.skip(`npm could not install the toy of ${c.label}`);
        return;
      }
      const dir = tempDir("ablation-cfgfail-");
      writeFiles(dir, { ...TOY_FILES, "vitest.config.ts": BROKEN_CONFIG });
      const link = path.join(dir, "node_modules");
      fs.symlinkSync(path.join(tv.dir, "node_modules"), link, "junction");
      try {
        const line = expectExit2(dir, ["--source", "src/calc.ts", "--tests", "src/calc.test.ts"]);
        assert.ok(line.includes("missing-module"), `the line does not name missing-module: ${line}`);
        assertNoAbsolutePath(line, [dir, tv.dir]);
      } finally {
        fs.unlinkSync(link); // the junction first, so no cleanup ever walks into the toy's node_modules
      }
    });
  }
});

// ---------------------------------------------------------------- the prompt files (unchanged)

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

// ---------------------------------------------------------------- spec 4: nothing left behind (must stay last)

test("after the whole file, os.tmpdir() holds no new test-ablation or ablation- entry and no report of the file under test-ablation/", () => {
  runCleanup();
  const added = fs
    .readdirSync(os.tmpdir())
    .filter((n) => (n.startsWith("test-ablation") || n.startsWith("ablation-")) && !TMP_BEFORE.includes(n));
  assert.deepEqual(added, [], "entries this file left in os.tmpdir()");
  const reports = fs.existsSync(DEFAULT_REPORT_DIR) ? fs.readdirSync(DEFAULT_REPORT_DIR) : [];
  assert.deepEqual(reports.filter((n) => !REPORTS_BEFORE.includes(n)), [], "reports this file left in <tmpdir>/test-ablation");
});
