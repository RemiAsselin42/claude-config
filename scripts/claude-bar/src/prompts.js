import { BRAND, DIM, RESET } from './colors.js';

const FILLED = '◼';
const EMPTY = '◻';
const HIDE_CURSOR = '\x1b[?25l';
const SHOW_CURSOR = '\x1b[?25h';

export function multiSelect(options) {
  return new Promise((resolve) => {
    const checked = options.map((o) => o.default !== false);
    let cursor = 0;

    function render() {
      // Move up to overwrite previous render (all lines: header + blank + items + blank + hint)
      const totalLines = options.length + 4;
      process.stdout.write(`\x1b[${totalLines}A`);
      draw();
    }

    function draw() {
      const lines = [];
      lines.push(`  Choose which lines to show:\n`);
      for (let i = 0; i < options.length; i++) {
        const icon = checked[i] ? FILLED : EMPTY;
        const focused = i === cursor;
        const color = focused ? BRAND : DIM;
        lines.push(`  ${color}${icon} ${options[i].label}${RESET}`);
      }
      lines.push('');
      lines.push(`  ${DIM}↑↓ navigate  space toggle  enter confirm${RESET}`);
      process.stdout.write(lines.join('\n') + '\n');
    }

    process.stdout.write(HIDE_CURSOR);
    draw();

    const { stdin } = process;
    const wasRaw = stdin.isRaw;
    stdin.setRawMode(true);
    stdin.resume();

    function cleanup() {
      stdin.setRawMode(wasRaw ?? false);
      stdin.removeListener('data', onKey);
      stdin.pause();
      process.stdout.write(SHOW_CURSOR);
    }

    function onKey(buf) {
      const key = buf.toString();

      // Ctrl-C — abort
      if (key === '\x03') {
        cleanup();
        process.exit(0);
      }

      // Enter — confirm
      if (key === '\r' || key === '\n') {
        cleanup();
        resolve(checked);
        return;
      }

      // Space — toggle
      if (key === ' ') {
        checked[cursor] = !checked[cursor];
        render();
        return;
      }

      // Arrow keys (escape sequences)
      if (key === '\x1b[A' || key === 'k') {
        cursor = (cursor - 1 + options.length) % options.length;
        render();
        return;
      }
      if (key === '\x1b[B' || key === 'j') {
        cursor = (cursor + 1) % options.length;
        render();
        return;
      }
    }

    stdin.on('data', onKey);
  });
}
