// Battery color palette — ANSI 24-bit true color escape sequences

export const BRAND        = '\x1b[38;2;217;119;87m';   // #D97757
export const BRAND_DARK   = '\x1b[38;2;184;90;58m';    // #B85A3A
export const BRAND_LIGHT  = '\x1b[38;2;240;196;174m';  // #F0C4AE
export const BRAND_LIGHTER= '\x1b[38;2;245;217;203m';  // #F5D9CB
export const TRACK        = '\x1b[38;2;100;96;90m';     // dim track
export const DIM          = '\x1b[38;2;120;115;108m';   // dim text
export const RESET        = '\x1b[0m';

export function intensityColor(pct) {
  if (pct >= 75) return BRAND_DARK;
  if (pct >= 50) return BRAND;
  if (pct >= 25) return BRAND_LIGHT;
  return BRAND_LIGHTER;
}
