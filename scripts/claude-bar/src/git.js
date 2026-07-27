import { execSync } from 'child_process';
import { readFileSync, writeFileSync, statSync } from 'fs';
import { createHash } from 'crypto';
import { tmpdir } from 'os';
import { join } from 'path';

const CACHE_TTL = 5; // seconds

function cachePath(cwd) {
  const hash = createHash('md5').update(cwd).digest('hex');
  return join(tmpdir(), `bar-git-cache-${hash}.json`);
}

function readCache(path) {
  try {
    const stat = statSync(path);
    if (Date.now() - stat.mtimeMs < CACHE_TTL * 1000) {
      return JSON.parse(readFileSync(path, 'utf8'));
    }
  } catch {}
  return null;
}

function run(cmd, cwd) {
  try {
    return execSync(cmd, { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch {
    return '';
  }
}

/**
 * Get git info for a directory. Returns { branch, staged, modified, untracked, worktree } or null.
 */
export function getGitInfo(cwd) {
  if (!cwd) return null;

  const cp = cachePath(cwd);
  const cached = readCache(cp);
  if (cached) return cached;

  // Check if it's a git repo
  if (!run('git rev-parse --git-dir', cwd)) return null;

  const branch = run('git branch --show-current', cwd) || run('git rev-parse --short HEAD', cwd);
  const staged = run('git diff --cached --numstat', cwd).split('\n').filter(Boolean).length;
  const modified = run('git diff --numstat', cwd).split('\n').filter(Boolean).length;
  const untracked = run('git ls-files --others --exclude-standard', cwd).split('\n').filter(Boolean).length;

  const gitDir = run('git rev-parse --git-dir', cwd);
  const gitCommon = run('git rev-parse --git-common-dir', cwd);
  const worktree = gitDir !== gitCommon;

  const info = { branch, staged, modified, untracked, worktree };
  try { writeFileSync(cp, JSON.stringify(info)); } catch {}
  return info;
}
