// Local to claude-config, not upstream's: an image shown in the band with no key
// pressed, as a mosaic of half blocks, for the terminals that draw no pictures. Windows
// Terminal and VS Code speak Sixel, Claude Code's Image element the kitty protocol only.

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

/** A mosaic as the Raster element takes it: its size in cells, and the cells packed. */
export type Mosaic = { columns: number; rows: number; cells: string }

const HALF_BLOCK = 0x2580

/**
 * A grid of pixels as one grid of half blocks: for each cell the block's code point,
 * the upper pixel as its ink and the lower as its background, each a little-endian u32,
 * row after row, in base64.
 */
export function mosaicRaster(pixels: readonly string[]): Mosaic {
  const columns = (pixels[0]?.length ?? 0) / 6
  const rows = Math.floor(pixels.length / 2)
  const u32 = (value: number) => String.fromCharCode(value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, value >>> 24)
  const colour = (row: number, x: number) => parseInt((pixels[row] ?? '').slice(x * 6, x * 6 + 6), 16)
  let bytes = ''
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < columns; x++) bytes += u32(HALF_BLOCK) + u32(colour(2 * y, x)) + u32(colour(2 * y + 1, x))
  }
  return { columns, rows, cells: btoa(bytes) }
}
