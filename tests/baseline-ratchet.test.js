// Self-check for scripts/baseline-ratchet.js on the real papers-helper baselines
// (tests/fixtures/baselines): unchanged and shrinking baselines pass; a growing,
// new or deleted one fails unless --override (the PR label) is given, and even
// then the growth is reported. Run after touching the script or the workflow:
//
//   node --test tests/
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const SCRIPT = path.join(__dirname, "..", "scripts", "baseline-ratchet.js");
const FIXTURES = path.join(__dirname, "fixtures", "baselines");
const T = fs.mkdtempSync(path.join(os.tmpdir(), "ratchet-repo-"));
const OUT = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "ratchet-out-")), "github-output.txt");

const git = (...args) => execFileSync("git", ["-C", T, ...args], { encoding: "utf8" }).trim();
const write = (rel, content) => {
  const p = path.join(T, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
};
const read = (rel) => JSON.parse(fs.readFileSync(path.join(T, rel), "utf8"));
const DC = "frontend/.dependency-cruiser-known-violations.json";

git("init", "-q", "-b", "main");
git("config", "user.email", "t@t");
git("config", "user.name", "t");
write("backend/import-cycles-baseline.json", fs.readFileSync(path.join(FIXTURES, "import-cycles-baseline.json"), "utf8"));
write("backend/import-layers-baseline.json", fs.readFileSync(path.join(FIXTURES, "import-layers-baseline.json"), "utf8"));
write(DC, fs.readFileSync(path.join(FIXTURES, ".dependency-cruiser-known-violations.json"), "utf8"));
git("add", "-A");
git("commit", "-q", "-m", "base");
const BASE = git("rev-parse", "HEAD");

// One branch per case, off a given commit; returns the new head sha.
function commitOn(start, name, mutate) {
  git("checkout", "-q", "-b", name, start);
  mutate();
  git("add", "-A");
  git("commit", "-q", "--allow-empty", "-m", name);
  return git("rev-parse", "HEAD");
}
function ratchet(base, head, ...flags) {
  fs.writeFileSync(OUT, "");
  const r = spawnSync(process.execPath, [SCRIPT, "--base", base, "--head", head, "--repo", T, ...flags], {
    encoding: "utf8",
    env: { ...process.env, GITHUB_OUTPUT: OUT },
  });
  return { code: r.status, out: r.stdout, err: r.stderr, grew: fs.readFileSync(OUT, "utf8").trim() };
}

test("unchanged baselines pass", () => {
  const r = ratchet(BASE, BASE);
  assert.equal(r.code, 0, r.err);
  assert.equal(r.grew, "grew=false");
  assert.match(r.out, /No baseline grew/);
  assert.match(r.out, /ok `backend\/import-cycles-baseline.json`: \+0 \/ -0 \(1 -> 1\)/);
});

test("a shrinking baseline passes and reports the removal", () => {
  const head = commitOn(BASE, "shrink", () => {
    const v = read(DC);
    v.pop();
    write(DC, JSON.stringify(v, null, 2));
  });
  const r = ratchet(BASE, head);
  assert.equal(r.code, 0, r.err);
  assert.equal(r.grew, "grew=false");
  assert.match(r.out, /ok `frontend\/\.dependency-cruiser-known-violations.json`: \+0 \/ -1 \(3 -> 2\)/);
});

test("reordered entries are not a change", () => {
  const head = commitOn(BASE, "reorder", () => write(DC, JSON.stringify(read(DC).reverse(), null, 2)));
  const r = ratchet(BASE, head);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /known-violations.json`: \+0 \/ -0/);
});

test("a growing baseline fails and names the new entry", () => {
  const head = commitOn(BASE, "grow", () => write("backend/import-layers-baseline.json", JSON.stringify([["app.config", "app.main"]])));
  const r = ratchet(BASE, head);
  assert.equal(r.code, 1, r.err);
  assert.equal(r.grew, "grew=true");
  assert.match(r.out, /GROWTH `backend\/import-layers-baseline.json`: \+1 \/ -0 \(0 -> 1\)/);
  assert.match(r.out, /added: `\["app\.config","app\.main"\]`/);
  assert.match(r.out, /A baseline grew/);
});

test("--override (the PR label) turns the same growth into a pass that is still reported", () => {
  const r = ratchet(BASE, git("rev-parse", "grow"), "--override");
  assert.equal(r.code, 0, r.err);
  assert.equal(r.grew, "grew=true"); // the workflow posts the PR comment on this
  assert.match(r.out, /Growth accepted because the PR carries the override label/);
  assert.match(r.out, /\+1 \/ -0 \(0 -> 1\)/);
});

test("a new baseline file is growth", () => {
  const head = commitOn(BASE, "new-file", () => write("backend/mutation-baseline.json", JSON.stringify({ min_score: 80 })));
  const r = ratchet(BASE, head);
  assert.equal(r.code, 1, r.err);
  assert.match(r.out, /GROWTH `backend\/mutation-baseline.json`: new baseline \(1 entries\)/);
});

test("a deleted baseline file is growth", () => {
  const head = commitOn(BASE, "deleted", () => fs.rmSync(path.join(T, "backend/import-cycles-baseline.json")));
  const r = ratchet(BASE, head);
  assert.equal(r.code, 1, r.err);
  assert.match(r.out, /GROWTH `backend\/import-cycles-baseline.json`: baseline deleted/);
});

test("a non-array baseline (a score floor) is one opaque entry: any value change is growth, key order is not", () => {
  const floor = commitOn(BASE, "floor", () => write("backend/mutation-baseline.json", JSON.stringify({ min_score: 80, max_survivors: 12 })));
  const lowered = commitOn(floor, "floor-lowered", () => write("backend/mutation-baseline.json", JSON.stringify({ max_survivors: 13, min_score: 80 })));
  const reordered = commitOn(floor, "floor-reordered", () => write("backend/mutation-baseline.json", JSON.stringify({ max_survivors: 12, min_score: 80 })));
  const r1 = ratchet(floor, lowered);
  assert.equal(r1.code, 1, r1.err);
  assert.match(r1.out, /mutation-baseline.json`: \+1 \/ -1/);
  const r2 = ratchet(floor, reordered);
  assert.equal(r2.code, 0, r2.err);
  assert.match(r2.out, /mutation-baseline.json`: \+0 \/ -0/);
});

test("an unknown ref is a usage error, never a pass", () => {
  const r = ratchet("no-such-ref", BASE);
  assert.equal(r.code, 2);
  assert.match(r.err, /unknown ref no-such-ref/);
});
