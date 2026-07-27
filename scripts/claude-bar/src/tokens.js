import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { request } from './http.js';

const TOKEN_URL = 'https://platform.claude.com/v1/oauth/token';
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

function barTokenPath() {
  return join(homedir(), '.bar', 'tokens.json');
}

function readBarToken() {
  const data = readJson(barTokenPath());
  if (!data?.accessToken) return null;
  return data;
}

function readBatteryTokens() {
  const dir = join(homedir(), '.battery', 'tokens');
  let files;
  try {
    files = readdirSync(dir).filter(f => f.endsWith('.json'));
  } catch {
    return null;
  }
  for (const f of files) {
    const data = readJson(join(dir, f));
    if (data?.accessToken) return data;
  }
  return null;
}

export async function refreshToken(tokenData) {
  if (!tokenData?.refreshToken) return null;
  try {
    const body = JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: tokenData.refreshToken,
      client_id: CLIENT_ID,
    });
    const res = await request(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });
    if (!res.ok) return null;
    const json = JSON.parse(res.body);
    return {
      accessToken: json.access_token,
      refreshToken: json.refresh_token || tokenData.refreshToken,
      expiresIn: json.expires_in || 3600,
    };
  } catch {
    return null;
  }
}

/**
 * Resolve an access token. Returns { accessToken, refreshToken?, expiresIn? } or null.
 * Priority: env var → bar tokens → battery tokens → null
 */
export function resolveToken() {
  // 1. Env var (plain access token string)
  const envToken = process.env.BAR_TOKEN || process.env.CLAUDE_CODE_OAUTH_TOKEN;
  if (envToken) return { accessToken: envToken };

  // 2. Bar's own tokens
  const bar = readBarToken();
  if (bar) return bar;

  // 3. Battery tokens
  const battery = readBatteryTokens();
  if (battery) return battery;

  return null;
}
