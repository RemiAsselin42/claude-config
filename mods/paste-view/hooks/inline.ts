// Local to claude-config, not upstream's: what the band shows of a paste with no key
// pressed. The first lines of a text, and an image as a mosaic of half blocks for the
// terminals that draw no pictures: Windows Terminal and VS Code speak Sixel, Claude
// Code's Image element the kitty protocol only.

/** Up to `count` lines from the first non-blank one, indentation kept, each cut to `width`. */
export function previewLines(text: string, count: number, width: number): string[] {
  const lines = text.split(/\r\n|\r|\n/)
  const start = lines.findIndex(line => line.trim() !== '')
  if (start < 0 || count < 1 || width < 1) return []
  return lines.slice(start, start + count).map(line => {
    // A pasted log may hold colour sequences: none of them, and no other control
    // character, reaches the terminal. A tab takes two cells here.
    const clean = line
      .replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
      .replace(/\t/g, '  ')
      .replace(/[\u0000-\u001f\u007f]/g, '')
      .trimEnd()
    return clean.length <= width ? clean : `${clean.slice(0, Math.max(0, width - 1))}…`
  })
}

// The most cells a mosaic takes. A cell is a half block: two pixels, one above the
// other, each its own colour. Sextants (two by three pixels a cell, in two colours)
// were tried for the sharper picture: in the VS Code terminal they drew stray grey
// pixels all over it, for little more detail (Rémi, 2026-10-06).
export const MOSAIC_COLUMNS = 48
export const MOSAIC_ROWS = 10

// PowerShell scales the image to fit the room it is given, to an even number of pixel
// rows, and writes one line of hex per row. The path and the room travel in the
// environment, never in the command line. 0.35 to 0.4s a run (measured 2026-10).
export const MOSAIC_COMMAND = [
  'Add-Type -AssemblyName System.Drawing',
  '$src = [Drawing.Image]::FromFile($env:PASTE_VIEW_PATH)',
  '$scale = [Math]::Min([double]$env:PASTE_VIEW_COLUMNS / $src.Width, 2 * [double]$env:PASTE_VIEW_ROWS / $src.Height)',
  '$w = [Math]::Max(1, [int]($src.Width * $scale))',
  '$h = 2 * [Math]::Max(1, [int]($src.Height * $scale / 2))',
  '$bmp = New-Object Drawing.Bitmap $w, $h',
  '$g = [Drawing.Graphics]::FromImage($bmp)',
  "$g.InterpolationMode = 'HighQualityBicubic'",
  "$g.PixelOffsetMode = 'HighQuality'",
  // Without it the pixels on the edges are blended with the nothing beyond them.
  '$edges = New-Object Drawing.Imaging.ImageAttributes',
  "$edges.SetWrapMode('TileFlipXY')",
  "$g.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $w, $h), 0, 0, $src.Width, $src.Height, 'Pixel', $edges)",
  '$out = New-Object Text.StringBuilder',
  "for ($y = 0; $y -lt $h; $y++) { for ($x = 0; $x -lt $w; $x++) { $p = $bmp.GetPixel($x, $y); [void]$out.AppendFormat('{0:x2}{1:x2}{2:x2}', $p.R, $p.G, $p.B) }; [void]$out.Append([char]10) }",
  '[Console]::Out.Write($out.ToString())',
].join('; ')

/** The pixel rows PowerShell wrote, six hex digits a pixel; null when they are not a whole grid. */
export function parseMosaic(stdout: string): string[] | null {
  const rows = stdout.split(/\r?\n/).filter(row => row !== '')
  const width = rows[0]?.length ?? 0
  const isGrid =
    rows.length >= 2 &&
    rows.length % 2 === 0 &&
    width >= 6 &&
    width % 6 === 0 &&
    rows.every(row => row.length === width && /^[0-9a-f]+$/.test(row))
  return isGrid ? rows : null
}

/** Cells in a row that share their two colours: `top` is the half block's, `bottom` its background. */
export type Run = { top: string; bottom: string; cells: number }

/** A grid of pixels as rows of cells, each row cut into runs of equal cells. */
export function mosaicCells(pixels: readonly string[]): Run[][] {
  const rows: Run[][] = []
  for (let y = 0; y + 1 < pixels.length; y += 2) {
    const upper = pixels[y] ?? ''
    const lower = pixels[y + 1] ?? ''
    const runs: Run[] = []
    for (let at = 0; at < upper.length; at += 6) {
      const top = `#${upper.slice(at, at + 6)}`
      const bottom = `#${lower.slice(at, at + 6)}`
      const last = runs.at(-1)
      if (last !== undefined && last.top === top && last.bottom === bottom) last.cells++
      else runs.push({ top, bottom, cells: 1 })
    }
    rows.push(runs)
  }
  return rows
}
