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
const hasBash = spawnSync("bash", ["-c", "true"]).status === 0;
// bash by absolute path (native spelling on Windows), so a test may empty PATH and still start a guard
const BASH = (() => {
  const r = spawnSync("bash", ["-c", process.platform === "win32" ? 'cygpath -w "$(command -v bash)"' : "command -v bash"], { encoding: "utf8" });
  return r.status === 0 && r.stdout.trim() ? r.stdout.trim() : "bash";
})();

function run(hook, payload, env = {}) {
  const js = hook.endsWith(".js");
  const e = { ...process.env, PROTECT_GATES: "", ...env }; // the machine's own PROTECT_GATES must not leak in
  if ("PATH" in env) for (const k of Object.keys(e)) if (k !== "PATH" && /^path$/i.test(k)) delete e[k]; // Windows spells it Path
  const r = spawnSync(js ? process.execPath : BASH, [path.join(HOOKS, hook)], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: e,
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const shell = (tool, command) => ({ hook_event_name: "PreToolUse", tool_name: tool, tool_input: { command } });
const file = (tool, tool_input) => ({ hook_event_name: "PreToolUse", tool_name: tool, tool_input });
// This user's ~/.claude as the tools spell it: native separators, forward slashes, Git Bash's /c/Users form on Windows
const HOME = os.homedir();
const home = (...p) => path.join(HOME, ".claude", ...p);
const homePosix = (...p) => [HOME.replace(/\\/g, "/"), ".claude", ...p].join("/");
const homeShell = (...p) =>
  (process.platform === "win32" && /^[A-Za-z]:/.test(HOME) ? "/" + HOME[0].toLowerCase() + HOME.slice(2).replace(/\\/g, "/") : HOME) +
  ["", ".claude", ...p].join("/");

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
  "sed -i 's/web/config/' backend/arch-gates.json",
  // audit 2026-10-08: the pre-commit hook is also skipped by moving core.hooksPath or disabling husky
  "git -c core.hooksPath=/dev/null commit -m x",
  "git -c core.hooksPath= commit -m x",
  "git config core.hooksPath .nohooks && git commit -m x",
  "git --config-env=core.hooksPath=HP commit -m x",
  "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\" git commit -m x",
  "HUSKY=0 git commit -m x",
  "export HUSKY=0; git commit -m x",
  "$env:HUSKY = '0'; git commit -m x",
  // a commit status is posted by CI, never by hand
  "gh api -X POST repos/o/r/statuses/0123abc -f state=success -f context='mutation / mutation'",
  "curl -X POST https://api.github.com/repos/o/r/statuses/0123abc -d '{\"state\":\"success\"}'",
  "Invoke-RestMethod -Method Post -Uri https://api.github.com/repos/o/r/statuses/0123abc",
  // a remote ref deleted or rewritten: release tags never move, a branch is deleted by a human
  "git push --delete origin v1",
  "git push -d origin v1",
  "rtk git push origin :v1",
  "git push origin :refs/tags/v1",
  "git push origin +v6",
  "git push origin +refs/tags/v6:refs/tags/v6",
  "cd backend && git push origin --delete feat",
  // review of PR #31: git takes any unique prefix of a long option and bundles short flags; --force is a rewrite too
  "git commit --no-veri -m x",
  "git commit -anm x",
  "git push --del origin v1",
  "git push --force origin v6",
  "git push -f origin v6",
  "git push --force-with-lease origin v6",
  "git push -fu origin v6",
  "git push --force --tags origin",
  // the REST twins of a deleted or rewritten ref
  "gh api -X DELETE repos/o/r/git/refs/tags/v1",
  "gh api --method PATCH repos/o/r/git/refs/tags/v6 -f sha=0123abc -F force=true",
  "Invoke-RestMethod -Method Delete -Uri https://api.github.com/repos/o/r/git/refs/tags/v1",
  "gh release delete v1 --cleanup-tag",
  // the hook scripts themselves and .git/config are gate files
  "rm .git/hooks/pre-commit && git commit -m x",
  "printf '[core]\\n\\thooksPath = /dev/null\\n' >> .git/config",
  "echo '' > .husky/pre-commit",
  "Set-Content .pre-commit-config.yaml ''",
  // HUSKY=0 set for the command, in every spelling the two shells have
  "cd x && FOO=1 HUSKY=0 git commit -m x",
  "HUSKY_SKIP_HOOKS=1 git commit -m x",
  "Set-Item env:HUSKY 0; git commit -m x",
  "Set-Item -Path env:HUSKY -Value '0'; git commit -m x",
  "[Environment]::SetEnvironmentVariable('HUSKY','0'); git commit -m x",
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
  "git config --get core.hooksPath",
  "git config --unset core.hooksPath",
  "gh api repos/o/r/commits/0123abc/statuses",
  "gh api repos/o/r/commits/0123abc/status",
  "git tag -a v6 -m 'release v6' && git push origin v6",
  "git push origin refs/tags/v6",
  // review of PR #31: a read, a mention in a message or a grep, a creation, an ordinary config write
  "git config --get core.hooksPath 2>/dev/null",
  "git config --unset core.hooksPath && git commit -m x",
  "grep -rn core.hooksPath .",
  "git commit -m 'docs: explain core.hooksPath handling'",
  "git commit -m 'docs: HUSKY=0 is no longer honoured'",
  "grep -rn HUSKY=0 docs/",
  "HUSKY=1 git commit -m x",
  "git commit --amend --no-edit",
  "git push -n origin feat",
  "gh api repos/o/r/git/refs/tags/v1",
  "gh api -X POST repos/o/r/git/refs -f ref=refs/tags/v6 -f sha=0123abc",
  "gh release create v6 --notes x",
  "cat .git/config",
  "git remote add upstream https://github.com/o/r.git",
  "git config user.name 'Remi'",
  "git branch -u origin/feat",
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
    file("Edit", { file_path: "C:\\repo\\backend\\arch-gates.json", old_string: "\"app.routes\"", new_string: "\"app.routes\", \"app.config\"" }),
    // Windows paths are case-insensitive: another spelling reaches the same file
    file("Write", { file_path: "C:\\repo\\backend\\ARCH-GATES.JSON", content: "" }),
    file("Write", { file_path: "C:\\repo\\backend\\Import-Cycles-Baseline.json", content: "" }),
    file("Write", { file_path: "C:\\repo\\.GitHub\\Workflows\\backend.yml", content: "" }),
    // review of PR #31: the pre-commit hook scripts themselves and .git/config
    file("Write", { file_path: "/repo/.husky/pre-commit", content: "" }),
    file("Edit", { file_path: "C:\\repo\\.git\\hooks\\pre-commit", old_string: "shellcheck", new_string: "true" }),
    file("Write", { file_path: "/repo/.pre-commit-config.yaml", content: "" }),
    file("Edit", { file_path: "/repo/.git/config", old_string: "[core]", new_string: "[core]\n\thooksPath = /dev/null" }),
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

  // a [[tool.mypy.overrides]] array table is a gate section too (an override can disable mypy for a module)
  const o = path.join(dir, "override", "pyproject.toml");
  fs.mkdirSync(path.dirname(o));
  fs.writeFileSync(o, '[project]\nname = "x"\n\n[tool.mypy]\nstrict = true\n\n[[tool.mypy.overrides]]\nmodule = "legacy.*"\nignore_errors = false\n');
  assert.equal(run("protect-gates.js", file("Edit", { file_path: o, old_string: "ignore_errors = false", new_string: "ignore_errors = true" })).code, 2);
  assert.equal(run("protect-gates.js", file("Edit", { file_path: o, old_string: 'module = "legacy.*"', new_string: 'module = "*"' })).code, 2);
  assert.equal(run("protect-gates.js", file("Write", { file_path: o, content: fs.readFileSync(o, "utf8") + '\n[[tool.mypy.overrides]]\nmodule = "app.*"\nignore_errors = true\n' })).code, 2);
  assert.equal(run("protect-gates.js", file("Edit", { file_path: o, old_string: 'name = "x"', new_string: 'name = "z"' })).code, 0);
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
    file("Edit", { file_path: "C:\\Users\\u\\.Claude\\Settings.json", old_string: "a", new_string: "b" }),
    shell("Bash", "echo '{}' > /home/u/.claude/settings.json"),
    shell("Bash", "sed -i 's/protect-gates//' /home/u/.claude/settings.json"),
    shell("PowerShell", "Set-Content C:\\Users\\u\\.claude\\settings.json '{}'"),
    shell("PowerShell", "Remove-Item C:\\Users\\u\\.claude\\hooks\\protect-gates.js"),
    // relative spellings, as a shell command names them from the project root
    shell("Bash", "echo '{}' > .claude/settings.local.json"),
    shell("PowerShell", "Set-Content .claude\\settings.local.json '{}'"),
    // a soft command rule in the same compound must not downgrade the harness write to a warning
    shell("Bash", "echo '{}' > /home/u/.claude/settings.json; pnpm lint:arch:baseline"),
    shell("Bash", "git commit -n -m x && sed -i 's/protect-gates//' /home/u/.claude/settings.json"),
    // the rest of what install.sh deploys, under this user's ~/.claude only (2026-10-09): CLAUDE.md, agents, commands, scripts, mods
    file("Edit", { file_path: home("CLAUDE.md"), old_string: "a", new_string: "b" }),
    file("Write", { file_path: home("agents", "plan-reviewer.md"), content: "" }),
    file("Write", { file_path: homePosix("commands", "feature.md"), content: "" }),
    file("Edit", { file_path: homeShell("mods", "ponytail", "hooks", "claude-codex-hooks.json"), old_string: "a", new_string: "b" }),
    shell("Bash", "cp scripts/statusline.sh ~/.claude/scripts/"),
    shell("Bash", "cp -r mods/ponytail ~/.claude/mods/"),
    shell("Bash", `sed -i 's/x/y/' ${homePosix("scripts", "session-start.sh")}`),
    shell("Bash", "cat x > ~/.claude/CLAUDE.md"),
    shell("PowerShell", `Copy-Item .\\commands\\feature.md ${home("commands", "feature.md")}`),
    shell("PowerShell", `Remove-Item ${home("agents", "spec-tester.md")}`),
  ];
  for (const c of self) {
    for (const env of [{}, { PROTECT_GATES: "off" }]) {
      const r3 = run("protect-gates.js", c, env);
      assert.equal(r3.code, 2, `${JSON.stringify(c.tool_input)} env=${JSON.stringify(env)}\n${r3.err}`);
      assert.match(r3.err, /harness itself/);
    }
  }
  // reading or running the harness is fine
  assert.equal(run("protect-gates.js", shell("Bash", "cat ~/.claude/settings.json"), { PROTECT_GATES: "off" }).code, 0);
  assert.equal(run("protect-gates.js", shell("Bash", "cat /home/u/.claude/settings.json")).code, 0);
  for (const c of [
    "bash ~/.claude/scripts/vibe-toggle.sh on",
    "bash ~/.claude/scripts/style-toggle.sh ponytail full >/dev/null",
    "cat ~/.claude/CLAUDE.md",
    "node ~/.claude/mods/ponytail/hooks/ponytail-activate.js",
    `ls ${homePosix("agents")}`,
  ]) assert.equal(run("protect-gates.js", shell("Bash", c)).code, 0, c);
});

test("a project's own .claude/agents and .claude/commands: blocked by default, lifted by PROTECT_GATES=off; another home counts as a project", () => {
  const cases = [
    file("Write", { file_path: "/repo/.claude/commands/deploy.md", content: "" }),
    file("Edit", { file_path: "C:\\repo\\.claude\\agents\\reviewer.md", old_string: "a", new_string: "b" }),
    file("Write", { file_path: "/home/other/.claude/commands/x.md", content: "" }),
    shell("Bash", "echo x > .claude/commands/deploy.md"),
    shell("Bash", "cp a .claude/agents/reviewer.md"),
    shell("PowerShell", "Set-Content .claude\\agents\\reviewer.md 'x'"),
  ];
  for (const c of cases) {
    const r = run("protect-gates.js", c);
    assert.equal(r.code, 2, `${JSON.stringify(c.tool_input)}\n${r.err}`);
    assert.match(r.err, /agent or command|gate/i);
    assert.doesNotMatch(r.err, /harness itself/);
    const off = run("protect-gates.js", c, { PROTECT_GATES: "off" });
    assert.equal(off.code, 0, `${JSON.stringify(c.tool_input)} off\n${off.err}`);
    assert.match(JSON.parse(off.out).systemMessage, /would have blocked/);
  }
  assert.equal(run("protect-gates.js", shell("Bash", "cat .claude/commands/deploy.md")).code, 0);
});

test("git merge and pushes to main pass only inside a /create-commit the human typed", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "protect-gates-git-"));
  const git = (...a) => spawnSync("git", ["-C", dir, ...a], { encoding: "utf8" });
  git("init", "-q", "-b", "main");
  const transcript = path.join(dir, "t.jsonl");
  const turn = (origin, content) => JSON.stringify({ type: "user", message: { role: "user", content }, ...(origin && { origin: { kind: origin } }) });
  const typed = turn("human", "<command-message>create-commit</command-message>\n<command-name>/create-commit</command-name>");
  const said = (lines) => fs.writeFileSync(transcript, lines.join("\n") + "\n");
  const gate = (command, tool = "Bash") => run("protect-gates.js", { ...shell(tool, command), cwd: dir, transcript_path: transcript });

  const humanOnly = [
    "git merge feat",
    "rtk git merge --no-ff feat",
    "git push", // bare, while on main
    "rtk git push origin",
    "git push origin HEAD",
    "git push -u origin HEAD:main",
    "git push origin feat:refs/heads/master",
    "git push --all origin",
    "git switch feat && git merge main",
  ];
  // a ref deleted or rewritten, main included, has no exemption at all: GitHub's rules refuse it either way (review of PR #31)
  const never = ["git push origin +feat:main", "git push origin :main", "git push --delete origin main", "git push --delete origin v1", "git push origin :v1", "git push origin +v6", "git push --force origin v6"];
  const free = ["git merge-base main feat", "git log --merges", "git push -u origin feat", "git push origin feat:feat"];

  // red: Claude alone (plain human turn, or the human's answer coming back as a tool_result)
  said([turn("human", "pousse sur main"), turn(null, [{ type: "tool_result", content: "/create-commit" }])]);
  for (const tool of ["Bash", "PowerShell"]) {
    for (const c of humanOnly) assert.equal(gate(c, tool).code, 2, `${tool}: ${c}`);
    for (const c of never) assert.equal(gate(c, tool).code, 2, `${tool}: ${c}`);
    for (const c of free) assert.equal(gate(c, tool).code, 0, `${tool}: ${c}`);
  }
  // red: the marker is only valid in the *latest* human turn
  said([typed, turn("human", "et maintenant merge"), turn(null, [{ type: "tool_result", content: "" }])]);
  assert.equal(gate("git merge feat").code, 2);
  // green: /create-commit typed by the human, tool results after it do not reset it
  said([turn("human", "x"), typed, turn(null, [{ type: "tool_result", content: "" }])]);
  for (const c of humanOnly) assert.equal(gate(c).code, 0, c);
  for (const tool of ["Bash", "PowerShell"]) for (const c of never) assert.equal(gate(c, tool).code, 2, `${tool}: ${c}`);
  // no transcript at all: blocked
  assert.equal(run("protect-gates.js", { ...shell("Bash", "git merge feat"), cwd: dir }).code, 2);
  // review of PR #7: git global options, push options with a value, tag-only pushes
  said([turn("human", "x")]);
  for (const c of [
    "git -c advice.detachedHead=false merge feat",
    "git -c a=b push origin main",
    `git -C "${dir}" --no-pager push`,
    "git push -o ci.skip origin",
    "git push --push-option ci.skip origin",
    "git push --tags origin main",
  ]) assert.equal(gate(c).code, 2, c);
  assert.equal(gate("git push --tags origin").code, 0);
  assert.equal(gate("git push --tags").code, 0);

  // bare push from a feature branch is free
  git("switch", "-q", "-c", "feat");
  assert.equal(gate("git push").code, 0);
  assert.equal(gate("git switch main && git push").code, 2);
  // the branch is read in the repository the push targets, not in the tool's cwd
  const other = fs.mkdtempSync(path.join(os.tmpdir(), "protect-gates-other-"));
  spawnSync("git", ["-C", other, "init", "-q", "-b", "main"]);
  const fromFeat = (command) => run("protect-gates.js", { ...shell("Bash", command), cwd: dir, transcript_path: transcript }).code;
  assert.equal(fromFeat(`git -C "${other}" push`), 2);
  assert.equal(fromFeat(`cd "${other}" && git push`), 2);
  assert.equal(fromFeat(`cd "${other}" && cd "${dir}" && git push`), 0);
  assert.equal(fromFeat('cd "$SOMEWHERE" && git push'), 2); // a directory that cannot be resolved is not trusted

  // the transcripts that carry the marker are part of the harness
  for (const c of [
    file("Write", { file_path: "C:\\Users\\u\\.claude\\projects\\C--repo\\s.jsonl", content: typed }),
    shell("Bash", `echo '${typed}' >> /home/u/.claude/projects/C--repo/s.jsonl`),
  ]) {
    const r = run("protect-gates.js", c, { PROTECT_GATES: "off" });
    assert.equal(r.code, 2, JSON.stringify(c.tool_input));
    assert.match(r.err, /harness itself/);
  }
});

test("inside a /init-gates the human typed, a gate file that does not exist yet may be created, never changed", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "protect-gates-init-"));
  fs.mkdirSync(path.join(dir, "frontend"));
  fs.writeFileSync(path.join(dir, "frontend", ".dependency-cruiser.cjs"), "module.exports = {};\n");
  fs.writeFileSync(path.join(dir, "frontend", "import-cycles-baseline.json"), "[]\n");
  fs.mkdirSync(path.join(dir, "backend"));
  fs.writeFileSync(path.join(dir, "backend", "pyproject.toml"), '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 100\n');
  fs.mkdirSync(path.join(dir, "mutated"));
  fs.writeFileSync(path.join(dir, "mutated", "pyproject.toml"), '[project]\nname = "y"\n\n[tool.mutmut]\nsource_paths = ["app/a.py"]\n');
  const transcript = path.join(dir, "t.jsonl");
  const said = (content) => fs.writeFileSync(transcript, JSON.stringify({ type: "user", origin: { kind: "human" }, message: { content } }) + "\n");
  const typed = (name) => `<command-message>${name}</command-message>\n<command-name>/${name}</command-name>`;
  const gate = (payload) => run("protect-gates.js", { ...payload, cwd: dir, transcript_path: transcript }).code;
  const at = (...p) => path.join(dir, ...p);
  const depcruiseBaseline = "npx --yes -p dependency-cruiser@17.4.3 depcruise src --config .dependency-cruiser.cjs --output-type baseline > frontend/.dependency-cruiser-known-violations.json";

  const creations = [
    file("Write", { file_path: at("backend", "arch-gates.json"), content: "{}" }),
    file("Write", { file_path: at(".github", "workflows", "arch-gates.yml"), content: "" }),
    shell("Bash", depcruiseBaseline), // reads the existing config, creates the baseline
    shell("Bash", "cd frontend && npx --yes depcruise src --output-type baseline > .dependency-cruiser-known-violations.json"),
    file("Write", { file_path: at(".github", "workflows", "baseline-ratchet.yml"), content: "" }),
    // the mutation and quality gates /init-gates creates since 2026-10-06
    file("Write", { file_path: at(".github", "workflows", "mutation-gate.yml"), content: "" }),
    file("Write", { file_path: at(".github", "workflows", "quality-gates.yml"), content: "" }),
    file("Write", { file_path: at("backend", "complexity-baseline.json"), content: "[]" }),
    file("Write", { file_path: at("frontend", "duplication-baseline.json"), content: "[]" }),
    // a [tool.mutmut] section added to a pyproject.toml that has none, the other gate sections untouched
    file("Edit", { file_path: at("backend", "pyproject.toml"), old_string: 'name = "x"\n', new_string: 'name = "x"\n\n[tool.mutmut]\nsource_paths = ["app/x.py"]\nalso_copy = ["app"]\n' }),
    file("Write", { file_path: at("backend", "pyproject.toml"), content: '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 100\n\n[tool.mutmut]\nsource_paths = ["app/x.py"]\n' }),
  ];
  const changes = [
    // the mutation baseline comes from the PR's first CI run, never from Claude, even here
    file("Write", { file_path: at("backend", "mutation-baseline.json"), content: "[]" }),
    // an existing [tool.mutmut] section, or another gate section riding along with the new one
    file("Edit", { file_path: at("mutated", "pyproject.toml"), old_string: 'source_paths = ["app/a.py"]', new_string: 'source_paths = ["app/b.py"]' }),
    file("Edit", { file_path: at("mutated", "pyproject.toml"), old_string: 'name = "y"\n', new_string: 'name = "y"\n\n[tool.mutmut.extra]\nx = 1\n' }),
    file("Edit", { file_path: at("backend", "pyproject.toml"), old_string: 'line-length = 100\n', new_string: 'line-length = 120\n\n[tool.mutmut]\nsource_paths = ["app/x.py"]\n' }),
    file("Edit", { file_path: at("backend", "pyproject.toml"), old_string: 'name = "x"\n', new_string: 'name = "x"\n\n[tool.pytest.ini_options]\naddopts = "-p no:cacheprovider"\n' }),
    file("Write", { file_path: at("frontend", ".dependency-cruiser.cjs"), content: "" }),
    file("Edit", { file_path: at("frontend", ".dependency-cruiser.cjs"), old_string: "{}", new_string: "{ forbidden: [] }" }),
    file("Write", { file_path: at("frontend", "import-cycles-baseline.json"), content: "[]" }),
    shell("Bash", "echo '[]' > frontend/import-cycles-baseline.json"),
    shell("Bash", "rm frontend/import-cycles-baseline.json"),
    shell("Bash", "cp x.json frontend/new-baseline.json && rm frontend/import-cycles-baseline.json"),
    shell("Bash", "uv run python check_imports.py cycles --update-baseline"),
    // review of PR #10: only the files /init-gates creates, nothing else that is absent
    file("Write", { file_path: at(".github", "workflows", "deploy.yml"), content: "" }),
    file("Write", { file_path: at("ruff.toml"), content: "" }),
    file("Write", { file_path: at("frontend", "eslint.config.js"), content: "" }),
    // review of PR #10: a redirect is resolved in the directory its segment runs in
    shell("Bash", "cd frontend && echo '[]' > import-cycles-baseline.json"),
    shell("Bash", "cd \"$SOMEWHERE\" && echo '[]' > .dependency-cruiser-known-violations.json"),
  ];

  // red: no /init-gates, or another command typed
  for (const t of [typed("create-commit"), "init the gates please"]) {
    said(t);
    for (const c of creations) assert.equal(gate(c), 2, `${t}: ${JSON.stringify(c.tool_input)}`);
  }
  // green for creations only
  said(typed("init-gates"));
  for (const c of creations) assert.equal(gate(c), 0, JSON.stringify(c.tool_input));
  for (const c of changes) assert.equal(gate(c), 2, JSON.stringify(c.tool_input));
  // the harness itself is never a creation
  assert.equal(gate(file("Write", { file_path: at(".claude", "settings.local.json"), content: "{}" })), 2);
});

// ------------------------------------------------- vendored cc-safe-setup guards
const skip = hasBashAndJq ? false : "bash + jq not available";

test("the three bash guards refuse everything when jq is missing, instead of reading an empty command", { skip: hasBash ? false : "bash not available" }, () => {
  for (const hook of ["branch-guard.sh", "destructive-guard.sh", "secret-guard.sh"]) {
    const r = run(hook, shell("Bash", "git push origin main"), { PATH: "" });
    assert.equal(r.code, 2, `${hook}\n${r.err}`);
    assert.match(r.err, /jq/);
  }
});
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
    assert.equal(guard("secret-guard.sh", tool, 'git add ".env"'), 2, tool);
    assert.equal(guard("secret-guard.sh", tool, "git add '.env.local'"), 2, tool);
    assert.equal(guard("secret-guard.sh", tool, 'git add "config/credentials.json"'), 2, tool);
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
