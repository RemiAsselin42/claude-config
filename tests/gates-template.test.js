// Self-check for templates/gates/dependency-cruiser.cjs: a toy project, the template
// with its LAYERS filled the way /init-gates fills them, and the dependency-cruiser
// version the arch-gates workflow pins. Needs npx (and its cache, or the network).
//
//   node --test "tests/*.test.js"
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const TEMPLATE = path.join(__dirname, "..", "templates", "gates", "dependency-cruiser.cjs");
const NPX = ["--yes", "-p", "dependency-cruiser@17.4.3", "-p", "typescript@5.9.3", "depcruise", "src", "--config", ".dependency-cruiser.cjs"];

function project(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gates-template-"));
  const layers = "['types/'],\n  ['utils/'],\n  ['components/'],\n  ['main\\\\.ts$'],";
  const config = fs.readFileSync(TEMPLATE, "utf8").replace(/const LAYERS = \[[\s\S]*?\n\];/, () => `const LAYERS = [\n  ${layers}\n];`); // a function: "$'" in the layers is not a replacement pattern
  fs.writeFileSync(path.join(dir, ".dependency-cruiser.cjs"), config);
  fs.writeFileSync(path.join(dir, "tsconfig.json"), JSON.stringify({ compilerOptions: { moduleResolution: "bundler", module: "ESNext", paths: { "@/*": ["./src/*"] } }, include: ["src"] }));
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), body);
  }
  return dir;
}
function cruise(dir) {
  const r = spawnSync("npx", NPX, { cwd: dir, encoding: "utf8", shell: process.platform === "win32" });
  return { code: r.status, out: r.stdout + r.stderr };
}
const npxWorks = spawnSync("npx", ["--version"], { encoding: "utf8", shell: process.platform === "win32" }).status === 0;
const skip = npxWorks ? false : "npx not available";

const CLEAN = {
  "src/types/paper.ts": "export type Paper = { id: string };\nexport const KIND = 'paper';\n",
  "src/utils/format.ts": "import { KIND } from '@/types/paper';\nexport const label = (s: string): string => KIND + s;\n",
  "src/components/card.ts": "import { label } from '../utils/format';\nexport const card = (): string => label('x');\n",
  "src/main.ts": "import { card } from './components/card';\ncard();\n",
};

test("template: no JSDoc import of dependency-cruiser", () => {
  // Fallow on the Cleant pilot read `@type {import('dependency-cruiser')...}` as an import of a
  // package the repo does not list (unlisted-dependency); the type hint is not worth that.
  assert.doesNotMatch(fs.readFileSync(TEMPLATE, "utf8"), /import\(['"]dependency-cruiser['"]\)/);
});

test("template: a layered project is green, each kind of violation is red", { skip }, () => {
  assert.equal(cruise(project(CLEAN)).code, 0, "clean project");

  // an upward import, reached through the @/ alias: only seen if the tsconfig is honoured
  const up = cruise(project({ ...CLEAN, "src/utils/format.ts": "import { card } from '@/components/card';\nexport const label = (s: string): string => card() + s;\n" }));
  assert.notEqual(up.code, 0);
  assert.match(up.out, /layer-1/);

  const cycle = cruise(project({ ...CLEAN, "src/types/paper.ts": "import { label } from '../utils/format';\nexport type Paper = { id: string };\nexport const KIND = label('');\n" }));
  assert.notEqual(cycle.code, 0);
  assert.match(cycle.out, /no-circular/);

  // a module in no layer, as importer and as imported
  const stray = cruise(project({ ...CLEAN, "src/stray/thing.ts": "import { KIND } from '../types/paper';\nexport const thing = KIND;\n", "src/components/card.ts": "import { thing } from '../stray/thing';\nexport const card = (): string => thing;\n" }));
  assert.notEqual(stray.code, 0);
  assert.match(stray.out, /not-in-a-layer/);
  assert.match(stray.out, /imports-a-module-in-no-layer/);

  // review of PR #10: a module in no layer that imports nothing and nobody imports;
  // a declaration file (vite-env.d.ts) carries no runtime code and stays out of it
  const orphan = cruise(project({ ...CLEAN, "src/lonely/alone.ts": "export const alone = 1;\n" }));
  assert.notEqual(orphan.code, 0);
  assert.match(orphan.out, /not-in-a-layer-orphan/);
  assert.equal(cruise(project({ ...CLEAN, "src/vite-env.d.ts": "/// <reference types=\"vite/client\" />\n" })).code, 0);

  // `import type` is erased at compile time: no runtime edge, no violation
  const typeOnly = cruise(project({ ...CLEAN, "src/types/paper.ts": "import type { card } from '../components/card';\nexport type Paper = { id: string; c?: typeof card };\nexport const KIND = 'paper';\n" }));
  assert.equal(typeOnly.code, 0, typeOnly.out);
});
