import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { mosaicCells, parseMosaic, previewLines } from '../hooks/inline'
import { charCount, draftTags, firstLine, matchesTag } from '../hooks/tags'
import { drawsImages, pngDimensions, thumbnailBoxes } from '../hooks/thumbnails'

const LOREM = 'Lorem ipsum dolor sit amet,\nconsectetur adipiscing elit,\nsed do eiusmod tempor.'

test('tags come from the draft, each once, in the order they first appear', () => {
  expect(draftTags('a [Image #4] [Pasted text #2 +9 lines] b [Image #1] [Pasted text #3] [Image #4] [Pasted text #2 +9 lines]')).toEqual({
    images: [4, 1],
    texts: [
      { n: 2, lines: 9 },
      { n: 3, lines: null },
    ],
  })
  expect(draftTags('[Image 1] [image #3] [Pasted text 2 +9 lines] [pasted text #4] #5')).toEqual({ images: [], texts: [] })
})

test('a clipboard text matches a tag only when the line count agrees', () => {
  expect(matchesTag(LOREM, 2)).toBe(true)
  expect(matchesTag(`${LOREM}\n`, 2)).toBe(true) // a trailing newline the terminal dropped
  expect(matchesTag(LOREM.replace(/\n/g, '\r\n'), 2)).toBe(true)
  expect(matchesTag(LOREM, 5)).toBe(false)
  expect(matchesTag('one long line', null)).toBe(true)
  expect(matchesTag(LOREM, null)).toBe(false)
  expect(matchesTag('  \n ', 1)).toBe(false)
})

test('the preview line is the first non-blank line, cut to fit', () => {
  expect(firstLine('\n\n  Hello   world  \nnext', 40)).toBe('Hello world')
  expect(firstLine('abcdefghij', 5)).toBe('abcd…')
  expect(firstLine('abc', 0)).toBe('')
})

test('character counts read short', () => {
  expect(charCount(840)).toBe('840 chars')
  expect(charCount(2349)).toBe('2.3k chars')
  expect(charCount(3000)).toBe('3k chars')
  expect(charCount(1_250_000)).toBe('1.3M chars')
})

test('pictures are drawn only where the terminal speaks the kitty graphics protocol', () => {
  expect(drawsImages({ term: 'xterm-kitty' })).toBe(true)
  expect(drawsImages({ term: 'xterm-256color', kittyWindowId: '1' })).toBe(true)
  expect(drawsImages({ term: 'xterm-ghostty', termProgram: 'ghostty' })).toBe(true)
  expect(drawsImages({ term: 'xterm-256color', termProgram: 'Orca' })).toBe(false)
  expect(drawsImages({ term: 'xterm-256color', termProgram: 'Apple_Terminal' })).toBe(false)
  expect(drawsImages({})).toBe(false)
  // Claude Code turns pictures off inside tmux or screen and in background sessions...
  expect(drawsImages({ termProgram: 'ghostty', multiplexer: '/tmp/tmux-501/default,1,0' })).toBe(false)
  expect(drawsImages({ termProgram: 'ghostty', sessionKind: 'bg' })).toBe(false)
  // ...unless told to draw them anyway.
  expect(drawsImages({ termProgram: 'ghostty', multiplexer: '1', forceImages: '1' })).toBe(true)
})

const BAND = {
  plugin: 'paste-view',
  component: 'AbovePrompt',
  requestId: 'above-prompt',
  viewport: { columns: 120, rows: 40 },
  props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 120, scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

const PANE = {
  plugin: 'paste-view',
  component: 'Pane',
  requestId: 'paste-view',
  viewport: { columns: 120, rows: 40 },
  props: { title: 'Pasted text #2', isFocused: true, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

/** The first bytes of a PNG of the given size, base64-encoded: signature, IHDR length and tag, width, height. */
function pngStart(width: number, height: number): string {
  const be32 = (value: number) => [value >>> 24, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
  const bytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...be32(13), 0x49, 0x48, 0x44, 0x52, ...be32(width), ...be32(height)]
  return btoa(String.fromCharCode(...bytes))
}

test('a PNG gives its size from its header; anything else gives none', () => {
  expect(pngDimensions(pngStart(1630, 632))).toEqual({ width: 1630, height: 632 })
  expect(pngDimensions(btoa('GIF89a, not a PNG at all, padded out'))).toBeNull()
  expect(pngDimensions(btoa('short'))).toBeNull()
})

test('thumbnails keep their proportions within the caps', () => {
  const square = { width: 400, height: 400 }
  // Square: six rows, twelve columns (cells are about twice as tall as wide).
  expect(thumbnailBoxes([square], 20, 120)).toEqual([{ columns: 12, rows: 6 }])
  // Panorama: held to 32 columns, with the rows it then needs.
  expect(thumbnailBoxes([{ width: 3000, height: 500 }], 20, 120)).toEqual([{ columns: 32, rows: 3 }])
  // Portrait: never under four columns.
  expect(thumbnailBoxes([{ width: 100, height: 2000 }], 20, 120)).toEqual([{ columns: 4, rows: 6 }])
  // Unknown size: a 3:2 shape.
  expect(thumbnailBoxes([null], 20, 120)).toEqual([{ columns: 18, rows: 6 }])
})

test('a row of thumbnails shrinks to the room it has', () => {
  const square = { width: 400, height: 400 }
  // Little height: the frame and label take three rows.
  expect(thumbnailBoxes([square], 6, 120)).toEqual([{ columns: 6, rows: 3 }])
  // Little width: three squares at six rows need 3 × 14 + 2 = 44 columns; 40 forces five.
  expect(thumbnailBoxes([square, square, square], 20, 40)).toEqual([
    { columns: 10, rows: 5 },
    { columns: 10, rows: 5 },
    { columns: 10, rows: 5 },
  ])
  // Never below one row, whatever the squeeze.
  expect(thumbnailBoxes([square, square, square, square], 2, 10).every(box => box.rows === 1)).toBe(true)
})

const IMAGES_DIR = '/tmp/claude-501/-work/sess-1/images'
// On Windows nothing sets CLAUDE_CODE_TMPDIR, and the cache is under %TEMP%\claude.
const WINDOWS_TEMP = 'C:\\Users\\me\\AppData\\Local\\Temp'
const WINDOWS_IMAGES_DIR = `${WINDOWS_TEMP}/claude/-work/sess-1/images`
const OPEN_COMMAND = 'Invoke-Item -LiteralPath $env:PASTE_VIEW_PATH'

// The engine hands a hook each path made absolute for the machine the tests run on: on
// Windows `/tmp/claude-501` arrives as `C:\tmp\claude-501`. Paths are compared whole, once
// the separators agree and the drive put in front of a path that had none is dropped.
function isPath(given: string, expected: string): boolean {
  const slashes = (path: string) => path.replace(/\\/g, '/')
  const hasDrive = /^[A-Za-z]:/.test(expected)
  return slashes(hasDrive ? given : given.replace(/^[A-Za-z]:/, '')) === slashes(expected)
}

/**
 * Whether the tests run on Windows, read off the first path the mod asked about. The
 * tests on Windows paths apply there alone: elsewhere the engine reads `C:\Users\…` as
 * a relative path, and no path it hands back equals the one expected. The kit has no
 * skip, and its sandbox neither `process` nor a `$.fs` for a test to ask with.
 */
function isWindowsHost(state: { asked: string[] }): boolean {
  const isWindows = /^[A-Za-z]:\\/.test(state.asked[0] ?? '')
  if (!isWindows) console.log('  not a Windows host: this test checks nothing here')
  return isWindows
}

function harness(on: On, env: Record<string, string> = {}, isWindows = false) {
  const clock = mock.clock(on)
  const imagesDir = isWindows ? WINDOWS_IMAGES_DIR : IMAGES_DIR
  mock.env(on, {
    ...(isWindows ? { OS: 'Windows_NT', TEMP: WINDOWS_TEMP } : { CLAUDE_CODE_TMPDIR: '/tmp/claude-501' }),
    TERM: 'xterm-256color',
    ...env,
  })
  // A Mac answers pbpaste, uname and open; Windows has PowerShell alone.
  const commands = isWindows ? ['powershell.exe'] : ['pbpaste', 'uname', 'open']
  const state = {
    draft: '',
    clipboard: '',
    /** While true the clipboard command fails, as on a timeout. */
    isClipboardDown: false,
    /** What the command that scales an image to a mosaic writes. */
    mosaic: '',
    /** Names of the files in the session's image cache. */
    images: ['1.png'],
    writes: 0,
    /** How many times the prompt box was read. */
    reads: 0,
    opened: [] as string[],
    closed: [] as string[],
    ran: [] as string[][],
    /** The variables the last command was run with. */
    env: {} as Record<string, string>,
    /** Every path asked about, as the engine handed it over. */
    asked: [] as string[],
  }
  const entry = (name: string, kind: 'file' | 'dir') => ({ name, kind, size: 0, mtimeMs: 0, isLink: false })
  on('session.id', () => ({ value: 'sess-1' }))
  on('fs.list', ($, e) => ({
    value: isPath(e.path, imagesDir) ? state.images.map(name => entry(name, 'file')) : [entry('-work', 'dir')],
  }))
  on('fs.exists', ($, e) => {
    state.asked.push(e.path)
    return { value: isPath(e.path, imagesDir) || state.images.some(name => isPath(e.path, `${imagesDir}/${name}`)) }
  })
  on('fs.read', () => ({ value: { base64: pngStart(800, 400) } }))
  on('state.set', ($, e, next) => (state.writes++, next(e)))
  on('session.start', () => ({ cwd: '/work' }))
  on('prompt.read', () => (state.reads++, { value: { text: state.draft, cursor: state.draft.length } }))
  on('process.run', ($, e) => {
    state.ran.push([...e.argv])
    state.env = { ...e.init?.env }
    const [command] = e.argv
    const isClipboard = command === 'pbpaste' || (command === 'powershell.exe' && e.argv.at(-1)?.includes('Get-Clipboard'))
    const isMosaic = command === 'powershell.exe' && e.argv.at(-1)?.includes('System.Drawing')
    const stdout = isClipboard ? state.clipboard : isMosaic ? state.mosaic : command === 'uname' ? 'Darwin\n' : ''
    const exitCode = commands.includes(command ?? '') && !(isClipboard && state.isClipboardDown) ? 0 : 1
    return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', ($, e) => (state.opened.push(e.id), { value: { isPlaced: true } }))
  on('ui.panes', () => ({ value: state.opened.map(id => ({ id, title: id, isShown: true, isFocused: true, isPlaced: true })) }))
  on('ui.close', ($, e) => (state.closed.push(e.id), (state.opened = state.opened.filter(id => id !== e.id)), { value: undefined }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['engine band'] }))
  return { clock, state }
}

test('a pasted text shows a preview, opens whole in a pane, and clears on send', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = LOREM
  state.draft = 'explain [Pasted text #2 +2 lines]'
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  // The label, then the text's own lines under it.
  expect((await band.find({ type: 'Button', key: 'text-2' }))?.props).toMatchObject({ label: '#2 · 3 lines · 79 chars' })
  expect(await band.find({ type: 'Text', text: '   consectetur adipiscing elit,' })).toBeDefined()
  await $.ui.press({ plugin: 'paste-view', key: 'text-2' })
  await band.unmount()
  expect(state.opened).toEqual(['paste-view'])

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ type: 'Text', text: 'sed do eiusmod tempor.' })).toBeDefined()
  await pane.unmount()

  // Sending the prompt empties the box: the row goes and the pane closes.
  state.draft = ''
  await clock.advance(200)
  expect(state.closed).toEqual(['paste-view'])
  const after = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await after.find({ type: 'Button' })).toBeUndefined()
  expect(await after.find({ type: 'Text', text: 'engine band' })).toBeDefined()
})

test('a paste whose clipboard no longer matches says so instead of guessing', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = 'something copied since'
  state.draft = '[Pasted text #1 +9 lines]'
  await clock.advance(200)
  // The clipboard catching up later doesn't change a verdict already made.
  state.clipboard = LOREM
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Button' })).toBeUndefined()
  expect(await band.find({ type: 'Text', text: '#1 · 10 lines · no preview (clipboard changed)' })).toBeDefined()
})

test('several tags appearing at once are not guessed from one clipboard', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = LOREM
  state.draft = '[Pasted text #1 +2 lines] [Pasted text #2 +2 lines]'
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Button' })).toBeUndefined()
})

for (const [terminal, env, hasPicture] of [
  ['Ghostty', { TERM_PROGRAM: 'ghostty' }, true],
  ['Orca', { TERM_PROGRAM: 'Orca' }, false],
] as const) {
  test(`a pasted image in ${terminal} shows as ${hasPicture ? 'a thumbnail' : 'a line that opens it'}`, async ($, on) => {
    const { clock, state } = harness(on, env)
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

    state.draft = 'see [Image #1]'
    await clock.advance(200)

    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    const image = await band.find({ type: 'Image' })
    const line = await band.find({ type: 'Button', key: 'image-1', text: '#1 · image 800×400 — open' })
    if (hasPicture) {
      expect(image?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/1.png`, format: 'png' } })
      expect(line).toBeUndefined()
    } else {
      expect(image).toBeUndefined()
      expect(line).toBeDefined()
      // Pressing it opens the cached file in the system's viewer.
      await $.ui.press({ plugin: 'paste-view', key: 'image-1' })
      expect(state.ran).toContainEqual(['open', `${IMAGES_DIR}/1.png`])
    }
  })
}

for (const [terminal, env] of [
  ['Ghostty', { TERM_PROGRAM: 'ghostty' }],
  ['Orca', { TERM_PROGRAM: 'Orca' }],
] as const) {
  test(`a pasted JPEG in ${terminal} shows as a line that opens it`, async ($, on) => {
    const { clock, state } = harness(on, env)
    state.images = ['1.jpg', '12.png']
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

    state.draft = 'see [Image #1]'
    await clock.advance(200)

    // The Image element only draws a PNG file, so no thumbnail, even where pictures show.
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ type: 'Image' })).toBeUndefined()
    expect(await band.find({ type: 'Button', key: 'image-1', text: '#1 · image · jpg — open' })).toBeDefined()
    await $.ui.press({ plugin: 'paste-view', key: 'image-1' })
    expect(state.ran).toContainEqual(['open', `${IMAGES_DIR}/1.jpg`])
  })
}

test('an image whose file is still missing does not redraw the band on every poll', async ($, on) => {
  const { clock, state } = harness(on, { TERM_PROGRAM: 'ghostty' })
  state.images = []
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.draft = 'see [Image #1]'
  await clock.advance(200)
  const afterFirst = state.writes
  await clock.advance(200)
  await clock.advance(200)
  expect(state.writes).toBe(afterFirst)

  // Once its file lands, the next poll finds it and draws it.
  state.images = ['1.png']
  await clock.advance(200)
  expect(state.writes).toBeGreaterThan(afterFirst)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Image' }))?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/1.png` } })
})

test('a clipboard read that fails once does not cost the session its previews', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = LOREM
  state.isClipboardDown = true
  state.draft = '[Pasted text #1 +2 lines]'
  await clock.advance(200)

  // The next paste is read again: the failure was that read's, not the machine's.
  state.isClipboardDown = false
  state.draft = '[Pasted text #1 +2 lines] [Pasted text #2 +2 lines]'
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: '#1 · 3 lines · no preview (clipboard changed)' })).toBeDefined()
  // The label, then the text's own lines under it.
  expect((await band.find({ type: 'Button', key: 'text-2' }))?.props).toMatchObject({ label: '#2 · 3 lines · 79 chars' })
  expect(await band.find({ type: 'Text', text: '   consectetur adipiscing elit,' })).toBeDefined()
})

test('a session nobody types in is not polled', async ($, on) => {
  const { clock, state } = harness(on)
  // A `-p` run or the SDK: no prompt box to watch.
  await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })

  await clock.advance(1000)
  expect(state.reads).toBe(0)
})

test('on Windows a pasted text is read from the clipboard by PowerShell', async ($, on) => {
  const { clock, state } = harness(on, {}, true)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  // The Windows clipboard ends its lines with CRLF: they are folded to LF, so the
  // count is the text's own and no carriage return reaches the pane.
  state.clipboard = LOREM.replace(/\n/g, '\r\n')
  state.draft = 'explain [Pasted text #2 +2 lines]'
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  // The label, then the text's own lines under it.
  expect((await band.find({ type: 'Button', key: 'text-2' }))?.props).toMatchObject({ label: '#2 · 3 lines · 79 chars' })
  expect(await band.find({ type: 'Text', text: '   consectetur adipiscing elit,' })).toBeDefined()
  // PowerShell alone is asked: a pbpaste or xclip left on the PATH must not answer first.
  expect(state.ran.map(([command]) => command)).toEqual(['powershell.exe'])
})

test('on Windows a pasted image is found under %TEMP%\\claude and opens through PowerShell', async ($, on) => {
  const { clock, state } = harness(on, {}, true)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.draft = 'see [Image #1]'
  await clock.advance(200)
  if (!isWindowsHost(state)) return

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Button', key: 'image-1', text: '#1 · image 800×400 — open' })).toBeDefined()
  await $.ui.press({ plugin: 'paste-view', key: 'image-1' })
  expect(state.ran.at(-1)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', OPEN_COMMAND])
  expect(state.env).toEqual({ PASTE_VIEW_PATH: `${WINDOWS_IMAGES_DIR}/1.png` })
  // Windows has neither `id` nor `uname`: a poll that asked for one would fail.
  expect(state.ran.some(([command]) => command === 'id' || command === 'uname')).toBe(false)
})

// PowerShell ends a quoted string at ' and at the typographic ‘ ’ ‚ ‛ alike, and runs
// what follows: the path travels in the environment, never in the command line.
test('on Windows an apostrophe in an image name stays out of the PowerShell command', async ($, on) => {
  const { clock, state } = harness(on, {}, true)
  state.images = ['1.it’s.jpg']
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.draft = 'see [Image #1]'
  await clock.advance(200)
  if (!isWindowsHost(state)) return

  await $.ui.mount({ ...BAND, surface: 'terminal' })
  await $.ui.press({ plugin: 'paste-view', key: 'image-1' })
  expect(state.ran.at(-1)?.at(-1)).toBe(OPEN_COMMAND)
  expect(state.env).toEqual({ PASTE_VIEW_PATH: `${WINDOWS_IMAGES_DIR}/1.it’s.jpg` })
})

test('the lines shown of a text keep their indentation and lose what a terminal would obey', () => {
  expect(previewLines('\n\ndef f():\n\treturn 1\n\nnext', 3, 40)).toEqual(['def f():', '  return 1', ''])
  expect(previewLines('\u001b[31mred\u001b[0m alert\u0007', 5, 40)).toEqual(['red alert'])
  expect(previewLines('abcdefghij', 5, 5)).toEqual(['abcd…'])
  expect(previewLines('   \n', 5, 40)).toEqual([])
  expect(previewLines('one', 0, 40)).toEqual([])
})

test('a mosaic is a whole grid of hex pixels, cut into runs of equal cells', () => {
  expect(parseMosaic('ff0000ff000000ff00\n000000000000ffffff\n')).toEqual(['ff0000ff000000ff00', '000000000000ffffff'])
  expect(parseMosaic('ff0000\n')).toBeNull() // a cell needs two pixel rows
  expect(parseMosaic('ff0000\n00ff0000\n')).toBeNull() // ragged
  expect(parseMosaic('ff0000\nnot-hex\n')).toBeNull()
  expect(parseMosaic('')).toBeNull()
  // Two red-over-black cells side by side are one run; the green-over-white one is its own.
  expect(mosaicCells(['ff0000ff000000ff00', '000000000000ffffff'])).toEqual([
    [
      { top: '#ff0000', bottom: '#000000', cells: 2 },
      { top: '#00ff00', bottom: '#ffffff', cells: 1 },
    ],
  ])
})

test('on Windows an image is drawn as a mosaic above its line, at the largest size too', async ($, on) => {
  const { clock, state } = harness(on, {}, true)
  // 48 columns by 10 rows, no two neighbours alike: the most cells a mosaic ever holds.
  const pixel = (x: number, y: number) => ((x * 5 + y * 13) % 256).toString(16).padStart(2, '0').repeat(3)
  state.mosaic = Array.from({ length: 20 }, (_, y) => Array.from({ length: 48 }, (_, x) => pixel(x, y)).join('')).join('\n')
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.draft = 'see [Image #1]'
  await clock.advance(200)
  if (!isWindowsHost(state)) return

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  // The first cell: pixel 00 over pixel 0d.
  const cell = await band.find({ type: 'Text', text: '▀' })
  expect(cell?.props).toMatchObject({ color: '#000000', backgroundColor: '#0d0d0d' })
  // The line that opens the image stays under the mosaic.
  expect(await band.find({ type: 'Button', key: 'image-1', text: '#1 · image 800×400 — open' })).toBeDefined()
  expect(state.env).toEqual({ PASTE_VIEW_PATH: `${WINDOWS_IMAGES_DIR}/1.png`, PASTE_VIEW_COLUMNS: '48', PASTE_VIEW_ROWS: '10' })
})

test('a long text shows its first five lines and how many are left', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = ['def main():', '    one()', '    two()', '    three()', '    four()', '    five()', '    six()', '    seven()'].join('\n')
  state.draft = '[Pasted text #1 +7 lines]'
  await clock.advance(200)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Button', key: 'text-1' }))?.props).toMatchObject({ label: '#1 · 8 lines · 87 chars' })
  // Indentation is the text's own, under the label.
  expect(await band.find({ type: 'Text', text: '   def main():' })).toBeDefined()
  expect(await band.find({ type: 'Text', text: '       four()' })).toBeDefined()
  expect(await band.find({ type: 'Text', text: 'five()' })).toBeUndefined()
  expect(await band.find({ type: 'Text', text: '   … 3 more lines' })).toBeDefined()
})

test('a text of one line, or a band with no room, keeps the first line on the label', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = 'one long line'
  state.draft = '[Pasted text #1]'
  await clock.advance(200)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Button', key: 'text-1' }))?.props).toMatchObject({ label: '#1 · 1 lines · 13 chars — one long line' })
  await band.unmount()

  // Three rows: the label, the hint, and one to spare, which a single line of text is not worth.
  state.clipboard = LOREM
  state.draft = '[Pasted text #2 +2 lines]'
  await clock.advance(200)
  const tight = await $.ui.mount({ ...BAND, props: { ...BAND.props, maxRows: 3 }, surface: 'terminal' })
  expect((await tight.find({ type: 'Button', key: 'text-2' }))?.props).toMatchObject({
    label: '#2 · 3 lines · 79 chars — Lorem ipsum dolor sit amet,',
  })
})

test('the hint names the click under the fullscreen layout alone', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = LOREM
  state.draft = '[Pasted text #1 +2 lines]'
  await clock.advance(200)

  // On the main screen a click reaches no line.
  const main = await $.ui.mount({ ...BAND, viewport: { ...BAND.viewport, isFullscreen: false }, surface: 'terminal' })
  expect(await main.find({ type: 'Text', text: 'to open one: press Ctrl+X, then Tab, then its number' })).toBeDefined()
  expect(await main.find({ type: 'Text', text: 'click' })).toBeUndefined()
  await main.unmount()

  const fullscreen = await $.ui.mount({ ...BAND, viewport: { ...BAND.viewport, isFullscreen: true }, surface: 'terminal' })
  expect(await fullscreen.find({ type: 'Text', text: 'to open one: click its line, or press Ctrl+X, then Tab, then its number' })).toBeDefined()
})

test('a text open in the pane is scrolled and closed from the band, which holds the keyboard', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = Array.from({ length: 25 }, (_, i) => `line ${i + 1}`).join('\n')
  state.draft = '[Pasted text #1 +24 lines]'
  await clock.advance(200)

  const closed = await $.ui.mount({ ...BAND, surface: 'terminal' })
  // Nothing is open: no key moves a pane.
  expect(await closed.find({ type: 'Button', key: 'pane-down' })).toBeUndefined()
  await $.ui.press({ plugin: 'paste-view', key: 'text-1' })
  await closed.unmount()

  // The pane opens without the keyboard, since the prompt holds text: the band has it.
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await band.find({ type: 'Button', key: 'pane-down' }))?.props).toMatchObject({ hotkey: 'j', label: 'down' })
  expect((await band.find({ type: 'Button', key: 'pane-up' }))?.props).toMatchObject({ hotkey: 'k', label: 'up' })
  expect((await band.find({ type: 'Button', key: 'pane-close' }))?.props).toMatchObject({ hotkey: 'x', label: 'close' })

  // The text is drawn ten lines a part: down shows the next part from its first line.
  expect(await pane.find({ type: 'Box', key: 'part-2' })).toBeDefined()
  await $.ui.press({ plugin: 'paste-view', key: 'pane-down' })
  await $.ui.press({ plugin: 'paste-view', key: 'pane-down' })
  await $.ui.press({ plugin: 'paste-view', key: 'pane-down' }) // already at the last part
  await $.ui.press({ plugin: 'paste-view', key: 'pane-up' })
  // What each press asks of the pane's window is checked on screen: the kit (2.1.291) hands a
  // plugin's scroll to no hook of the test, so here the presses only have to be taken.

  await $.ui.press({ plugin: 'paste-view', key: 'pane-close' })
  expect(state.closed).toEqual(['paste-view'])
})

test('the pane promises the arrows only while it holds the keyboard', async ($, on) => {
  const { clock, state } = harness(on)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

  state.clipboard = LOREM
  state.draft = '[Pasted text #2 +2 lines]'
  await clock.advance(200)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await $.ui.press({ plugin: 'paste-view', key: 'text-2' })
  await band.unmount()

  const without = await $.ui.mount({ ...PANE, props: { ...PANE.props, isFocused: false }, surface: 'terminal' })
  expect(await without.find({ type: 'Text', text: '3 lines · 79 chars · j k scroll · x close' })).toBeDefined()
  expect(await without.find({ type: 'Text', text: '↑↓' })).toBeUndefined()
  await without.unmount()

  const held = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await held.find({ type: 'Text', text: '3 lines · 79 chars · ↑↓ scroll · esc close' })).toBeDefined()
})
