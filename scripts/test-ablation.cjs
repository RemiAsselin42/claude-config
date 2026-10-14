#!/usr/bin/env node
// test-ablation.cjs — statement ablation audit of one TypeScript source under Vitest.
//
// For one source file and the Vitest tests that import it: neutralize one
// statement at a time in a throwaway copy of the project, run the tests, record
// which tests fail, restore. The result is a statement × failing-tests matrix;
// the report's `facts` are derived from it and never say "useless" or "dead":
// that is the test-auditor agent's reading (/audit-tests).
//
//   node test-ablation.cjs --source <file.ts> [--project <dir>] [--tests <file>...]
//                          [--out <report.json>] [--baseline-runs 2] [--dry-run]
//
// Exit 0: report written (findings or not: an audit, not a gate).
// Exit 2: blind spot or usage error, one stderr line naming it: typescript or
//         vitest unresolvable from the project, source syntax error, no stable
//         passing test, reach run differing from the baseline, project modified.
// stdout: one count per `facts` bucket (a dry run: the units and the estimate),
//         then the report path, alone, last.
//
// typescript and vitest come from the audited project (require.resolve with
// paths: [project]); this script has no dependency of its own. typescript 7,
// the native port, has no JS parser API: the project needs typescript@6 as a
// devDependency. The real project is never written: Vitest runs in a temp copy
// whose node_modules is a junction (works on Windows without admin rights) with
// its caches inside the copy, and the copy is removed on exit, error paths
// included. A dry run still runs the baseline (for the estimate) and nothing
// else; its units carry status "not_run".
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn, spawnSync, execFileSync } = require("node:child_process");

const WIN = process.platform === "win32";
const SKIP_DIRS = new Set([".git", "node_modules", "dist", "build", "coverage", ".test-ablation"]);
const TEST_FILE = /\.(test|spec)\.(ts|tsx|mts|cts|js|mjs)$/;
const MISSING_SYMBOL = /is not a function|is not a constructor|is not defined|does not provide an export named|Cannot find module|Failed to resolve import|Failed to load url/;
const BASELINE_TIMEOUT_MS = 300000;
const REACH_ENV = "TEST_ABLATION_REACH";

class Fail extends Error {}
const fail = (msg) => { throw new Fail(msg); };
const sha1 = (s) => crypto.createHash("sha1").update(s).digest("hex");
const posix = (p) => p.split(path.sep).join("/");
const norm = (p) => (WIN ? path.resolve(p).toLowerCase() : path.resolve(p));
const realpathOr = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
const firstLine = (s) => String(s || "").split(/\r?\n/).find((l) => l.trim()) || "";
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// ---------------------------------------------------------------- arguments
function parseArgs(argv) {
  const o = { source: null, project: null, tests: [], out: null, baselineRuns: 2, dryRun: false };
  const usage = "usage: node test-ablation.cjs --source <file.ts> [--project <dir>] [--tests <file>...] [--out <report.json>] [--baseline-runs 2] [--dry-run]";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const value = () => { if (i + 1 >= argv.length || argv[i + 1].startsWith("--")) fail(`${usage} (${a} needs a value)`); return argv[++i]; };
    if (a === "--source") o.source = value();
    else if (a === "--project") o.project = value();
    else if (a === "--out") o.out = value();
    else if (a === "--dry-run") o.dryRun = true;
    else if (a === "--baseline-runs") {
      o.baselineRuns = Number(value());
      if (!Number.isInteger(o.baselineRuns) || o.baselineRuns < 1) fail(`${usage} (--baseline-runs needs a positive integer)`);
    } else if (a === "--tests") {
      while (i + 1 < argv.length && !argv[i + 1].startsWith("--")) o.tests.push(argv[++i]);
      if (!o.tests.length) fail(`${usage} (--tests needs at least one file)`);
    } else fail(`${usage} (unknown argument ${a})`);
  }
  if (!o.source) fail(usage);
  return o;
}

function relInside(root, abs, what) {
  const rel = path.relative(root, abs);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) fail(`${what} ${abs} is not inside the project ${root}`);
  return posix(rel);
}
function findProject(fromDir) {
  for (let d = fromDir; ; d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, "package.json"))) return d;
    if (path.dirname(d) === d) return null;
  }
}

// ---------------------------------------------------------------- the project's tools
function resolveTools(project) {
  const problems = [];
  const own = (name) => fs.existsSync(path.join(project, "node_modules", name, "package.json"));
  let ts = null;
  try {
    const mod = require(require.resolve("typescript", { paths: [project] }));
    if (typeof mod.createSourceFile !== "function") problems.push(`typescript ${mod.version || "?"} has no JS compiler API (createSourceFile): add typescript@6 as a devDependency`);
    else if (!own("typescript")) problems.push(`typescript resolved outside ${posix(project)}/node_modules (hoisted or workspace install): not supported`);
    else ts = mod;
  } catch { problems.push(`typescript not found from ${posix(project)}`); }
  let vitest = null;
  try {
    const pkgPath = require.resolve("vitest/package.json", { paths: [project] });
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    const binRel = typeof pkg.bin === "string" ? pkg.bin : pkg.bin && pkg.bin.vitest;
    if (!binRel) problems.push(`vitest ${pkg.version}: no bin in its package.json`);
    else if (!own("vitest")) problems.push(`vitest resolved outside ${posix(project)}/node_modules (hoisted or workspace install): not supported`);
    else vitest = { version: pkg.version, bin: path.join(path.dirname(pkgPath), binRel) };
  } catch { problems.push(`vitest not found from ${posix(project)}`); }
  if (problems.length) fail(problems.join("; "));
  return { ts, vitest };
}

// ---------------------------------------------------------------- parsing
function scriptKind(ts, file) {
  if (/\.tsx$/i.test(file)) return ts.ScriptKind.TSX;
  if (/\.(ts|mts|cts)$/i.test(file)) return ts.ScriptKind.TS;
  if (/\.jsx$/i.test(file)) return ts.ScriptKind.JSX;
  return ts.ScriptKind.JS;
}
function parseFile(ts, file, text) {
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, scriptKind(ts, file));
  return { sf, diags: sf.parseDiagnostics || [] };
}
function diagLine(ts, sf, d) {
  const { line, character } = sf.getLineAndCharacterOfPosition(d.start || 0);
  return `${ts.flattenDiagnosticMessageText(d.messageText, " ")} (${line + 1}:${character + 1})`;
}

// ---------------------------------------------------------------- ablation units
// A unit: a statement (replaced by `;`) or the expression body of an arrow
// (replaced by `(void 0)`). Declarations are not units but their bodies are
// walked. Ids: <scope chain>/<child index path>:<SyntaxKind>; a declaration
// starts a scope named after it, a unit keeps its path and names the functions
// nested in it (`f` for a named one, `fn<k>` otherwise).
function collectUnits(ts, sf, text) {
  const K = ts.SyntaxKind;
  const units = [];
  const notAblated = [];
  const exports = new Set();
  let exportsComplete = true;
  const kindName = (n) => K[n.kind];
  const lc = (p) => { const x = sf.getLineAndCharacterOfPosition(p); return { line: x.line + 1, col: x.character + 1 }; };
  const modifiers = (n) => (ts.canHaveModifiers(n) && ts.getModifiers(n)) || [];
  const hasMod = (n, m) => modifiers(n).some((x) => x.kind === m);
  const isFnLike = (n) => ts.isArrowFunction(n) || ts.isFunctionExpression(n);
  const isMemberFn = (n) => ts.isMethodDeclaration(n) || ts.isConstructorDeclaration(n) || ts.isGetAccessorDeclaration(n) || ts.isSetAccessorDeclaration(n);
  const nameText = (name) => (name && (ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name) || ts.isPrivateIdentifier(name)) ? name.text : null);
  const na = (n, reason) => notAblated.push({ start: lc(n.getStart(sf)), kind: kindName(n), reason });

  function addUnit(node, segs, parent, opts) {
    const pos = node.getStart(sf), endPos = node.getEnd();
    const normText = text.slice(pos, endPos).replace(/\s+/g, " ").trim();
    const u = {
      id: `${segs.join("/")}:${opts.kind || kindName(node)}`, parentUnit: parent, kind: opts.kind || kindName(node),
      pos, endPos, start: lc(pos), end: lc(endPos), text_head: normText.slice(0, 80), text_sha1: sha1(normText).slice(0, 12),
      flags: opts.flags || [], replacement: opts.replacement, probe: opts.probe, probePos: opts.probePos === undefined ? pos : opts.probePos,
    };
    units.push(u);
    return u;
  }
  function consoleCall(st) {
    if (!ts.isExpressionStatement(st)) return false;
    let e = st.expression;
    if (ts.isAwaitExpression(e)) e = e.expression;
    if (!ts.isCallExpression(e)) return false;
    for (e = e.expression; ; ) {
      if (ts.isPropertyAccessExpression(e) || ts.isElementAccessExpression(e) || ts.isCallExpression(e) || ts.isNonNullExpression(e)) e = e.expression;
      else return ts.isIdentifier(e) && e.text === "console";
    }
  }
  // Function-likes nested in the expressions of `node`, skipping the statement
  // children handled elsewhere; each one's body becomes a nested scope.
  function scanFnLikes(node, segs, parent, skip) {
    let k = 0;
    const nameFor = (n) => {
      if (n.name && nameText(n.name)) return nameText(n.name);
      const p = n.parent;
      if (p && (ts.isVariableDeclaration(p) || ts.isPropertyAssignment(p) || ts.isPropertyDeclaration(p)) && nameText(p.name)) return nameText(p.name);
      return `fn${k++}`;
    };
    (function walk(n) {
      if (skip && skip.has(n)) return;
      if (isFnLike(n) || (isMemberFn(n) && ts.isObjectLiteralExpression(n.parent))) return fnBody(n, [...segs, nameFor(n)], parent);
      if (ts.isClassExpression(n)) return classMembers(n, segs, parent);
      ts.forEachChild(n, walk);
    })(node);
  }
  function fnBody(fn, segs, parent) {
    if (!fn.body) return;
    if (ts.isBlock(fn.body)) return statements(fn.body.statements, segs, parent);
    const u = addUnit(fn.body, [...segs, "expr"], parent, { kind: kindName(fn.body), replacement: "(void 0)", probe: "expr" });
    scanFnLikes(fn.body, [...segs, "expr"], u, null);
  }
  function classMembers(cls, segs, parent) {
    const cname = (cls.name && cls.name.text) || "class";
    for (const m of cls.members) {
      if (ts.isClassStaticBlockDeclaration(m)) statements(m.body.statements, [...segs, `${cname}.static`], parent);
      else if (isMemberFn(m) && m.body) statements(m.body.statements, [...segs, `${cname}.${ts.isConstructorDeclaration(m) ? "constructor" : nameText(m.name) || "member"}`], parent);
      else if (ts.isPropertyDeclaration(m) && m.initializer) {
        const segs2 = [...segs, `${cname}.${nameText(m.name) || "member"}`];
        if (isFnLike(m.initializer)) fnBody(m.initializer, segs2, parent);
        else scanFnLikes(m.initializer, segs2, parent, null);
      }
    }
  }
  function statements(list, segs, parent) {
    let prologue = true;
    list.forEach((st, i) => {
      if (prologue && ts.isExpressionStatement(st) && ts.isStringLiteral(st.expression)) return na(st, "prologue");
      prologue = false;
      statement(st, [...segs, String(i)], parent, "before");
    });
  }
  // `body`: the single statement under if/else/loop/label: a block is walked
  // in place, anything else is one wrapped unit (probe `{ probe; unit }`); the
  // probe of a labeled statement's body goes before the label.
  function body(st, segs, parent, label) {
    if (ts.isBlock(st)) return statements(st.statements, segs, parent);
    statement(st, [...segs, "0"], parent, label ? "before" : "wrap", label ? label.getStart(sf) : undefined);
  }
  function declaredExports(st) {
    if (!hasMod(st, K.ExportKeyword)) return;
    if (hasMod(st, K.DefaultKeyword)) return exports.add("default");
    if (ts.isVariableStatement(st)) {
      const names = (b) => { if (ts.isIdentifier(b)) exports.add(b.text); else if (ts.isObjectBindingPattern(b) || ts.isArrayBindingPattern(b)) for (const e of b.elements) if (e.name) names(e.name); };
      for (const d of st.declarationList.declarations) names(d.name);
    } else if (st.name && !ts.isInterfaceDeclaration(st) && !ts.isTypeAliasDeclaration(st)) exports.add(st.name.text);
  }
  function statement(st, segs, parent, probe, probePos) {
    const top = parent === null && segs.length === 1;
    if (top) declaredExports(st);
    if (ts.isImportDeclaration(st) || ts.isImportEqualsDeclaration(st)) return na(st, "import");
    if (ts.isExportAssignment(st)) { exports.add("default"); return na(st, "export"); }
    if (ts.isExportDeclaration(st)) {
      if (st.exportClause && ts.isNamedExports(st.exportClause)) for (const e of st.exportClause.elements) exports.add(e.name.text);
      else if (st.exportClause && ts.isNamespaceExport(st.exportClause)) exports.add(st.exportClause.name.text);
      else exportsComplete = false;
      return na(st, "export");
    }
    if (ts.isEmptyStatement(st)) return na(st, "empty");
    if (hasMod(st, K.DeclareKeyword)) return na(st, "declare");
    if (ts.isInterfaceDeclaration(st) || ts.isTypeAliasDeclaration(st)) return na(st, "type");
    if (ts.isEnumDeclaration(st)) return na(st, "enum");
    if (ts.isModuleDeclaration(st)) return na(st, "namespace");
    const scope = segs.slice(0, -1);
    if (ts.isFunctionDeclaration(st)) return st.body && statements(st.body.statements, [...scope, st.name ? st.name.text : "default"], parent);
    if (ts.isClassDeclaration(st)) return classMembers(st, scope, parent);
    if (ts.isVariableStatement(st) && hasMod(st, K.ExportKeyword)) {
      const decls = st.declarationList.declarations;
      if (!decls.length || !decls.every((d) => d.initializer && isFnLike(d.initializer))) return na(st, "export_value");
      for (const d of decls) fnBody(d.initializer, [...scope, nameText(d.name) || "fn"], parent);
      return;
    }
    const u = addUnit(st, segs, parent, { replacement: ";", probe, probePos, flags: consoleCall(st) ? ["side_effect_only"] : [] });
    const skip = new Set();
    if (ts.isIfStatement(st)) {
      skip.add(st.thenStatement); body(st.thenStatement, [...segs, "then"], u);
      if (st.elseStatement) { skip.add(st.elseStatement); body(st.elseStatement, [...segs, "else"], u); }
    } else if (ts.isForStatement(st) || ts.isForInStatement(st) || ts.isForOfStatement(st) || ts.isWhileStatement(st) || ts.isDoStatement(st)) {
      skip.add(st.statement); body(st.statement, [...segs, "body"], u);
    } else if (ts.isLabeledStatement(st)) {
      skip.add(st.statement); body(st.statement, [...segs, "body"], u, st);
    } else if (ts.isSwitchStatement(st)) {
      st.caseBlock.clauses.forEach((c, k) => { c.statements.forEach((s) => skip.add(s)); statements(c.statements, [...segs, `case${k}`], u); });
    } else if (ts.isTryStatement(st)) {
      skip.add(st.tryBlock); statements(st.tryBlock.statements, [...segs, "try"], u);
      if (st.catchClause) { skip.add(st.catchClause.block); statements(st.catchClause.block.statements, [...segs, "catch"], u); }
      if (st.finallyBlock) { skip.add(st.finallyBlock); statements(st.finallyBlock.statements, [...segs, "finally"], u); }
    } else if (ts.isBlock(st)) {
      st.statements.forEach((s) => skip.add(s)); statements(st.statements, segs, u);
    }
    scanFnLikes(st, segs, u, skip);
  }
  statements(sf.statements, [], null);

  units.sort((a, b) => a.pos - b.pos || b.endPos - a.endPos);
  const seen = new Map();
  for (const u of units) { const n = (seen.get(u.id) || 0) + 1; seen.set(u.id, n); if (n > 1) u.id += ` #${n}`; }
  for (const u of units) u.parent = u.parentUnit ? u.parentUnit.id : null;
  notAblated.sort((a, b) => a.start.line - b.start.line || a.start.col - b.start.col);
  return { units, notAblated, exports: [...exports].sort(), exportsComplete };
}

const PROBE = (id) => `(globalThis.__testAblationReach ??= new Set()).has(${JSON.stringify(id)}) || (globalThis.__testAblationReach.add(${JSON.stringify(id)}), globalThis.process?.getBuiltinModule?.("node:fs")?.appendFileSync(globalThis.process.env.${REACH_ENV}, ${JSON.stringify(id + "\n")}))`;

// The source with a probe before every unit. Insertions at one offset nest the
// way the units do: an outer unit's opening text lands left of an inner one's,
// an inner unit's closing text left of the outer's.
function probedSource(text, units) {
  const ins = [];
  units.forEach((u, idx) => {
    const p = PROBE(u.id);
    if (u.probe === "expr") ins.push({ pos: u.pos, start: true, idx, text: `(${p}, ` }, { pos: u.endPos, start: false, idx, text: ")" });
    else if (u.probe === "wrap") ins.push({ pos: u.pos, start: true, idx, text: `{ ${p}; ` }, { pos: u.endPos, start: false, idx, text: " }" });
    else ins.push({ pos: u.probePos, start: true, idx, text: `${p}; ` });
  });
  ins.sort((a, b) => b.pos - a.pos || (a.start !== b.start ? (a.start ? -1 : 1) : a.start ? b.idx - a.idx : a.idx - b.idx));
  let out = text;
  for (const i of ins) out = out.slice(0, i.pos) + i.text + out.slice(i.pos);
  return out;
}
const mutantSource = (text, u) => text.slice(0, u.pos) + u.replacement + text.slice(u.endPos);

// ---------------------------------------------------------------- test files
// Relative specifiers a test file imports, statically or through
// `await import("<literal>")`, with the names it binds from each.
function importsOf(ts, sf) {
  const out = []; // { spec, names: Set, all: boolean }
  const byAlias = new Map(); // identifier -> entry, for `const m = await import(...)` then m.x
  const add = (spec) => { const e = { spec, names: new Set(), all: false }; out.push(e); return e; };
  const bindingNames = (b, e) => { if (ts.isObjectBindingPattern(b)) for (const el of b.elements) e.names.add(el.propertyName ? el.propertyName.text : el.name.text); else e.all = true; };
  (function walk(n) {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const e = add(n.moduleSpecifier.text);
      const c = n.importClause;
      if (c) {
        if (c.name) e.names.add("default");
        if (c.namedBindings && ts.isNamedImports(c.namedBindings)) for (const el of c.namedBindings.elements) e.names.add(el.propertyName ? el.propertyName.text : el.name.text);
        if (c.namedBindings && ts.isNamespaceImport(c.namedBindings)) e.all = true;
      }
    } else if (ts.isExportDeclaration(n) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) {
      add(n.moduleSpecifier.text).all = true;
    } else if (ts.isCallExpression(n) && n.expression.kind === ts.SyntaxKind.ImportKeyword && n.arguments.length && ts.isStringLiteral(n.arguments[0])) {
      const e = add(n.arguments[0].text);
      let p = n.parent;
      if (p && ts.isAwaitExpression(p)) p = p.parent;
      while (p && ts.isParenthesizedExpression(p)) p = p.parent;
      if (p && ts.isVariableDeclaration(p)) { if (ts.isIdentifier(p.name)) byAlias.set(p.name.text, e); else bindingNames(p.name, e); }
      else if (p && ts.isPropertyAccessExpression(p)) e.names.add(p.name.text);
      else e.all = true;
    } else if (ts.isPropertyAccessExpression(n) && ts.isIdentifier(n.expression) && byAlias.has(n.expression.text)) {
      byAlias.get(n.expression.text).names.add(n.name.text);
    }
    ts.forEachChild(n, walk);
  })(sf);
  return out;
}
function resolvesTo(spec, fromDir, sourceAbs) {
  if (!spec.startsWith(".")) return false;
  const base = path.resolve(fromDir, spec);
  const c = [base, `${base}.ts`, `${base}.tsx`, `${base}.mts`, `${base}.cts`, path.join(base, "index.ts"), path.join(base, "index.tsx")];
  const m = /\.(js|jsx|mjs|cjs)$/.exec(base);
  if (m) c.push(base.slice(0, -m[0].length) + { js: ".ts", jsx: ".tsx", mjs: ".mts", cjs: ".cts" }[m[1]]);
  const want = norm(sourceAbs);
  return c.some((x) => norm(x) === want);
}
function walkFiles(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walkFiles(path.join(dir, e.name), out); }
    else if (e.isFile() && TEST_FILE.test(e.name)) out.push(path.join(dir, e.name));
  }
  return out;
}
function discoverTests(ts, project, sourceAbs) {
  const found = [];
  for (const abs of walkFiles(project, [])) {
    const { sf } = parseFile(ts, abs, fs.readFileSync(abs, "utf8"));
    const names = new Set();
    let all = false, imports = false;
    for (const e of importsOf(ts, sf)) {
      if (!resolvesTo(e.spec, path.dirname(abs), sourceAbs)) continue;
      imports = true; all = all || e.all; for (const n of e.names) names.add(n);
    }
    if (imports) found.push({ rel: posix(path.relative(project, abs)), names: [...names].sort(), all });
  }
  return found.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
}

// ---------------------------------------------------------------- the copy
function copyProject(project) {
  const copy = fs.mkdtempSync(path.join(os.tmpdir(), "test-ablation-"));
  fs.cpSync(project, copy, { recursive: true, filter: (src) => src === project || !SKIP_DIRS.has(path.basename(src)) });
  const nm = path.join(project, "node_modules");
  if (fs.existsSync(nm)) fs.symlinkSync(nm, path.join(copy, "node_modules"), "junction");
  return copy;
}
function removeCopy(copy) {
  const nm = path.join(copy, "node_modules");
  try { if (fs.lstatSync(nm).isSymbolicLink()) { try { fs.unlinkSync(nm); } catch { fs.rmdirSync(nm); } } } catch { /* no link */ }
  fs.rmSync(copy, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
function gitStatus(project) {
  if (!fs.existsSync(path.join(project, ".git"))) return null;
  try { return execFileSync("git", ["-C", project, "status", "--porcelain"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch { return null; }
}

// ---------------------------------------------------------------- vitest runs
function killTree(child) {
  if (WIN) spawnSync("taskkill", ["/T", "/F", "/PID", String(child.pid)], { stdio: "ignore", windowsHide: true });
  else { try { process.kill(-child.pid, "SIGKILL"); } catch { try { child.kill("SIGKILL"); } catch { /* gone */ } } }
}
function runEnv(extra) {
  const env = { ...process.env, TZ: "UTC", CI: "1", NO_COLOR: "1", FORCE_COLOR: "0", ...extra };
  delete env.NODE_OPTIONS; delete env.VSCODE_INSPECTOR_OPTIONS;
  if (!extra || !(REACH_ENV in extra)) delete env[REACH_ENV];
  return env;
}
function runVitest({ copy, bin, testFiles, env, timeoutMs, tag }) {
  const dir = path.join(copy, ".test-ablation");
  fs.mkdirSync(dir, { recursive: true });
  const outFile = path.join(dir, `${tag}.json`);
  fs.rmSync(outFile, { force: true });
  const args = [bin, "run", ...testFiles, "--reporter=json", `--outputFile=${outFile}`, "--coverage.enabled=false", "--sequence.shuffle=false", "--sequence.seed=1", "--no-cache", `--fsModuleCachePath=${path.join(dir, "vitest-cache")}`];
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(process.execPath, args, { cwd: copy, env, stdio: ["ignore", "pipe", "pipe"], windowsHide: true, detached: !WIN });
    let output = "";
    child.stdout.on("data", (d) => { output += d; });
    child.stderr.on("data", (d) => { output += d; });
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; killTree(child); }, timeoutMs);
    child.on("close", (code) => {
      clearTimeout(timer);
      let json = null;
      if (!timedOut && fs.existsSync(outFile)) { try { json = JSON.parse(fs.readFileSync(outFile, "utf8")); } catch { json = null; } }
      resolve({ timedOut, code, durationMs: Date.now() - t0, json, output: output.slice(-4000) });
    });
  });
}
// Per-test results of one run: id -> { status: passed|failed|skipped, message }.
// A test file that failed to load (no per-test entries) is the single id
// `<file>::*`; a file with no result at all counts the same.
function parseResults(json, copy, testFiles) {
  const res = new Map();
  const seen = new Set();
  const roots = [...new Set([copy, realpathOr(copy)])].map((r) => posix(r).replace(/\/+$/, "") + "/");
  const fold = (s) => (WIN ? s.toLowerCase() : s);
  const relOf = (name) => {
    const n = posix(name);
    for (const r of roots) if (fold(n).startsWith(fold(r))) { const rel = n.slice(r.length); if (testFiles.includes(rel)) return rel; }
    return testFiles.find((t) => fold(n).endsWith(fold("/" + t))) || null;
  };
  for (const f of json.testResults || []) {
    const rel = relOf(f.name);
    if (!rel) continue;
    seen.add(rel);
    const list = f.assertionResults || [];
    if (f.status === "failed" && !list.length) { res.set(`${rel}::*`, { status: "failed", message: String(f.message || "test file failed to load") }); continue; }
    const counts = new Map();
    for (const a of list) {
      const base = `${rel}::${a.fullName}`;
      const n = (counts.get(base) || 0) + 1;
      counts.set(base, n);
      res.set(n > 1 ? `${base} #${n}` : base, { status: a.status === "passed" ? "passed" : a.status === "failed" ? "failed" : "skipped", message: (a.failureMessages || [])[0] || "" });
    }
  }
  for (const t of testFiles) if (!seen.has(t)) res.set(`${t}::*`, { status: "failed", message: "no result from vitest" });
  return res;
}
const killKind = (message) => (/^\s*AssertionError\b/.test(firstLine(message)) ? "assertion" : "crash");
const failReason = (message) => (MISSING_SYMBOL.test(message) ? "missing_symbol" : killKind(message));

// ---------------------------------------------------------------- report
function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])]));
  return v;
}
const byId = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

async function main() {
  if (typeof process.getBuiltinModule !== "function") fail(`node ${process.versions.node}: process.getBuiltinModule missing, node 22.3 or later is needed for the reach probe`);
  const o = parseArgs(process.argv.slice(2));
  const sourceAbs = path.resolve(o.source);
  if (!fs.existsSync(sourceAbs)) fail(`source not found: ${sourceAbs}`);
  const project = o.project ? path.resolve(o.project) : findProject(path.dirname(sourceAbs));
  if (!project || !fs.existsSync(path.join(project, "package.json"))) fail(`no package.json above ${sourceAbs}: pass --project`);
  const sourceRel = relInside(project, sourceAbs, "source");
  const { ts, vitest } = resolveTools(project);

  const text = fs.readFileSync(sourceAbs, "utf8");
  const { sf, diags } = parseFile(ts, sourceRel, text);
  if (diags.length) fail(`syntax error in ${sourceRel}: ${diagLine(ts, sf, diags[0])}`);
  const { units, notAblated, exports, exportsComplete } = collectUnits(ts, sf, text);
  for (const u of units) u.invalid = parseFile(ts, sourceRel, mutantSource(text, u)).diags.length > 0;

  const importers = discoverTests(ts, project, sourceAbs);
  const testFiles = (o.tests.length ? o.tests.map((t) => relInside(project, path.resolve(t), "test file")) : importers.map((i) => i.rel)).sort(byId);
  if (!testFiles.length) fail(`no test file imports ${sourceRel}: pass --tests`);
  const missingExports = [];
  if (exportsComplete) for (const i of importers) for (const n of i.names) if (!exports.includes(n)) missingExports.push({ test_file: i.rel, name: n });

  const outPath = o.out ? path.resolve(o.out) : path.join(os.tmpdir(), "test-ablation", `${sha1(`${project}\n${sourceRel}`).slice(0, 12)}.json`);
  const gitBefore = gitStatus(project);
  const copy = copyProject(project);
  const copyRe = new RegExp([...new Set([copy, realpathOr(copy)])].flatMap((r) => [escapeRe(posix(r)) + "/?", escapeRe(r) + "\\\\?"]).join("|"), WIN ? "gi" : "g");
  const scrub = (s) => firstLine(s).replace(copyRe, "").slice(0, 200);
  const durations = { baseline: [], reach: null, ablation: null };
  const t0 = Date.now();
  const copySource = path.join(copy, sourceRel);
  let vitestRuns = 0;
  const run = (tag, extraEnv, timeoutMs) => { vitestRuns++; return runVitest({ copy, bin: vitest.bin, testFiles, env: runEnv(extraEnv), timeoutMs, tag }); };

  let report;
  try {
    // 1. baseline
    const runs = [];
    for (let k = 0; k < o.baselineRuns; k++) {
      const r = await run(`baseline-${k + 1}`, null, BASELINE_TIMEOUT_MS);
      if (r.timedOut) fail(`baseline run ${k + 1} timed out after ${BASELINE_TIMEOUT_MS / 1000} s`);
      if (!r.json) fail(`baseline run ${k + 1}: vitest wrote no report: ${scrub(r.output) || `exit ${r.code}`}`);
      durations.baseline.push(r.durationMs);
      runs.push(parseResults(r.json, copy, testFiles));
    }
    const ids = [...new Set(runs.flatMap((m) => [...m.keys()]))].sort(byId);
    const passing = [], failing = [], flaky = [];
    for (const id of ids) {
      const sts = runs.map((m) => (m.get(id) || { status: "absent" }).status);
      if (sts.every((s) => s === "passed")) passing.push(id);
      else if (sts.every((s) => s === "failed")) { const msg = runs[0].get(id).message; failing.push({ test: id, reason: failReason(msg), message_head: scrub(msg) }); }
      else if (!sts.every((s) => s === "skipped")) flaky.push(id);
    }
    if (!passing.length) fail(`no stable passing test in the baseline (${o.baselineRuns} runs of ${testFiles.join(", ")}): nothing to measure`);
    const stable = new Map(passing.map((id) => [id, "passed"]).concat(failing.map((f) => [f.test, "failed"])));
    const timeoutMs = Math.max(10000, 5 * Math.max(...durations.baseline));

    const reached = new Set();
    const kills = new Map(); // unit id -> kills
    if (!o.dryRun) {
      // 2. reach
      const reachFile = path.join(copy, ".test-ablation", "reach.txt");
      fs.mkdirSync(path.dirname(reachFile), { recursive: true });
      fs.writeFileSync(reachFile, "");
      fs.writeFileSync(copySource, probedSource(text, units));
      let r;
      try { r = await run("reach", { [REACH_ENV]: reachFile }, timeoutMs); } finally { fs.writeFileSync(copySource, text); }
      if (r.timedOut) fail(`reach run timed out after ${timeoutMs / 1000} s`);
      if (!r.json) fail(`reach run: vitest wrote no report: ${scrub(r.output) || `exit ${r.code}`}`);
      durations.reach = r.durationMs;
      const res = parseResults(r.json, copy, testFiles);
      for (const [id, st] of stable) { const got = (res.get(id) || { status: "absent" }).status; if (got !== st) fail(`reach run differs from the baseline: ${id} ${st} -> ${got}`); }
      for (const line of fs.readFileSync(reachFile, "utf8").split(/\r?\n/)) if (line) reached.add(line);

      // 3. ablation, one run per valid unit
      const ta = Date.now();
      for (const u of units) {
        if (u.invalid) continue;
        fs.writeFileSync(copySource, mutantSource(text, u));
        let m;
        try { m = await run(`mutant-${units.indexOf(u)}`, null, timeoutMs); } finally { fs.writeFileSync(copySource, text); }
        const ks = [];
        if (m.timedOut) ks.push({ test: "*", kind: "timeout" });
        else {
          const res = m.json ? parseResults(m.json, copy, testFiles) : null;
          for (const id of passing) {
            const got = res && res.get(id);
            if (!res || !got) ks.push({ test: id, kind: "crash" });
            else if (got.status === "failed") ks.push({ test: id, kind: killKind(got.message) });
          }
        }
        kills.set(u.id, ks.sort((a, b) => byId(a.test, b.test) || byId(a.kind, b.kind)));
      }
      durations.ablation = Date.now() - ta;
    }

    const gitAfter = gitStatus(project);
    if (gitBefore !== gitAfter) fail(`the project changed during the run (git status --porcelain differs): ${firstLine((gitAfter || "").split("\n").filter((l) => !(gitBefore || "").includes(l)).join(" | ")) || "see git status"}`);

    const unitRows = units.map((u) => {
      const ks = kills.get(u.id) || [];
      const status = o.dryRun ? (u.invalid ? "invalid" : "not_run") : u.invalid ? "invalid" : ks.length ? "killed" : "survived";
      return { id: u.id, parent: u.parent, kind: u.kind, start: u.start, end: u.end, text_head: u.text_head, text_sha1: u.text_sha1, flags: u.flags, reached: o.dryRun ? null : reached.has(u.id), status, kills: ks };
    });
    const killedTests = new Set(unitRows.flatMap((u) => u.kills.map((k) => k.test)));
    const facts = o.dryRun
      ? { survived_reached: [], unreached: [], crash_only: [], never_failing_tests: [], orphan_tests: [] }
      : {
          survived_reached: unitRows.filter((u) => u.status === "survived" && u.reached).map((u) => u.id),
          unreached: unitRows.filter((u) => u.status !== "invalid" && !u.reached).map((u) => u.id),
          crash_only: unitRows.filter((u) => u.status === "killed" && u.kills.every((k) => k.kind === "crash")).map((u) => u.id),
          never_failing_tests: passing.filter((id) => !killedTests.has(id)),
          orphan_tests: failing.map((f) => f.test),
        };
    for (const k of Object.keys(facts)) facts[k].sort(byId);
    report = {
      schema: 1, language: "typescript", dry_run: o.dryRun, source: sourceRel, tests: testFiles,
      tool_versions: { node: process.versions.node, typescript: ts.version, vitest: vitest.version },
      baseline: { passing, failing: failing.sort((a, b) => byId(a.test, b.test)), flaky: flaky.sort(byId) },
      units: unitRows, not_ablated: notAblated,
      static: { exports, exports_complete: exportsComplete, missing_exports: missingExports.sort((a, b) => byId(a.test_file, b.test_file) || byId(a.name, b.name)), test_files_importing_source: importers.map((i) => i.rel) },
      facts,
      meta: { durations_ms: { ...durations, total: Date.now() - t0 }, units_total: units.length, vitest_runs: vitestRuns, run_timeout_ms: timeoutMs },
    };
  } finally {
    removeCopy(copy);
  }

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(sortKeys(report), null, 2) + "\n");
  if (o.dryRun) {
    for (const u of report.units) console.log(`${u.id}  ${u.text_head}`);
    const mean = durations.baseline.reduce((a, b) => a + b, 0) / durations.baseline.length;
    console.log(`estimate: ${units.length} units x ${Math.round(mean)} ms = ${Math.round((units.length * mean) / 1000)} s`);
  } else {
    for (const k of Object.keys(report.facts)) console.log(`${k}: ${report.facts[k].length}`);
  }
  console.log(outPath);
}

main().catch((e) => {
  console.error(`test-ablation: ${String(e instanceof Fail ? e.message : (e && e.stack) || e).replace(/\s*\n\s*/g, " ")}`);
  process.exit(2);
});
