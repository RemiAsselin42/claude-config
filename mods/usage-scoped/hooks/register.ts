import type { Register } from 'claude-code'

// usage-scoped: the per-model weekly rate-limit windows, which the statusline
// payload does not carry (it has five_hour and seven_day alone). After each
// session.measure, outside its dispatch, the OAuth usage endpoint is read with
// the session's credential held by the engine ($.session.authorize() answers an
// opaque handle, $.http.fetch spends it; the secret never reaches this module),
// and its `limits` of kind weekly_scoped are written to <config dir>/.usage-scoped
// as one "label<TAB>percent<TAB>resets_at (epoch seconds)" line per window, only
// when the text changed. scripts/statusline.sh renders one "Week <label>" segment
// per line. Anything wrong (no handle, an API key, a refused or failed request, a
// body that is not JSON) writes nothing and raises nothing.
//
//   claude plugin validate mods/usage-scoped
//   claude plugin test mods/usage-scoped

const URL = 'https://api.anthropic.com/api/oauth/usage'

type Limit = { kind?: unknown; percent?: unknown; resets_at?: unknown; scope?: { model?: { display_name?: unknown }; surface?: unknown } }

/** The window's name, every control character removed; '' when it has none. */
const label = (l: Limit) => String(l.scope?.model?.display_name ?? l.scope?.surface ?? '').replace(/\p{Cc}/gu, '')
const percent = (v: unknown) => Math.min(100, Math.max(0, Math.round(Number(v) || 0)))
/** Epoch seconds from an ISO 8601 string, epoch milliseconds or epoch seconds; 0 otherwise. */
const reset = (v: unknown) => {
  const ms = typeof v === 'string' ? Date.parse(v) : typeof v === 'number' ? (v > 1e11 ? v : v * 1000) : NaN
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : 0
}

export const register: Register = on => {
  let last: string | undefined

  on('session.measure', ($, e, next) => {
    $.clock.after(0, async () => {
      try {
        const auth = await $.session.authorize()
        if (auth?.kind !== 'bearer') return
        const res = await $.http.fetch(URL, { auth: auth.handle, headers: { 'anthropic-beta': 'oauth-2025-04-20' } })
        if (!res.ok) return
        const limits: unknown = JSON.parse(res.text)?.limits
        if (!Array.isArray(limits)) return
        const text = (limits as Limit[])
          .filter(l => l?.kind === 'weekly_scoped' && label(l) !== '')
          .map(l => `${label(l)}\t${percent(l.percent)}\t${reset(l.resets_at)}\n`)
          .join('')
        if (text === last) return
        const dir = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? `${(await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE'))}/.claude`
        await $.fs.write(`${dir}/.usage-scoped`, text)
        last = text
      } catch {
        // A failed refresh leaves the last file as it is; the next measure tries again.
      }
    })
    return next(e)
  })
}
