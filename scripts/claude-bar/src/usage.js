import { readFileSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { request } from './http.js';
import { resolveToken, refreshToken } from './tokens.js';

const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const CACHE_PATH = join(tmpdir(), 'bar-usage-cache.json');
const CACHE_TTL = 30; // seconds

function readCache() {
  try {
    const data = JSON.parse(readFileSync(CACHE_PATH, 'utf8'));
    if (Date.now() - data._ts < CACHE_TTL * 1000) return data;
  } catch {}
  return null;
}

function writeCache(data) {
  try {
    writeFileSync(CACHE_PATH, JSON.stringify({ ...data, _ts: Date.now() }));
  } catch {}
}

async function fetchUsage(accessToken) {
  const res = await request(USAGE_URL, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'anthropic-beta': 'oauth-2025-04-20',
      'User-Agent': 'Bar/0.1.0',
    },
  });
  return res;
}

/**
 * Get usage data. Returns { fiveHour, sevenDay } or null.
 * Uses file cache (30s TTL), auto-refreshes token on 401.
 */
export async function getUsage() {
  const cached = readCache();
  if (cached) return cached;

  const tokenData = resolveToken();
  if (!tokenData) return null;

  let res = await fetchUsage(tokenData.accessToken).catch(() => null);
  if (!res) return null;

  // On 401, try refreshing the token once
  if (res.status === 401) {
    const refreshed = await refreshToken(tokenData);
    if (refreshed) {
      // Save refreshed token back (best-effort)
      try {
        const { writeFileSync: ws, mkdirSync } = await import('fs');
        const { join: j } = await import('path');
        const { homedir: h } = await import('os');
        const p = j(h(), '.bar', 'tokens.json');
        mkdirSync(j(h(), '.bar'), { recursive: true, mode: 0o700 });
        ws(p, JSON.stringify(refreshed, null, 2), { mode: 0o600 });
      } catch {}
      res = await fetchUsage(refreshed.accessToken).catch(() => null);
      if (!res) return null;
    }
  }

  if (!res.ok) return null;

  try {
    const json = JSON.parse(res.body);
    // API returns utilization as percentage (e.g. 23.5 = 23.5%).
    // Store raw Doubles; round only at display time. fiveHour is null when
    // there is no active 5-hour session window.
    const data = {
      fiveHour: json.five_hour
        ? {
            utilization: json.five_hour.utilization ?? 0,
            resetsAt: json.five_hour.resets_at || null,
          }
        : null,
      sevenDay: json.seven_day
        ? {
            utilization: json.seven_day.utilization ?? 0,
            resetsAt: json.seven_day.resets_at || null,
          }
        : null,
      // Per-model weekly windows (e.g. Fable) come from the limits array.
      weeklyScoped: Array.isArray(json.limits)
        ? json.limits
            .filter((l) => l.kind === 'weekly_scoped')
            .map((l) => ({
              label: l.scope?.model?.display_name || l.scope?.surface || '',
              utilization: l.percent ?? 0,
              resetsAt: l.resets_at || null,
            }))
        : [],
    };
    writeCache(data);
    return data;
  } catch {
    return null;
  }
}
