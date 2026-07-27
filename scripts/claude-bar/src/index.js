#!/usr/bin/env node

import { render } from './render.js';
import { getUsage } from './usage.js';
import { login, logout } from './login.js';
import setup from './setup.js';

const args = process.argv.slice(2);

if (args.includes('login')) {
  await login();
} else if (args.includes('logout')) {
  logout();
} else if (process.stdin.isTTY) {
  // Interactive terminal (e.g. npx @allthingsclaude/bar or claude-bar) — run setup wizard
  await setup();
} else {
  // Piped input from Claude Code — read stdin JSON, fetch usage, render
  let raw = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) {
    raw += chunk;
  }

  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    input = {};
  }

  let usage = null;
  try {
    usage = await getUsage();
  } catch {}

  render(input, usage);
}
