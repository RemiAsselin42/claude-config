import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { execSync } from 'child_process';
import { saveConfig } from './config.js';
import { login } from './login.js';
import { BRAND, DIM, RESET } from './colors.js';
import { multiSelect } from './prompts.js';

const CLAUDE_SETTINGS_PATH = join(homedir(), '.claude', 'settings.json');

function writeStatusLineConfig() {
  let settings = {};
  try {
    settings = JSON.parse(readFileSync(CLAUDE_SETTINGS_PATH, 'utf8'));
  } catch {}

  settings.statusLine = {
    type: 'command',
    command: 'claude-bar',
  };

  mkdirSync(dirname(CLAUDE_SETTINGS_PATH), { recursive: true });
  writeFileSync(CLAUDE_SETTINGS_PATH, JSON.stringify(settings, null, 2));
}

export default async function setup() {
  console.log();
  console.log(`${BRAND}  bar${RESET} ${DIM}— battery-themed statusline for Claude Code${RESET}`);
  console.log();

  // Line visibility prompts
  const choices = await multiSelect([
    { label: 'Context line', default: true },
    { label: 'Session / rate-limit line', default: true },
    { label: 'Git line', default: true },
  ]);

  // Save config
  const config = {
    lines: {
      context: choices[0],
      session: choices[1],
      git: choices[2],
    },
  };
  saveConfig(config);
  console.log(`  ${DIM}Saved preferences to ~/.bar/config.json${RESET}`);

  // Install globally
  console.log(`\n  Installing globally...`);
  try {
    execSync('npm install -g @allthingsclaude/bar', { stdio: 'inherit' });
  } catch {
    console.error(`\n  ${BRAND}Warning:${RESET} Global install failed. You may need to run with sudo or fix npm permissions.`);
  }

  // OAuth login (only needed for session/rate-limit data)
  if (config.lines.session) {
    console.log(`\n  ${BRAND}Authenticating with Claude...${RESET}\n`);
    await login();
  }

  // Write statusLine config to ~/.claude/settings.json
  writeStatusLineConfig();
  console.log(`\n  ${DIM}Configured statusLine in ~/.claude/settings.json${RESET}`);

  // Success
  console.log();
  console.log(`  ${BRAND}Setup complete!${RESET} Restart Claude Code to see your statusline.`);
  console.log();
}
