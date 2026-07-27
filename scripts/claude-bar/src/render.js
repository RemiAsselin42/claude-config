import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { BRAND, BRAND_DARK, BRAND_LIGHT, BRAND_LIGHTER, TRACK, DIM, RESET, intensityColor } from './colors.js';
import { getGitInfo } from './git.js';
import { getConfig } from './config.js';

const COMPACT_BUFFER = 33_000;

function isAutoCompactEnabled() {
  try {
    const data = JSON.parse(readFileSync(join(homedir(), '.claude.json'), 'utf8'));
    return data.autoCompactEnabled !== false; // absent or true = on
  } catch {
    return true; // default is on
  }
}

const BAR_W = 10;
const SEP = `${DIM} \u2502 ${RESET}`;

function fmtTokens(t) {
  if (t >= 1_000_000) {
    const m = Math.floor(t / 1_000_000);
    const r = Math.floor((t % 1_000_000) / 100_000);
    return r > 0 ? `${m}.${r}M` : `${m}M`;
  }
  if (t >= 1000) return `${Math.floor(t / 1000)}k`;
  return String(t);
}

function progressBar(pct, intensity) {
  const filled = Math.min(Math.round(pct * BAR_W / 100), BAR_W);
  const empty = BAR_W - filled;
  let bar = '';
  if (filled > 0) bar += `${intensity}${'█'.repeat(filled)}`;
  if (empty > 0) bar += `${TRACK}${'░'.repeat(empty)}`;
  return bar + RESET;
}

function shortDuration(seconds) {
  if (seconds <= 0) return '0s';
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h >= 24) return `${Math.floor(h / 24)}d ${h % 24}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  if (s > 0) return `${s}s`;
  return '< 1m';
}

function fmtCountdown(resetsAt) {
  if (!resetsAt) return null;
  const remain = (new Date(resetsAt) - Date.now()) / 1000;
  return shortDuration(remain);
}

/**
 * Render 3-line statusline.
 * @param {object} input  - Claude Code statusline JSON
 * @param {object|null} usage - { fiveHour: { utilization, resetsAt }, sevenDay } or null
 */
export function render(input, usage) {
  const config = getConfig();

  // ── Parse input ────────────────────────────────────────────
  const model = input?.model?.display_name || '?';
  const rawCtxSize = input?.context_window?.context_window_size || 200_000;
  const linesAdded = input?.cost?.total_lines_added || 0;
  const linesRemoved = input?.cost?.total_lines_removed || 0;

  const cur = input?.context_window?.current_usage || {};
  const usedTokens = (cur.input_tokens || 0) + (cur.cache_creation_input_tokens || 0) + (cur.cache_read_input_tokens || 0);

  // Effective context limit: subtract 33k compaction buffer when auto-compact is on
  const ctxSize = isAutoCompactEnabled() ? rawCtxSize - COMPACT_BUFFER : rawCtxSize;
  const pct = Math.min(100, Math.floor(usedTokens * 100 / ctxSize));

  const usedFmt = fmtTokens(usedTokens);
  const totalFmt = fmtTokens(ctxSize);
  const ctxIntensity = intensityColor(pct);

  // Label column width — keep in sync with the "Caveman" label statusline.sh
  // inserts (7 chars) so all labels align.
  const PAD = 7;
  const label = (t) => `${BRAND}${t.padEnd(PAD)}${RESET}${SEP}`;

  // ── LINE 1: Model ──────────────────────────────────────────
  const lineModel = `${label('Model')}${BRAND}${model}${RESET}`;

  // ── LINE 2: Cache (context window) ─────────────────────────
  const bar1 = progressBar(pct, ctxIntensity);
  const lineCache = `${label('Cache')}${DIM}${usedFmt}/${totalFmt}${RESET} [${bar1}] ${ctxIntensity}${pct}%${RESET}`;

  // ── LINE 3: Usage — Session (5h) | Week (all models) | Week (per-model) ──
  const seg = (name, utilization, resetsAt) => {
    const p = Math.round(utilization);
    const i = intensityColor(p);
    const countdown = fmtCountdown(resetsAt) || '--';
    return `${DIM}${name} ·${RESET} [${progressBar(p, i)}] ${i}${p}%${RESET} ${DIM}· ${countdown}${RESET}`;
  };
  const segs = [];
  if (usage?.fiveHour) {
    segs.push(seg('Session', usage.fiveHour.utilization, usage.fiveHour.resetsAt));
  }
  if (usage?.sevenDay) {
    segs.push(seg('Week', usage.sevenDay.utilization, usage.sevenDay.resetsAt));
  }
  for (const w of usage?.weeklyScoped || []) {
    segs.push(seg(w.label ? `Week ${w.label}` : 'Week', w.utilization, w.resetsAt));
  }
  const lineUsage = segs.length
    ? `${label('Usage')}${segs.join(`${DIM} | ${RESET}`)}`
    : `${label('Usage')}${DIM}No active session${RESET}`;

  // ── LINE 3: Git ────────────────────────────────────────────
  const cwd = input?.workspace?.current_dir || '.';
  const projectDir = input?.workspace?.project_dir || cwd;
  const projectName = projectDir.split('/').pop();
  const git = getGitInfo(cwd);

  let line3 = '';
  if (git?.branch) {
    line3 = `${label('Github')}${BRAND}\u2387 ${git.branch}${RESET}`;
    if (git.worktree) line3 += `${DIM} \u00B7 \u16B0 ${projectName}${RESET}`;
    if (linesAdded > 0 || linesRemoved > 0) {
      line3 += `${DIM} \u00B7 ${RESET}${BRAND_LIGHT}+${linesAdded}${RESET} ${BRAND_DARK}-${linesRemoved}${RESET}`;
    }
  }

  // ── Output ─────────────────────────────────────────────────
  let out = '';
  if (config.lines.context) out += lineModel + '\n' + lineCache + '\n';
  if (config.lines.session) out += lineUsage + '\n';
  if (config.lines.git && line3) out += line3 + '\n';
  process.stdout.write(out);
}
