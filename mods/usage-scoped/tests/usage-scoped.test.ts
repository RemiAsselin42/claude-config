import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// Acceptance tests of the usage-scoped mod, written from its spec and plan before the
// code: the mod is driven through `$` (events raised through it) and `on` (engine ops
// answered beneath it) alone. No network: `http.fetch` is answered here.
//
//   claude plugin test mods/usage-scoped

const URL = 'https://api.anthropic.com/api/oauth/usage'
const HANDLE = 'tok-7f3a9c-secret'
const CONFIG_DIR = '/cfg/claude'
const FILE = `${CONFIG_DIR}/.usage-scoped`
const MEASURE = { context: { window: 1000000 }, rateLimits: [], changed: ['rateLimits'] }
/** 2026-10-17T00:00:00Z in epoch seconds. */
const RESET = 1792195200

type Limit = Record<string, unknown>
const scoped = (name: string, percent: unknown, resetsAt: unknown): Limit => ({
  kind: 'weekly_scoped',
  percent,
  resets_at: resetsAt,
  scope: { model: { display_name: name } },
})
const body = (limits: Limit[]) =>
  JSON.stringify({ five_hour: { utilization: 10 }, seven_day: { utilization: 30 }, limits })

// The engine hands a hook each path made absolute for the machine the tests run on: on
// Windows `/cfg/claude` arrives as `C:\cfg\claude`. Paths are compared whole, once the
// separators agree and the drive put in front of a path that had none is dropped.
function isPath(given: string, expected: string): boolean {
  const slashes = (path: string) => path.replace(/\\/g, '/')
  const hasDrive = /^[A-Za-z]:/.test(expected)
  return slashes(hasDrive ? given : given.replace(/^[A-Za-z]:/, '')) === slashes(expected)
}

function harness(on: On, env: Record<string, string> = { CLAUDE_CONFIG_DIR: CONFIG_DIR }) {
  const clock = mock.clock(on)
  mock.env(on, env)
  const state = {
    /** The handle `session.authorize` answers. */
    handle: { handle: HANDLE, kind: 'bearer' } as { handle: string; kind: string } | null,
    status: 200,
    text: body([scoped('Fable', 12, '2026-10-17T00:00:00Z')]),
    /** 'answer' answers with status and text, 'reject' throws, 'hang' never settles. */
    fetch: 'answer' as 'answer' | 'reject' | 'hang',
    requests: [] as { url: string; init: any }[],
    writes: [] as [string, string][],
  }
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('session.authorize', () => ({ value: state.handle }))
  on('fs.write', ($, e) => (state.writes.push([e.path, e.text]), { value: undefined }))
  on('http.fetch', ($, e) => {
    state.requests.push({ url: e.url, init: e.init })
    if (state.fetch === 'reject') throw new Error('network down')
    if (state.fetch === 'hang') return new Promise<never>(() => {})
    const ok = state.status >= 200 && state.status < 300
    return { value: { status: state.status, ok, headers: {}, text: state.text } }
  })
  /** One measure, then the clock run so the refresh it scheduled happens. */
  const measure = async ($: any) => {
    const result = await $.session.measure(MEASURE)
    await clock.advance(1)
    return result
  }
  return { clock, state, measure }
}

/** The lines written, the text split on its line ends. */
const lines = (text: string) => text.split('\n').filter((l, i, all) => i < all.length - 1 || l !== '')

// ── 1 ──────────────────────────────────────────────────────────────────────────
test('a measure writes one label, percent, reset line per weekly_scoped limit, in order, other kinds left out', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([
    scoped('Fable', 12, '2026-10-17T00:00:00Z'),
    { kind: 'weekly_all', percent: 30, resets_at: '2026-10-17T00:00:00Z' },
    scoped('Opus', 40, '2026-10-20T12:30:00Z'),
  ])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(isPath(state.writes[0][0], FILE)).toBe(true)
  expect(state.writes[0][1]).toBe(`Fable\t12\t${RESET}\nOpus\t40\t1792499400\n`)
})

// ── 2 ──────────────────────────────────────────────────────────────────────────
test('the request is a GET of the usage endpoint, the handle in auth, the beta header set, the handle nowhere else', async ($, on) => {
  const { state, measure } = harness(on)
  await measure($)
  expect(state.requests.length).toBe(1)
  const { url, init } = state.requests[0]
  expect(url).toBe(URL)
  expect(String(init?.method ?? 'GET').toUpperCase()).toBe('GET')
  const auth = init?.auth
  expect(auth === HANDLE || auth?.handle === HANDLE).toBe(true)
  const headers: Record<string, string> = Object.fromEntries(
    Object.entries(init?.headers ?? {}).map(([k, v]) => [k.toLowerCase(), String(v)]),
  )
  expect(headers['anthropic-beta']).toBe('oauth-2025-04-20')
  expect('authorization' in headers).toBe(false)
  expect(url.includes(HANDLE)).toBe(false)
  expect(JSON.stringify(init?.headers ?? {}).includes(HANDLE)).toBe(false)
})

// ── 3 ──────────────────────────────────────────────────────────────────────────
test('the file holds labels and digits only, never the handle, control characters dropped from a label', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([scoped('Fable\x1b[31m\tx', 12, '2026-10-17T00:00:00Z'), scoped(`Op\r\nus\x07${'\u0085'}`, 40, RESET)])
  await measure($)
  expect(state.writes.length).toBe(1)
  const text = state.writes[0][1]
  expect(/^([^\p{Cc}]+\t\d+\t\d+\n)*$/u.test(text)).toBe(true)
  expect(text.includes(HANDLE)).toBe(false)
  // Every control character goes (ESC, tab, CR, LF, BEL, NEL), the printable rest stays.
  expect(lines(text)).toEqual([`Fable[31mx\t12\t${RESET}`, `Opus\t40\t${RESET}`])
})

// ── 4 ──────────────────────────────────────────────────────────────────────────
test('a refresh with the same values asks again but writes nothing, a changed value writes again', async ($, on) => {
  const { state, measure } = harness(on)
  await measure($)
  expect(state.writes.length).toBe(1)
  await measure($)
  expect(state.requests.length).toBe(2)
  expect(state.writes.length).toBe(1)
  state.text = body([scoped('Fable', 13, '2026-10-17T00:00:00Z')])
  await measure($)
  expect(state.requests.length).toBe(3)
  expect(state.writes.length).toBe(2)
  expect(state.writes[1][1]).toBe(`Fable\t13\t${RESET}\n`)
})

// ── 5 ──────────────────────────────────────────────────────────────────────────
test('a body with no weekly_scoped limit writes an empty file', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([{ kind: 'weekly_all', percent: 30, resets_at: RESET }])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(isPath(state.writes[0][0], FILE)).toBe(true)
  expect(state.writes[0][1]).toBe('')
})

test('a body that is not JSON, or has no limits, writes nothing', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = '<html>502 Bad Gateway</html>'
  await measure($)
  state.text = JSON.stringify({ five_hour: { utilization: 10 }, seven_day: { utilization: 30 } })
  await measure($)
  expect(state.requests.length).toBe(2)
  expect(state.writes).toEqual([])
})

// ── 6 ──────────────────────────────────────────────────────────────────────────
// Each failure leaves the mod working: the next refresh, answered well, writes the file.
async function recovers($: any, h: ReturnType<typeof harness>) {
  h.state.handle = { handle: HANDLE, kind: 'bearer' }
  h.state.status = 200
  h.state.fetch = 'answer'
  h.state.text = body([scoped('Fable', 12, RESET)])
  expect(await h.measure($)).toMatchObject({ changed: ['rateLimits'] })
  expect(h.state.writes.length).toBe(1)
  expect(h.state.writes[0][1]).toBe(`Fable\t12\t${RESET}\n`)
}

test('a 500 response writes nothing, throws nothing, and the measure still answers', async ($, on) => {
  const h = harness(on)
  h.state.status = 500
  h.state.text = body([scoped('Fable', 12, RESET)])
  expect(await h.measure($)).toMatchObject({ changed: ['rateLimits'] })
  expect(h.state.requests.length).toBe(1)
  expect(h.state.writes).toEqual([])
  await recovers($, h)
})

test('a fetch that rejects writes nothing, throws nothing, and the measure still answers', async ($, on) => {
  const h = harness(on)
  h.state.fetch = 'reject'
  expect(await h.measure($)).toMatchObject({ changed: ['rateLimits'] })
  expect(h.state.requests.length).toBe(1)
  expect(h.state.writes).toEqual([])
  await recovers($, h)
})

test('no handle from authorize writes nothing, throws nothing, and the measure still answers', async ($, on) => {
  const h = harness(on)
  h.state.handle = null
  expect(await h.measure($)).toMatchObject({ changed: ['rateLimits'] })
  expect(h.state.writes).toEqual([])
  await recovers($, h)
})

test('an api-key handle writes nothing, throws nothing, and the measure still answers', async ($, on) => {
  const h = harness(on)
  h.state.handle = { handle: 'sk-ant-api-key', kind: 'api-key' }
  expect(await h.measure($)).toMatchObject({ changed: ['rateLimits'] })
  expect(h.state.writes).toEqual([])
  await recovers($, h)
})

// ── 7 ──────────────────────────────────────────────────────────────────────────
test('a measure answers at once while the fetch never resolves', async ($, on) => {
  const { clock, state } = harness(on)
  state.fetch = 'hang'
  expect(await $.session.measure(MEASURE)).toMatchObject({ changed: ['rateLimits'] })
  await clock.advance(1)
  // The refresh has asked and is still waiting on its answer; a measure meanwhile still answers.
  expect(state.requests.length).toBe(1)
  expect(await $.session.measure(MEASURE)).toMatchObject({ changed: ['rateLimits'] })
  expect(state.writes).toEqual([])
})

// ── 8 ──────────────────────────────────────────────────────────────────────────
test('the file goes under CLAUDE_CONFIG_DIR when it is set', async ($, on) => {
  const { state, measure } = harness(on, { CLAUDE_CONFIG_DIR: CONFIG_DIR, HOME: '/home/me', USERPROFILE: '/users/me' })
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(isPath(state.writes[0][0], FILE)).toBe(true)
})

test('the file goes under HOME/.claude without CLAUDE_CONFIG_DIR', async ($, on) => {
  const { state, measure } = harness(on, { HOME: '/home/me', USERPROFILE: '/users/me' })
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(isPath(state.writes[0][0], '/home/me/.claude/.usage-scoped')).toBe(true)
})

test('the file goes under USERPROFILE/.claude without CLAUDE_CONFIG_DIR or HOME', async ($, on) => {
  const { state, measure } = harness(on, { USERPROFILE: 'C:\\Users\\me' })
  await measure($)
  expect(state.writes.length).toBe(1)
  // Elsewhere than Windows the engine reads `C:\Users\…` as a relative path, and no path
  // it hands back equals the one expected: the path is checked on a Windows host alone.
  if (!/^[A-Za-z]:\\/.test(state.writes[0][0])) {
    console.log('  not a Windows host: the USERPROFILE path is not checked here')
    return
  }
  expect(isPath(state.writes[0][0], 'C:/Users/me/.claude/.usage-scoped')).toBe(true)
})

// ── 9 ──────────────────────────────────────────────────────────────────────────
test('a reset given as an ISO date, epoch milliseconds or epoch seconds lands as the same epoch seconds, a missing one as 0', async ($, on) => {
  const { state, measure } = harness(on)
  const missing = scoped('D', 5, undefined)
  delete missing.resets_at
  state.text = body([
    scoped('A', 5, '2026-10-17T00:00:00Z'),
    scoped('B', 5, RESET * 1000),
    scoped('C', 5, RESET),
    missing,
  ])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(lines(state.writes[0][1])).toEqual([`A\t5\t${RESET}`, `B\t5\t${RESET}`, `C\t5\t${RESET}`, 'D\t5\t0'])
})

// ── 10 ─────────────────────────────────────────────────────────────────────────
test('a percent is rounded to the nearest whole number and capped at 100', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([scoped('A', 23.5, RESET), scoped('B', 140, RESET)])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(lines(state.writes[0][1])).toEqual([`A\t24\t${RESET}`, `B\t100\t${RESET}`])
})

// ── Plan conventions the numbered list does not name ───────────────────────────
test('a missing percent lands as 0 and a negative one is raised to 0', async ($, on) => {
  const { state, measure } = harness(on)
  const missing = scoped('A', undefined, RESET)
  delete missing.percent
  state.text = body([missing, scoped('B', -7, RESET)])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(lines(state.writes[0][1])).toEqual([`A\t0\t${RESET}`, `B\t0\t${RESET}`])
})

test('a reset that is an unparsable string or neither a string nor a number lands as 0', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([scoped('A', 5, 'not a date'), scoped('B', 5, { at: RESET }), scoped('C', 5, null)])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(lines(state.writes[0][1])).toEqual(['A\t5\t0', 'B\t5\t0', 'C\t5\t0'])
})

test('the label falls back to scope.surface, and a limit with no label, or one empty once cleaned, is skipped', async ($, on) => {
  const { state, measure } = harness(on)
  state.text = body([
    { kind: 'weekly_scoped', percent: 7, resets_at: RESET, scope: { surface: 'claude_code' } },
    { kind: 'weekly_scoped', percent: 8, resets_at: RESET, scope: {} },
    { kind: 'weekly_scoped', percent: 9, resets_at: RESET },
    scoped('\x1b\t\r\n', 10, RESET),
    { kind: 'weekly_scoped', percent: 11, resets_at: RESET, scope: { model: { display_name: 'Fable' }, surface: 'claude_code' } },
  ])
  await measure($)
  expect(state.writes.length).toBe(1)
  expect(lines(state.writes[0][1])).toEqual([`claude_code\t7\t${RESET}`, `Fable\t11\t${RESET}`])
})
