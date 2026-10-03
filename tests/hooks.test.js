// Self-check for the PreToolUse guards in hooks/: protect-gates.js and the three
// vendored cc-safe-setup shell guards. Every case is a hook payload exactly as
// Claude Code sends it (tool_name + tool_input), for the Bash tool and for the
// PowerShell tool alike. Run after touching anything in hooks/:
//
//   node --test tests/
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const HOOKS = path.join(__dirname, "..", "hooks");
const hasBashAndJq = spawnSync("bash", ["-c", "command -v jq"], { encoding: "utf8" }).status === 0;

function run(hook, payload, env = {}) {
  const js = hook.endsWith(".js");
  const r = spawnSync(js ? process.execPath : "bash", [path.join(HOOKS, hook)], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: { ...process.env, PROTECT_GATES: "", ...env }, // the machine's own PROTECT_GATES must not leak in
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const shell = (tool, command) => ({ hook_event_name: "PreToolUse", tool_name: tool, tool_input: { command } });
const file = (tool, tool_input) => ({ hook_event_name: "PreToolUse", tool_name: tool, tool_input });

// ---------------------------------------------------------------- protect-gates
const BLOCKED_SHELL = [
  "git commit --no-verify -m x",
  "git commit -n -m x",
  "rtk git commit -am x --no-verify",
  "cd backend && git -C . commit --no-verify",
  "uv run python scripts/check_import_cycles.py --update-baseline",
  "pnpm lint:arch:baseline",
  "gh pr merge 12 --squash",
  "gh pr edit 12 --add-label baseline-update",
  "gh api -X PUT repos/o/r/pulls/12/merge",
  "curl -X POST https://api.github.com/repos/o/r/issues/12/labels -d '[\"baseline-update\"]'",
  "Invoke-RestMethod -Method Put -Uri https://api.github.com/repos/o/r/pulls/12/merge",
  "Invoke-WebRequest -Method Post -Uri https://api.github.com/repos/o/r/issues/12/labels",
  "echo '[]' > backend/import-cycles-baseline.json",
  "sed -i 's/error/warn/' frontend/.dependency-cruiser.cjs",
  "sed -E -i.bak 's/x/y/' ruff.toml",
  "cp /tmp/x .github/workflows/backend.yml",
  "rm frontend/.dependency-cruiser-known-violations.json",
  "Set-Content -Path backend/import-layers-baseline.json -Value '[]'",
  "'[]' | Out-File frontend/.dependency-cruiser-known-violations.json",
  "Add-Content eslint.config.js 'x'",
  "Copy-Item C:\\tmp\\x .github\\workflows\\frontend.yml",
  "Move-Item ruff.toml ruff.bak",
  "Remove-Item backend\\import-cycles-baseline.json",
  "echo x >> pyproject.toml",
];
const ALLOWED_SHELL = [
  "git commit -m 'fix: nothing to verify here'",
  "git commit -m x && git push origin feat",
  "cat backend/import-cycles-baseline.json",
  "uv run python scripts/check_import_cycles.py",
  "pnpm lint:arch",
  "gh pr view 12",
  "gh pr create --title x --body y",
  "curl https://api.github.com/repos/o/r/pulls/12",
  "Get-Content backend/import-layers-baseline.json",
  "grep -n baseline .github/workflows/backend.yml 2>/dev/null",
  "uv add httpx",
  "node --test tests/",
];

for (const tool of ["Bash", "PowerShell"]) {
  test(`protect-gates blocks gate tampering from the ${tool} tool`, () => {
    for (const command of BLOCKED_SHELL) {
      const r = run("protect-gates.js", shell(tool, command));
      assert.equal(r.code, 2, `${command}\n${r.err}`);
      assert.match(r.err, /protect-gates: BLOCKED/);
    }
  });
  test(`protect-gates lets ordinary ${tool} commands through`, () => {
    for (const command of ALLOWED_SHELL) {
      const r = run("protect-gates.js", shell(tool, command));
      assert.equal(r.code, 0, `${command}\n${r.err}`);
      assert.equal(r.out, "");
    }
  });
}

test("protect-gates blocks edits to gate configs, baselines and workflows (both path spellings)", () => {
  const cases = [
    file("Edit", { file_path: "/repo/backend/import-cycles-baseline.json", old_string: "[", new_string: "[[\"a\",\"b\"]," }),
    file("Edit", { file_path: "C:\\repo\\frontend\\.dependency-cruiser-known-violations.json", old_string: "x", new_string: "y" }),
    file("Write", { file_path: "/repo/.github/workflows/backend.yml", content: "" }),
    file("Write", { file_path: "C:\\repo\\.github\\workflows\\frontend.yml", content: "" }),
    file("Edit", { file_path: "/repo/frontend/eslint.config.js", old_string: "error", new_string: "warn" }),
    file("Edit", { file_path: "/repo/frontend/.dependency-cruiser.cjs", old_string: "error", new_string: "warn" }),
    file("Write", { file_path: "/repo/ruff.toml", content: "" }),
    file("Write", { file_path: "/repo/.ruff.toml", content: "" }),
    file("MultiEdit", { file_path: "/repo/mypy.ini", edits: [] }),
    file("NotebookEdit", { notebook_path: "/repo/x-baseline.json", new_source: "" }),
  ];
  for (const c of cases) {
    const r = run("protect-gates.js", c);
    assert.equal(r.code, 2, `${JSON.stringify(c.tool_input)}\n${r.err}`);
    assert.match(r.err, /gate config or baseline/);
  }
});

test("protect-gates lets ordinary files through", () => {
  const cases = [
    file("Edit", { file_path: "/repo/src/app.ts", old_string: "a", new_string: "b" }),
    file("Write", { file_path: "C:\\repo\\README.md", content: "" }),
    file("Edit", { file_path: "/repo/.github/CODEOWNERS", old_string: "a", new_string: "b" }),
    file("Write", { file_path: "/repo/backend/tests/test_check_layers.py", content: "" }),
    file("NotebookEdit", { notebook_path: "/repo/nb.ipynb", new_source: "" }),
  ];
  for (const c of cases) {
    const r = run("protect-gates.js", c);
    assert.equal(r.code, 0, `${JSON.stringify(c.tool_input)}\n${r.err}`);
  }
});

test("pyproject.toml: dependencies stay editable, the gates' [tool.*] sections are frozen", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "protect-gates-"));
  const p = path.join(dir, "pyproject.toml");
  fs.copyFileSync(path.join(__dirname, "fixtures", "pyproject.toml"), p); // a real project's file, anonymized
  const edit = (old_string, new_string) => run("protect-gates.js", file("Edit", { file_path: p, old_string, new_string })).code;

  // red: every gate section
  assert.equal(edit("line-length = 100", "line-length = 120"), 2);
  assert.equal(edit("strict = true", "strict = false"), 2);
  assert.equal(edit('select = ["E", "F", "I", "UP"]', 'select = ["E"]'), 2);
  assert.equal(edit("[tool.mypy]\n", "[tool.mypy]\nignore_errors = true\n"), 2);
  assert.equal(edit('asyncio_mode = "auto"', 'asyncio_mode = "strict"'), 2);
  assert.equal(edit('version = "0.1.0"', 'version = "0.1.0"\n[tool.ruff]\nline-length = 999'), 2); // sneaking a section in elsewhere
  // green: dependencies and metadata
  assert.equal(edit('"httpx>=0.28.0",', '"httpx>=0.28.0",\n    "tenacity>=9.0",'), 0);
  assert.equal(edit('"grimp>=3.14",', '"grimp>=3.14",\n    "mutmut>=3.3",'), 0);
  assert.equal(edit('version = "0.1.0"', 'version = "0.2.0"'), 0);
  assert.equal(edit("not in the file", "x"), 0); // the Edit tool fails on its own

  const before = fs.readFileSync(p, "utf8");
  const write = (content) => run("protect-gates.js", file("Write", { file_path: p, content })).code;
  assert.equal(write(before.replace('"networkx>=3.2",', '"networkx>=3.2",\n    "tenacity>=9.0",')), 0);
  assert.equal(write(before.replace("line-length = 100", "line-length = 200")), 2);
  assert.equal(write(before.replace("[tool.ruff.lint]\nselect", "[tool.ruff.lint]\nignore = [\"E501\"]\nselect")), 2);

  const multi = (edits) => run("protect-gates.js", file("MultiEdit", { file_path: p, edits })).code;
  assert.equal(multi([{ old_string: 'version = "0.1.0"', new_string: 'version = "0.3.0"' }]), 0);
  assert.equal(multi([{ old_string: 'version = "0.1.0"', new_string: 'version = "0.3.0"' }, { old_string: "line-length = 100", new_string: "line-length = 80" }]), 2);

  // a pyproject.toml without any gate section is free; adding one from scratch is a gate change
  const q = path.join(dir, "other", "pyproject.toml");
  fs.mkdirSync(path.dirname(q));
  fs.writeFileSync(q, '[project]\nname = "x"\n');
  assert.equal(run("protect-gates.js", file("Write", { file_path: q, content: '[project]\nname = "y"\n' })).code, 0);
  assert.equal(run("protect-gates.js", file("Write", { file_path: q, content: '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 999\n' })).code, 2);
});

test("PROTECT_GATES=off: a visible warning instead of a block; the harness itself stays protected", () => {
  const r = run("protect-gates.js", shell("Bash", "git commit --no-verify -m x"), { PROTECT_GATES: "off" });
  assert.equal(r.code, 0, r.err);
  assert.match(JSON.parse(r.out).systemMessage, /OFF.*would have blocked Bash/);
  const r2 = run("protect-gates.js", file("Edit", { file_path: "/repo/import-layers-baseline.json", old_string: "[]", new_string: "[1]" }), { PROTECT_GATES: "off" });
  assert.equal(r2.code, 0);
  assert.match(JSON.parse(r2.out).systemMessage, /would have blocked Edit/);

  const self = [
    file("Edit", { file_path: "C:\\Users\\u\\.claude\\settings.json", old_string: "a", new_string: "b" }),
    file("Write", { file_path: "/home/u/.claude/hooks/protect-gates.js", content: "" }),
    file("Write", { file_path: "/repo/.claude/settings.local.json", content: "{}" }),
    shell("Bash", "echo '{}' > /home/u/.claude/settings.json"),
    shell("Bash", "sed -i 's/protect-gates//' /home/u/.claude/settings.json"),
    shell("PowerShell", "Set-Content C:\\Users\\u\\.claude\\settings.json '{}'"),
    shell("PowerShell", "Remove-Item C:\\Users\\u\\.claude\\hooks\\protect-gates.js"),
  ];
  for (const c of self) {
    for (const env of [{}, { PROTECT_GATES: "off" }]) {
      const r3 = run("protect-gates.js", c, env);
      assert.equal(r3.code, 2, `${JSON.stringify(c.tool_input)} env=${JSON.stringify(env)}\n${r3.err}`);
      assert.match(r3.err, /harness itself/);
    }
  }
  // reading the harness is fine
  assert.equal(run("protect-gates.js", shell("Bash", "cat ~/.claude/settings.json"), { PROTECT_GATES: "off" }).code, 0);
  assert.equal(run("protect-gates.js", shell("Bash", "cat /home/u/.claude/settings.json")).code, 0);
});

// ------------------------------------------------- vendored cc-safe-setup guards
const skip = hasBashAndJq ? false : "bash + jq not available";
const guard = (hook, tool, command) => run(hook, shell(tool, command)).code;

test("branch-guard: push to main or force push blocked, also behind rtk or a cd; feature pushes pass", { skip }, () => {
  for (const tool of ["Bash", "PowerShell"]) {
    assert.equal(guard("branch-guard.sh", tool, "git push origin main"), 2, tool);
    assert.equal(guard("branch-guard.sh", tool, "rtk git push origin main"), 2, tool);
    assert.equal(guard("branch-guard.sh", tool, "cd repo && git push origin master"), 2, tool);
    assert.equal(guard("branch-guard.sh", tool, "git push --force origin feat"), 2, tool);
    assert.equal(guard("branch-guard.sh", tool, "git push -u origin feature-branch"), 0, tool);
    assert.equal(guard("branch-guard.sh", tool, "rtk git push origin feat"), 0, tool);
  }
});

test("secret-guard: staging .env or key files blocked, also behind rtk or a cd; ordinary adds pass", { skip }, () => {
  for (const tool of ["Bash", "PowerShell"]) {
    assert.equal(guard("secret-guard.sh", tool, "git add .env"), 2, tool);
    assert.equal(guard("secret-guard.sh", tool, "rtk git add backend/.env.local"), 2, tool);
    assert.equal(guard("secret-guard.sh", tool, "cd repo && git add id_rsa"), 2, tool);
    assert.equal(guard("secret-guard.sh", tool, "git add src/ README.md"), 0, tool);
    assert.equal(guard("secret-guard.sh", tool, "rtk git add hooks/"), 0, tool);
  }
});

test("destructive-guard: hard resets, clean, forced checkout, recursive deletes blocked, also behind rtk; safe commands pass", { skip }, () => {
  for (const tool of ["Bash", "PowerShell"]) {
    assert.equal(guard("destructive-guard.sh", tool, "git reset --hard HEAD~1"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "rtk git reset --hard"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "cd repo && git clean -fdx"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "rtk git checkout -f main"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "Remove-Item -Recurse -Force C:\\Users\\User\\Documents"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "rm -rf ~/"), 2, tool);
    assert.equal(guard("destructive-guard.sh", tool, "rm -rf node_modules"), 0, tool);
    assert.equal(guard("destructive-guard.sh", tool, "git reset --soft HEAD~1"), 0, tool);
    assert.equal(guard("destructive-guard.sh", tool, "rtk git status"), 0, tool);
  }
});
