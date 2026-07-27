import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';

const CONFIG_PATH = join(homedir(), '.bar', 'config.json');

const DEFAULTS = {
  lines: { context: true, session: true, git: true },
};

export function getConfig() {
  try {
    const data = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
    return { lines: { ...DEFAULTS.lines, ...data.lines } };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveConfig(config) {
  mkdirSync(dirname(CONFIG_PATH), { recursive: true, mode: 0o700 });
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), { mode: 0o600 });
}
