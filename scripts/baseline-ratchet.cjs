#!/usr/bin/env node
// baseline-ratchet.cjs — a gate baseline may only shrink.
//
// Compares every baseline file between two git refs and fails when the head
// side holds entries the base side does not (or when a baseline appeared or
// disappeared). Entries are the elements of the JSON array, compared as
// canonical strings (object keys sorted), so reordering is not a change. A
// baseline that is not an array counts as one opaque entry: any change to it
// is growth, and so is a change of shape (array <-> object).
//
//   node baseline-ratchet.cjs --base <ref> --head <ref> [--repo <dir>] [--override]
//
// Exit 0: no growth, or growth with --override (reported loudly).
// Exit 1: growth without --override.
// Exit 2: usage or git error.
// With GITHUB_OUTPUT set, appends grew=true|false for the workflow steps.
//
// Run by .github/workflows/baseline-ratchet.yml. hooks/protect-gates.js is the
// local speed bump; this script is what actually holds.
"use strict";
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");

const BASELINE = /(^|\/)([^/]*-baseline\.json|\.dependency-cruiser-known-violations\.json)$/;

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i === -1 ? dflt : process.argv[i + 1];
}
const base = arg("--base");
const head = arg("--head");
const repo = arg("--repo", process.cwd());
const override = process.argv.includes("--override");
if (!base || !head) {
  console.error("usage: baseline-ratchet.cjs --base <ref> --head <ref> [--repo <dir>] [--override]");
  process.exit(2);
}

function git(...args) {
  return execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}
for (const ref of [base, head]) {
  try { git("rev-parse", "--verify", "--quiet", `${ref}^{commit}`); } catch {
    console.error(`baseline-ratchet: unknown ref ${ref}`);
    process.exit(2);
  }
}

function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])]));
  return v;
}
const canon = (v) => JSON.stringify(sortKeys(v));
const baselinesIn = (ref) => git("ls-tree", "-r", "--name-only", ref).split("\n").filter((p) => BASELINE.test(p));
function entries(ref, p) {
  let text;
  try { text = git("show", `${ref}:${p}`); } catch { return null; } // absent on this side
  const json = JSON.parse(text);
  const isArray = Array.isArray(json);
  const items = isArray ? json : [json];
  return { isArray, set: new Set(items.map(canon)), items };
}
const shape = (e) => (e.isArray ? "array" : "object");
// An entry whose last field is a number is a measure under a key ([file, function, complexity]):
// the same key with a lower number is a shrink, a higher one is growth. Other entries are opaque.
const measured = (item) => (Array.isArray(item) && item.length > 1 && typeof item[item.length - 1] === "number" ? { key: canon(item.slice(0, -1)), value: item[item.length - 1] } : null);
const measures = (items) => new Map(items.map(measured).filter(Boolean).map((m) => [m.key, m.value]));

const paths = [...new Set([...baselinesIn(base), ...baselinesIn(head)])].sort();
const lines = ["## baseline-ratchet", ""];
let grew = false;
for (const p of paths) {
  const a = entries(base, p);
  const b = entries(head, p);
  if (!a) { grew = true; lines.push(`- GROWTH \`${p}\`: new baseline (${b.set.size} entries)`); continue; }
  if (!b) { grew = true; lines.push(`- GROWTH \`${p}\`: baseline deleted`); continue; }
  if (a.isArray !== b.isArray) { grew = true; lines.push(`- GROWTH \`${p}\`: format changed (${shape(a)} -> ${shape(b)})`); continue; }
  const ma = measures(a.items);
  const mb = measures(b.items);
  const added = [];
  const raised = [];
  let lowered = 0;
  for (const item of b.items) {
    const e = canon(item);
    if (a.set.has(e)) continue;
    const m = measured(item);
    if (m && ma.has(m.key)) { if (m.value > ma.get(m.key)) raised.push(`${e} (was ${ma.get(m.key)})`); else lowered++; }
    else added.push(e);
  }
  const removed = a.items.filter((item) => !b.set.has(canon(item)) && !(measured(item) && mb.has(measured(item).key))).length;
  if (added.length || raised.length) grew = true;
  const moved = raised.length || lowered ? `, raised ${raised.length} / lowered ${lowered}` : "";
  lines.push(`- ${grew && (added.length || raised.length) ? "GROWTH" : "ok"} \`${p}\`: +${added.length} / -${removed}${moved} (${a.set.size} -> ${b.set.size})`);
  for (const e of added) lines.push(`  - added: \`${e}\``);
  for (const e of raised) lines.push(`  - raised: \`${e}\``);
}
if (!paths.length) lines.push("- no baseline file on either side");
lines.push("");
if (grew && override) {
  lines.push(
    "**Growth accepted because the PR carries the override label.** A baseline is debt that is",
    "being frozen: review the added entries above. GitHub only sees the token, so a label set",
    "by Claude with the owner's token is indistinguishable from one the owner set; the hook",
    "protect-gates blocks the known ways to do it and this comment makes every use visible.",
  );
} else if (grew) {
  lines.push("**A baseline grew.** Fix the new violations, or have a human set the override label on the PR.");
} else {
  lines.push("No baseline grew.");
}
console.log(lines.join("\n"));
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `grew=${grew}\n`);
process.exit(grew && !override ? 1 : 0);
