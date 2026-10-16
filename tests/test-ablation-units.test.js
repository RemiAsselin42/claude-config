// Unit-level checks of the two parsers of scripts/test-ablation.cjs, fed by hand what the
// acceptance tests (tests/test-ablation.test.js, frozen by their commit) do not reach:
//   - errorFile: every stack-frame spelling Vitest 3, 4 and 5 print (native and forward-slash
//     paths, file:/// URLs, percent-encoded roots, `async` frames, a ` (` inside a path,
//     node:internal and node_modules frames first, the realpath root, no usable frame);
//   - collectUnits on snippets that need no Vitest run: function-valued declarators behind
//     as / satisfies / ! / parentheses, class and function expressions, exported mixed
//     statements, the `var a, b;` replacement (sorted, binding patterns, for heads, labels)
//     and varNames stopping at nested functions and classes.
// The script exports those pieces when it is required rather than run. collectUnits needs
// typescript: installed once by npm into a temp dir (typescript@6.0.3, the toys' version),
// skipped when npm is unavailable. Runs under `node --test tests/*.test.js` (ci.yml).
"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REPO = path.resolve(__dirname, "..");
const WIN = process.platform === "win32";
const { parseFile, collectUnits, mutantSource, errorFile } = require(path.join(REPO, "scripts", "test-ablation.cjs"));

// ---------------------------------------------------------------- errorFile

// A copy root in the platform's own spelling, as parseResults builds it (posix, trailing /).
const ROOT = WIN ? "C:/Users/u/AppData/Local/Temp/test-ablation-abc" : "/tmp/test-ablation-abc";
const NATIVE = WIN ? ROOT.replace(/\//g, "\\") : ROOT;
const URL = `file://${WIN ? "/" : ""}${ROOT}`;
const fold = (s) => (WIN ? s.toLowerCase() : s);
const roots = (...rs) => rs.map((r) => `${r}/`);
const msg = (...frames) => ["TypeError: Cannot read properties of undefined (reading 'value')", ...frames.map((f) => `    at ${f}`)].join("\n");
const file = (m, rs = roots(ROOT)) => errorFile(m, rs, fold);

test("errorFile: a test-file frame in the 4.x/5.x spelling (forward slashes) and in the 3.x spelling (native)", () => {
  assert.equal(file(msg(`${ROOT}/src/a.test.ts:5:20`)), "src/a.test.ts");
  assert.equal(file(msg(`${NATIVE}${WIN ? "\\" : "/"}src${WIN ? "\\" : "/"}a.test.ts:5:19`)), "src/a.test.ts");
  assert.equal(file(msg(`check (${ROOT}/src/a.test.ts:20:38)`, `${ROOT}/src/a.test.ts:21:3`)), "src/a.test.ts");
});

test("errorFile: the first frame inside the copy wins: the source before the test, node:internal and node_modules skipped", () => {
  assert.equal(file(msg(`peek (${ROOT}/src/a.ts:6:17)`, `${ROOT}/src/a.test.ts:8:3`)), "src/a.ts");
  assert.equal(file(msg("processTicksAndRejections (node:internal/process/task_queues:103:5)", `${ROOT}/src/a.test.ts:17:3`)), "src/a.test.ts");
  assert.equal(file(msg(`${URL}/node_modules/@vitest/runner/dist/chunk-hooks.js:155:11`, `${ROOT}/src/a.test.ts:5:20`)), "src/a.test.ts");
  assert.equal(file(msg(`${ROOT}/node_modules/lib/index.js:1:1`, `${ROOT}/src/a.test.ts:5:20`)), "src/a.test.ts");
  assert.equal(file(msg(`later (${ROOT}/src/a.ts:15:12)`, "process.processTicksAndRejections (node:internal/process/task_queues:103:5)", `${ROOT}/src/a.test.ts:17:3`)), "src/a.ts");
});

test("errorFile: an anonymous `async` frame, and a ` (` inside the path, in both forms", () => {
  assert.equal(file(msg(`async fetchJson (${URL}/node_modules/lib/index.js:10:5)`, `async ${ROOT}/src/a.test.ts:5:3`)), "src/a.test.ts");
  const odd = `${ROOT} (x)`;
  assert.equal(file(msg(`${odd}/src/a.test.ts:12:20`), roots(odd)), "src/a.test.ts");
  assert.equal(file(msg(`check (${odd}/src/a.test.ts:20:38)`), roots(odd)), "src/a.test.ts");
});

test("errorFile: a file:/// URL of a root holding a space is percent-decoded; the realpath root counts too", () => {
  const spaced = `${ROOT} b`;
  const spacedUrl = `file://${WIN ? "/" : ""}${ROOT}%20b`;
  assert.equal(file(msg(`${spacedUrl}/node_modules/lib/index.js:1:1`, `${spaced}/src/a.test.ts:1:1`), roots(spaced)), "src/a.test.ts");
  assert.equal(file(msg(`${spacedUrl}/src/a.test.ts:1:1`), roots(spaced)), "src/a.test.ts");
  const real = `${ROOT}-real`;
  assert.equal(file(msg(`${real}/src/a.ts:2:2`), roots(ROOT, real)), "src/a.ts");
});

test("errorFile: null without a usable frame, or with frames outside the copy only", () => {
  assert.equal(file(msg("new Promise (<anonymous>)")), null);
  assert.equal(file(msg()), null);
  assert.equal(file(""), null);
  assert.equal(file(msg(`${WIN ? "D:" : ""}/other/src/a.test.ts:1:1`)), null);
  assert.equal(file(msg(`${ROOT}-other/src/a.test.ts:1:1`)), null, "a sibling with the root as prefix is not the root");
});

test("errorFile: on Windows the drive letter's case does not matter", { skip: !WIN }, () => {
  assert.equal(file(msg(`c:/users/u/appdata/local/temp/test-ablation-abc/src/a.test.ts:5:20`)), "src/a.test.ts");
});

// ---------------------------------------------------------------- collectUnits

const npmWorks = spawnSync("npm", ["--version"], { encoding: "utf8", shell: WIN }).status === 0;
const skip = npmWorks ? false : "npm not available";
let tsDir = null;
let tsMod = null;
function tsLib() {
  if (tsMod) return tsMod;
  tsDir = fs.mkdtempSync(path.join(os.tmpdir(), "units-ts-")); // not a prefix the acceptance file counts as its own residue
  fs.writeFileSync(path.join(tsDir, "package.json"), '{ "private": true }\n');
  const r = spawnSync("npm", ["install", "--no-audit", "--no-fund", "--silent", "typescript@6.0.3"], { cwd: tsDir, encoding: "utf8", shell: WIN });
  assert.equal(r.status, 0, `npm install typescript: ${r.stdout}${r.stderr}`);
  tsMod = require(path.join(tsDir, "node_modules", "typescript"));
  return tsMod;
}
after(() => {
  if (tsDir) fs.rmSync(tsDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
});

function unitsOf(lines) {
  const src = lines.join("\n") + "\n";
  const ts = tsLib();
  const { sf, diags } = parseFile(ts, "src/x.ts", src);
  assert.deepEqual(diags, [], "the snippet parses");
  const r = collectUnits(ts, sf, src);
  const byId = (id) => {
    const u = r.units.find((x) => x.id === id);
    assert.ok(u, `no unit ${id}; units: ${r.units.map((x) => x.id).join(", ")}`);
    return u;
  };
  const reasonAt = (line) => r.notAblated.filter((n) => n.start.line === line).map((n) => n.reason);
  const parses = (u) => parseFile(ts, "src/x.ts", mutantSource(src, u)).diags.length === 0;
  return { ...r, ids: r.units.map((u) => u.id), byId, reasonAt, mutant: (u) => mutantSource(src, u), parses };
}

test("collectUnits: a function-valued declarator is not a unit, its body is, under the binding's name, with no parent", { skip }, () => {
  const r = unitsOf(["const helper = (x: number) => x * 2;", "export function quad(x: number): number {", "  return helper(helper(x));", "}"]);
  assert.deepEqual(r.reasonAt(1), ["function_value"]);
  assert.deepEqual(r.ids, ["helper/expr:BinaryExpression", "quad/0:ReturnStatement"]);
  const body = r.byId("helper/expr:BinaryExpression");
  assert.equal(body.parent, null);
  assert.equal(body.replacement, "(void 0)");
});

test("collectUnits: as, satisfies, !, parentheses, a function expression and a class expression are unwrapped; the scope is the binding, not the function's own name", { skip }, () => {
  const r = unitsOf([
    "const w = ((x: number) => x) as (x: number) => number;",
    "const s = (() => 1) satisfies () => number;",
    "const nn = (function named() { return 2; })!;",
    "const C = class { m() { return 1; } };",
    "const p = (((y: number) => y));",
  ]);
  for (const line of [1, 2, 3, 4, 5]) assert.deepEqual(r.reasonAt(line), ["function_value"], `line ${line}`);
  assert.deepEqual(r.ids, ["w/expr:Identifier", "s/expr:NumericLiteral", "nn/0:ReturnStatement", "C.m/0:ReturnStatement", "p/expr:Identifier"]);
  for (const u of r.units) assert.equal(u.parent, null, u.id);
});

test("collectUnits: a statement mixing a value and an arrow is one unit emptying the value only; the arrow body is a separate unit", { skip }, () => {
  const r = unitsOf(["export function pick(): number {", "  const a = 1, f = () => a;", "  return f();", "}"]);
  assert.deepEqual(r.ids, ["pick/0:VariableStatement", "pick/f/expr:Identifier", "pick/1:ReturnStatement"]);
  const stmt = r.byId("pick/0:VariableStatement");
  assert.equal(stmt.replacement, "const a = 0, f = () => a;");
  assert.equal(r.byId("pick/f/expr:Identifier").parent, null);
  assert.ok(r.parses(stmt));
});

test("collectUnits: the reasons function_value, no_initializer, already_empty", { skip }, () => {
  const r = unitsOf(["const z = 0, g = () => z;", "let q;", "const e = 0;", "const fq = () => 1, nope;"]);
  assert.deepEqual(r.reasonAt(1), ["function_value"]);
  assert.deepEqual(r.reasonAt(2), ["no_initializer"]);
  assert.deepEqual(r.reasonAt(3), ["already_empty"]);
  assert.deepEqual(r.reasonAt(4), ["function_value"], "nothing left to empty beside a function-valued declarator");
  assert.deepEqual(r.ids, ["g/expr:Identifier", "fq/expr:NumericLiteral"]);
});

test("collectUnits: an exported statement: values are export_value, never units; function-valued declarators are walked, wrapped or not", { skip }, () => {
  const r = unitsOf(["export const a = 1, f = () => a;", "export const k = (() => 1) as any;", "export const v = 1;", "export const K = class { n() { return 3; } };"]);
  assert.deepEqual(r.reasonAt(1), ["export_value"]);
  assert.deepEqual(r.reasonAt(2), [], "an exported function value is walked and not listed");
  assert.deepEqual(r.reasonAt(3), ["export_value"]);
  assert.deepEqual(r.reasonAt(4), []);
  assert.deepEqual(r.ids, ["f/expr:Identifier", "k/expr:NumericLiteral", "K.n/0:ReturnStatement"]);
  assert.deepEqual(r.exports, ["K", "a", "f", "k", "v"]);
});

test("collectUnits: a removed statement keeps the var names its span hoists: sorted, binding patterns, for heads, labels; a var statement keeps its own emptied form", { skip }, () => {
  const r = unitsOf([
    "export function h(c: boolean, o: { a: number; b: number[] }): number {",
    "  if (c) {",
    "    var b = 1;",
    "    for (var a = 0; a < 1; a++) {}",
    "  }",
    "  if (o) {",
    "    var { a: d, b: [e] } = o;",
    "  }",
    "  outer: for (var i of [1]) {",
    "    break outer;",
    "  }",
    "  return a + b + d + e + i;",
    "}",
  ]);
  const first = r.byId("h/0:IfStatement");
  assert.equal(first.replacement, "var a, b;");
  assert.deepEqual([...first.declares].sort(), ["a", "b"]);
  assert.ok(r.mutant(first).includes("var a, b;"));
  assert.ok(r.parses(first));
  assert.equal(r.byId("h/0/then/1:ForStatement").replacement, "var a;");
  assert.equal(r.byId("h/0/then/0:VariableStatement").replacement, "var b = 0;");
  assert.equal(r.byId("h/1:IfStatement").replacement, "var d, e;");
  assert.equal(r.byId("h/2:LabeledStatement").replacement, "var i;");
  const forOf = r.units.find((u) => u.kind === "ForOfStatement");
  assert.equal(forOf.replacement, "var i;");
  assert.ok(r.parses(forOf), "`outer: var i;` parses");
});

test("collectUnits: a var inside a nested function or class is that scope's own: the enclosing statement is replaced by `;`", { skip }, () => {
  const r = unitsOf([
    "export function v(c: boolean): number {",
    "  let y = 1;",
    "  if (c) {",
    "    const g = function () { var y = 2; return y; };",
    "    y = g();",
    "  }",
    "  if (c) {",
    "    const K = class { static { var s = 1; } m() { var t = 1; return t; } };",
    "    y = new K().m();",
    "  }",
    "  if (c) {",
    "    y = (() => { var z = 3; return z; })();",
    "  }",
    "  return y;",
    "}",
  ]);
  for (const id of ["v/1:IfStatement", "v/2:IfStatement", "v/3:IfStatement"]) {
    const u = r.byId(id);
    assert.equal(u.replacement, ";", id);
    assert.deepEqual([...u.declares], [], id);
  }
  assert.equal(r.byId("v/1/then/g/0:VariableStatement").replacement, "var y = 0;", "the nested function's own var is a unit of its own scope");
});
