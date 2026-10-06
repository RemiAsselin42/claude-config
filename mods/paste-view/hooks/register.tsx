// Vendored from github.com/Amorfx/claude-paste-view at a71ba10 (MIT, see ../LICENSE)
// on 2026-10-06: claude-config ships the mod itself instead of installing it from
// a third-party marketplace at whatever commit that holds on install day.
// Local changes. Windows, which upstream does not cover: the image cache is looked
// for under %TEMP%\claude, the clipboard is read and an image opened through
// PowerShell, and CRLF line ends are folded to LF. On every platform: a clipboard
// read that fails is not remembered, and a session with nobody at the prompt is not
// polled. On Windows where no picture is drawn, an image shows as a mosaic of half
// blocks (inline.ts, local). A text is its label alone, its size and no excerpt. The
// hint names the click under the fullscreen layout alone. The pane of a text never
// gets the keyboard when it opens, so the band carries the keys that scroll and close
// it. tags.ts and thumbnails.ts are upstream's, untouched.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { PastedImage, PastedText } from '../types'
import { MOSAIC_COLUMNS, MOSAIC_COMMAND, MOSAIC_ROWS, mosaicCells, parseMosaic } from './inline'
import { charCount, draftTags, lineBreaks, matchesTag } from './tags'
import type { TextTag } from './tags'
import { drawsImages, pngDimensions, thumbnailBoxes } from './thumbnails'
import type { Dimensions } from './thumbnails'

const PANE = 'paste-view'
// A paste raises no prompt.edit, and a collapsed text paste reaches no hook before it is
// sent: the draft is watched on a timer, and a new text tag is matched against the
// clipboard the moment it appears.
const POLL_MS = 200

const images = atom({ plugin: 'paste-view', key: 'images' } as const, [] as PastedImage[])
const texts = atom({ plugin: 'paste-view', key: 'texts' } as const, [] as PastedText[])
const viewing = atom({ plugin: 'paste-view', key: 'viewing' } as const, null as number | null)

const POWERSHELL = ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command'] as const
// The text goes out as UTF-8 bytes: written as text it would come back in the console's
// code page, accents lost, with a newline added.
const WINDOWS_CLIPBOARD = [
  ...POWERSHELL,
  '$t = Get-Clipboard -Raw; if ($t) { $b = [Text.Encoding]::UTF8.GetBytes($t); [Console]::OpenStandardOutput().Write($b, 0, $b.Length) }',
] as const

// Tried in order on first use; the first that runs is kept.
const CLIPBOARD_COMMANDS: readonly (readonly string[])[] = [
  ['pbpaste'],
  ['wl-paste', '--no-newline'],
  ['xclip', '-selection', 'clipboard', '-o'],
]

let cwd = ''
let hasGraphics = false
let clipboardCommand: readonly string[] | undefined
let viewerCommand: string | undefined
let imagesDir: { session: string; path: string } | undefined
const dimensions = new Map<string, Dimensions | null>()
// The mosaic of each image, by path, scaled once.
const grids = new Map<string, string[] | null>()
// The cells a mosaic may take: the band's room when it was last drawn.
let room = { columns: MOSAIC_COLUMNS, rows: MOSAIC_ROWS }
// Pasted texts by tag number, each read once, when its tag first shows up.
const pastes = new Map<number, string | null>()
// What the draft held at the last refresh; undefined forces the next one to redo the work.
let lastSignature: string | undefined
// What was last written to state, so a refresh that finds the same pastes doesn't redraw.
let written: string | undefined
let isRefreshing = false

// Windows has no `id`, `uname` or `open`; it always sets OS.
const isWindows = async ($: EngineInterface) => (await $.env.get('OS')) === 'Windows_NT'

async function tmpRoot($: EngineInterface): Promise<string> {
  const configured = await $.env.get('CLAUDE_CODE_TMPDIR')
  if (configured !== undefined) return configured
  // There the folder is %TEMP%\claude, with no user id in its name.
  if (await isWindows($)) return `${await $.env.get('TEMP')}/claude`
  const { stdout } = await $.process.run(['id', '-u'])
  return `/tmp/claude-${stdout.trim()}`
}

// Claude Code keeps a session's pasted images in <tmp>/<project>/<session>/images/<n>.<ext>,
// <project> being the working directory with every character but letters and digits
// turned into '-'. That folder is tried first; the session id alone finds it otherwise.
async function findImagesDir($: EngineInterface): Promise<string | undefined> {
  const session = await $.session.id()
  if (imagesDir?.session === session) return imagesDir.path
  const root = await tmpRoot($)
  const projects = await $.fs.list(root).catch(() => [])
  const candidates = [
    cwd.replace(/[^a-zA-Z0-9]/g, '-'),
    ...projects.filter(entry => entry.kind === 'dir').map(entry => entry.name),
  ]
  for (const project of candidates) {
    const path = `${root}/${project}/${session}/images`
    if (await $.fs.exists(path)) {
      imagesDir = { session, path }
      return path
    }
  }
  return undefined
}

// An image is cached in the format it was pasted in: <n>.png for a screenshot, but
// <n>.jpg or <n>.webp for others.
async function findImage($: EngineInterface, dir: string, n: number): Promise<string | undefined> {
  const png = `${dir}/${n}.png`
  if (await $.fs.exists(png)) return png
  const entries = await $.fs.list(dir).catch(() => [])
  const other = entries.find(entry => entry.kind === 'file' && entry.name.startsWith(`${n}.`))
  return other === undefined ? undefined : `${dir}/${other.name}`
}

const isPng = (path: string) => path.endsWith('.png')

// Where the terminal draws no pictures, the band draws the image itself, as half blocks.
// Windows only: PowerShell's System.Drawing does the scaling.
async function mosaicOf($: EngineInterface, path: string): Promise<string[] | null> {
  if (hasGraphics || !(await isWindows($))) return null
  if (!grids.has(path)) {
    const env = { PASTE_VIEW_PATH: path, PASTE_VIEW_COLUMNS: String(room.columns), PASTE_VIEW_ROWS: String(room.rows) }
    const ran = await $.process.run([...POWERSHELL, MOSAIC_COMMAND], { env, timeoutMs: 5000 }).catch(() => undefined)
    grids.set(path, ran?.exitCode === 0 ? parseMosaic(ran.stdout) : null)
  }
  return grids.get(path) ?? null
}

async function describeImage($: EngineInterface, dir: string | undefined, n: number): Promise<PastedImage> {
  const path = dir === undefined ? undefined : await findImage($, dir, n)
  if (path === undefined) return { n, path: null, size: null, pixels: null }
  const pixels = await mosaicOf($, path)
  if (!isPng(path)) return { n, path, size: null, pixels }
  if (!dimensions.has(path)) {
    // A file past the read cap is still drawn, in a default shape.
    const head = await $.fs.read(path, { as: 'bytes' }).catch(() => undefined)
    dimensions.set(path, head === undefined ? null : pngDimensions(head.base64))
  }
  return { n, path, size: dimensions.get(path) ?? null, pixels }
}

async function readClipboard($: EngineInterface): Promise<string | null> {
  const onWindows = await isWindows($)
  // Windows is asked through PowerShell alone: a pbpaste or xclip left on its PATH by
  // MSYS2 or Cygwin must not be the one that answers.
  const firstUse = onWindows ? [WINDOWS_CLIPBOARD] : CLIPBOARD_COMMANDS
  // PowerShell starts in 0.3 to 0.4s once warm (measured 2026-10); a cold start can pass a second.
  const timeoutMs = onWindows ? 5000 : 1000
  for (const argv of clipboardCommand === undefined ? firstUse : [clipboardCommand]) {
    // pbpaste decodes by the locale, which a bare child process may lack.
    const ran = await $.process.run(argv, { env: { LANG: 'en_US.UTF-8' }, timeoutMs }).catch(() => undefined)
    if (ran?.exitCode === 0 && !ran.isStdoutTruncated) {
      clipboardCommand = argv
      // The Windows clipboard ends lines with CRLF: a carriage return must not reach the pane.
      return ran.stdout.replace(/\r\n?/g, '\n')
    }
  }
  // A read that failed is that paste's alone (a timeout, a clipboard past the read cap):
  // nothing is remembered of it, and the next paste is read again.
  return null
}

async function capturePastes($: EngineInterface, tags: readonly TextTag[]) {
  for (const n of pastes.keys()) if (!tags.some(tag => tag.n === n)) pastes.delete(n)
  const fresh = tags.filter(tag => !pastes.has(tag.n))
  if (fresh.length === 0) return
  // One clipboard can only stand for one paste: tags arriving together (a draft brought
  // back from history) are left without a preview rather than guessed.
  const clipboard = fresh.length === 1 ? await readClipboard($) : null
  for (const tag of fresh) pastes.set(tag.n, clipboard !== null && matchesTag(clipboard, tag.lines) ? clipboard : null)
}

async function refresh($: EngineInterface, draft: string) {
  const tags = draftTags(draft)
  await capturePastes($, tags.texts)

  const signature = JSON.stringify([tags.images, tags.texts.map(tag => tag.n)])
  if (signature === lastSignature) return

  const dir = tags.images.length > 0 ? await findImagesDir($) : undefined
  const imageList = await Promise.all(tags.images.map(n => describeImage($, dir, n)))
  // An image whose file hasn't landed yet is looked for again on the next poll.
  lastSignature = imageList.some(image => image.path === null) ? undefined : signature

  const textList = tags.texts.map(tag => ({ ...tag, text: pastes.get(tag.n) ?? null }))
  // Each write redraws the band: an image still missing must not redraw it on every poll.
  const json = JSON.stringify([imageList, textList])
  if (json !== written) {
    await update($, images, () => imageList)
    await update($, texts, () => textList)
    written = json
  }

  const shown = await read($, viewing)
  if (shown !== null && !tags.texts.some(tag => tag.n === shown)) await closePane($)
}

async function poll($: EngineInterface) {
  if (isRefreshing) return
  isRefreshing = true
  try {
    await refresh($, (await $.prompt.read()).text)
  } finally {
    isRefreshing = false
  }
}

// Without pictures in the terminal, an image opens in the system's own viewer.
async function openImage($: EngineInterface, path: string) {
  viewerCommand ??= (await isWindows($))
    ? 'Invoke-Item'
    : (await $.process.run(['uname'])).stdout.trim() === 'Darwin'
      ? 'open'
      : 'xdg-open'
  // Invoke-Item is PowerShell's. The path travels in the environment, never in the command:
  // PowerShell ends a quoted string at ' and at the typographic ‘ ’ ‚ ‛ alike, and runs
  // what follows (seen with a path holding ’, 2026-10).
  const ran = await (viewerCommand === 'Invoke-Item'
    ? $.process.run([...POWERSHELL, 'Invoke-Item -LiteralPath $env:PASTE_VIEW_PATH'], { env: { PASTE_VIEW_PATH: path }, timeoutMs: 5000 })
    : $.process.run([viewerCommand, path], { timeoutMs: 5000 })
  ).catch(() => undefined)
  if (ran?.exitCode !== 0) $.ui.toast(`paste-view: couldn't open the image with ${viewerCommand}`)
}

// The pane draws a text this many lines a part, each part a place the band can scroll to.
const PART_LINES = 10
// The part the band last brought to the top of the pane.
// ponytail: counts its own moves, so a wheel scroll in between is not seen; read the
// window's offset from the pane's props if that ever matters.
let panePart = 0

const paneParts = (text: string) => {
  const lines = text.split(/\r\n|\r|\n/)
  return Array.from({ length: Math.ceil(lines.length / PART_LINES) }, (_, i) => lines.slice(i * PART_LINES, (i + 1) * PART_LINES).join('\n'))
}

async function openPane($: EngineInterface, paste: PastedText) {
  panePart = 0
  await update($, viewing, () => paste.n)
  // `focus` is a request the engine refuses while the prompt holds text or the band holds
  // the keyboard, which is every time here: the pane opens without the keys, the arrows
  // never reach it, and the band's own keys move it instead (scrollPane).
  await $.ui.open({ id: PANE, title: `Pasted text #${paste.n}`, focus: true, closeOnEscape: true })
}

async function scrollPane($: EngineInterface, by: -1 | 1) {
  const shown = await read($, viewing)
  const paste = (await read($, texts)).find(one => one.n === shown)
  if (paste?.text == null) return
  panePart = Math.max(0, Math.min(paneParts(paste.text).length - 1, panePart + by))
  // A move the engine refuses or cannot make leaves the pane where it is, no more.
  await $.ui.scroll({ in: PANE, to: { key: `part-${panePart}` }, block: 'start' }).catch(() => undefined)
}

async function closePane($: EngineInterface) {
  await update($, viewing, () => null)
  if ((await $.ui.panes()).some(pane => pane.id === PANE)) await $.ui.close({ id: PANE })
}

/** Lines a paste spans on screen, a trailing newline not counted. */
const shownLines = (paste: PastedText) =>
  paste.text === null ? (paste.lines ?? 0) + 1 : lineBreaks(paste.text.trimEnd()) + 1

const imageLabel = (image: PastedImage, path: string) => {
  if (image.size !== null) return `#${image.n} · image ${image.size.width}×${image.size.height}`
  return isPng(path) ? `#${image.n} · image` : `#${image.n} · image · ${path.slice(path.lastIndexOf('.') + 1)}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // A `-p` run or the SDK has no prompt box: nothing to watch, so no timer.
    if (!e.isInteractive) return next(e)
    cwd = e.cwd
    hasGraphics = drawsImages({
      term: await $.env.get('TERM'),
      termProgram: await $.env.get('TERM_PROGRAM'),
      kittyWindowId: await $.env.get('KITTY_WINDOW_ID'),
      forceImages: await $.env.get('CLAUDE_CODE_FORCE_TERMINAL_IMAGES'),
      sessionKind: await $.env.get('CLAUDE_CODE_SESSION_KIND'),
      multiplexer: (await $.env.get('TMUX')) ?? (await $.env.get('STY')),
    })
    // A reload keeps the state: the texts already read stay matched to their tags.
    for (const paste of await read($, texts)) pastes.set(paste.n, paste.text)
    $.clock.every(POLL_MS, () => poll($))
    return next(e)
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    await update($, viewing, () => null)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || e.props.hasSurvey) return next(e)
    // Kept for the next image to be scaled: four rows are left to the lines below it.
    room = {
      columns: Math.min(MOSAIC_COLUMNS, e.props.bodyColumns),
      rows: Math.max(2, Math.min(MOSAIC_ROWS, e.props.maxRows - 4)),
    }
    const imageList = await read($, images)
    const textList = await read($, texts)
    if (imageList.length === 0 && textList.length === 0) return next(e)
    // The text open in the pane, if any: the band then carries the keys that move it.
    const shown = await read($, viewing)

    const { Box, Button, Image, Text } = $.ui.resolve(e)
    const width = e.props.bodyColumns
    // The Image element draws a PNG file only: any other format is a line that opens it.
    const pictures = hasGraphics ? imageList.filter(image => image.path !== null && isPng(image.path)) : []
    const imageLines = imageList.filter(image => !pictures.includes(image))
    const openable = imageLines.filter(image => image.path !== null)
    // One row per line below the thumbnails, plus the hint and the pane's keys while it
    // is open; the thumbnails get the rest.
    const lineRows = imageLines.length + textList.length + 1 + (shown === null ? 0 : 1)
    const boxes = thumbnailBoxes(pictures.map(image => image.size), e.props.maxRows - lineRows, width)
    // Number keys run down the lines that open something, images first.
    const hotkey = (i: number) => (i >= 0 && i < 9 ? { hotkey: String(i + 1) } : {})
    // Where no picture is drawn, each image scaled to a mosaic sits above the lines.
    const mosaics = imageLines.flatMap(image => (image.pixels == null ? [] : [{ n: image.n, rows: mosaicCells(image.pixels) }]))
    const below = await next(e)

    return (
      <Box flexDirection="column">
        {pictures.length > 0 && (
          <Box flexDirection="row" columnGap={1} alignItems="flex-end">
            {pictures.map((image, i) => (
              <Box flexDirection="column" alignItems="center">
                <Box borderStyle="round" borderDimColor>
                  <Image
                    key={`picture-${image.n}`}
                    source={{ file: image.path ?? '', format: 'png' }}
                    columns={boxes[i]?.columns ?? 4}
                    rows={boxes[i]?.rows ?? 1}
                    alt={`[Image #${image.n}]`}
                  />
                </Box>
                <Text dimColor>#{image.n}</Text>
              </Box>
            ))}
          </Box>
        )}
        {mosaics.length > 0 && (
          <Box flexDirection="row" columnGap={1} alignItems="flex-end">
            {mosaics.map(mosaic => (
              <Box flexDirection="column" alignItems="center">
                {mosaic.rows.map(runs => (
                  <Box flexDirection="row">
                    {runs.map(run => (
                      <Text color={run.top} backgroundColor={run.bottom}>
                        {'▀'.repeat(run.cells)}
                      </Text>
                    ))}
                  </Box>
                ))}
                <Text dimColor>#{mosaic.n}</Text>
              </Box>
            ))}
          </Box>
        )}
        {imageLines.map(image => {
          const path = image.path
          if (path === null) {
            return <Text dimColor wrap="truncate">{`#${image.n} · image · no preview`}</Text>
          }
          return (
            <Button
              key={`image-${image.n}`}
              plain
              {...hotkey(openable.indexOf(image))}
              label={`${imageLabel(image, path)} — open`}
              onPress={() => openImage($, path)}
            />
          )
        })}
        {textList.map((paste, i) => {
          const head = `#${paste.n} · ${shownLines(paste)} lines`
          if (paste.text === null) {
            return <Text dimColor wrap="truncate">{`${head} · no preview (clipboard changed)`}</Text>
          }
          // The label alone, its size and nothing of the text: its first lines under it, and
          // upstream's first line after it, were seen on screen and taken out (Rémi, 2026-10-06).
          return (
            <Button
              key={`text-${paste.n}`}
              plain
              {...hotkey(openable.length + i)}
              label={`${head} · ${charCount(paste.text.length)}`}
              onPress={() => openPane($, paste)}
            />
          )
        })}
        {(openable.length > 0 || textList.some(paste => paste.text !== null)) && (
          // A click reaches a line under the fullscreen layout alone: on the main screen
          // naming it sent people clicking at nothing.
          <Text dimColor wrap="truncate">
            {e.viewport?.isFullscreen === true
              ? 'to open one: click its line, or press Ctrl+X, then Tab, then its number'
              : 'to open one: press Ctrl+X, then Tab, then its number'}
          </Text>
        )}
        {shown !== null && (
          <Box flexDirection="row" columnGap={2}>
            <Text dimColor>{`pasted text #${shown}:`}</Text>
            <Button key="pane-down" plain hotkey="j" label="down" onPress={() => scrollPane($, 1)} />
            <Button key="pane-up" plain hotkey="k" label="up" onPress={() => scrollPane($, -1)} />
            <Button key="pane-close" plain hotkey="x" label="close" onPress={() => closePane($)} />
          </Box>
        )}
        {below}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const shown = await read($, viewing)
    const paste = (await read($, texts)).find(one => one.n === shown)
    if (paste?.text == null) return <Text dimColor>This paste is no longer in the prompt.</Text>

    // The arrows and Escape are the pane's only while it holds the keyboard; otherwise
    // the keys are the band's.
    const keys = e.props.isFocused ? '↑↓ scroll · esc close' : 'j k scroll · x close'
    return (
      <Box flexDirection="column">
        <Text dimColor wrap="truncate">{`${shownLines(paste)} lines · ${charCount(paste.text.length)} · ${keys}`}</Text>
        {paneParts(paste.text).map((part, i) => (
          <Box key={`part-${i}`}>
            <Text>{part}</Text>
          </Box>
        ))}
      </Box>
    )
  })
}
