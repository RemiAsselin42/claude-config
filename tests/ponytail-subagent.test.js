// The harness agents in agents/ (plan-reviewer, spec-tester, diff-reviewer) run
// without ponytail: its SubagentStart hook injects the lazy-dev ruleset into every
// subagent, and a reviewer or a test writer must not be told to cut corners. The
// exclusion is the `matcher` of the SubagentStart entry in the vendored
// mods/ponytail/hooks/claude-codex-hooks.json, which Claude Code evaluates against
// the subagent's frontmatter `name` before running the hook (hooks reference,
// "SubagentStart": exact names, a `|` list, or any other string as an unanchored
// JavaScript RegExp tested with RegExp.prototype.test; an omitted, empty or `*`
// matcher runs for every agent). Reading agents/ keeps a fourth harness agent
// covered the day it is added.
//
//   node --test tests/ponytail-subagent.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repo = path.join(__dirname, '..');
const hooksFile = path.join(repo, 'mods', 'ponytail', 'hooks', 'claude-codex-hooks.json');
const entries = JSON.parse(fs.readFileSync(hooksFile, 'utf8')).hooks.SubagentStart;

const harnessAgents = fs.readdirSync(path.join(repo, 'agents'))
  .filter((f) => f.endsWith('.md'))
  .map((f) => /^name:\s*(.+?)\s*$/m.exec(fs.readFileSync(path.join(repo, 'agents', f), 'utf8'))[1]);

// Claude Code's matcher rule for SubagentStart, as documented.
function hookRunsFor(entry, agentType) {
  const m = entry.matcher;
  if (m === undefined || m === '' || m === '*') return true;
  if (/^[\w|,]+$/.test(m)) return m.split(/[|,]/).includes(agentType);
  return new RegExp(m).test(agentType);
}

test('the three harness agents are what agents/ declares', () => {
  assert.deepEqual([...harnessAgents].sort(), ['diff-reviewer', 'plan-reviewer', 'spec-tester']);
  assert.ok(entries.length >= 1, 'ponytail declares a SubagentStart hook');
});

test('no SubagentStart entry of ponytail runs for a harness agent', () => {
  for (const entry of entries) {
    for (const name of harnessAgents) {
      assert.equal(hookRunsFor(entry, name), false, `${name} would receive the ponytail ruleset`);
    }
  }
});

test('every other subagent still receives the ruleset, the unnamed one included', () => {
  for (const entry of entries) {
    for (const name of ['Explore', 'general-purpose', 'Plan', 'claude-code-guide', 'plan-reviewer-v2', '']) {
      assert.equal(hookRunsFor(entry, name), true, `"${name}" would lose the ponytail ruleset`);
    }
  }
});
