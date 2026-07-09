#!/usr/bin/env node
// Contrast gate for docs SVG diagrams (docs/token-saving.html).
// Two rules, checked for BOTH themes:
//   1. Ink-token rule: every SVG <text> must wear an ink token (--text/--bright/--dim
//      via class or fill) — never a literal color or a series color on text.
//   2. WCAG AA: each ink token used by diagram text must hit >= 4.5:1 against the
//      figure surface (--surface) in light AND dark themes.
// Usage: node tests/check-color-contrast.mjs   (exit 1 on any FAIL)
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const css = readFileSync(join(root, 'docs/research/research-style.css'), 'utf8');
const html = readFileSync(join(root, 'docs/token-saving.html'), 'utf8');

function varsFrom(block) {
  const out = {};
  for (const m of block.matchAll(/--([\w-]+):\s*(#[0-9A-Fa-f]{6})/g)) out[m[1]] = m[2];
  return out;
}
const lightBlock = css.match(/:root\s*{([^}]*)}/s)[1];
const darkBlock = css.match(/\[data-theme="dark"\]\s*{([^}]*)}/s)[1];
const themes = { light: varsFrom(lightBlock), dark: varsFrom(darkBlock) };

function luminance(hex) {
  const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(v => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
const contrast = (a, b) => {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
};

let failures = 0;
const report = [];

// Rule 1: SVG text elements carry ink tokens only.
const INK_CLASSES = { 'bar-label': 'text', 'bar-value': 'bright', 'stack-label': 'bright', 'stack-sub': 'text' };
const svgBlocks = [...html.matchAll(/<svg[\s\S]*?<\/svg>/g)].map(m => m[0]);
const usedInks = new Set();
for (const svg of svgBlocks) {
  for (const t of svg.matchAll(/<text\b[^>]*>/g)) {
    const tag = t[0];
    const cls = (tag.match(/class="([\w-]+)"/) || [])[1];
    const fill = (tag.match(/fill="([^"]+)"/) || [])[1];
    if (fill && !/^var\(--(text|bright|dim)\)$/.test(fill)) {
      report.push(`FAIL ink-token: <text> carries non-ink fill "${fill}" — text wears ink tokens, marks carry color`);
      failures++;
    } else if (fill) {
      usedInks.add(fill.match(/--([\w-]+)/)[1]);
    }
    if (cls && INK_CLASSES[cls]) usedInks.add(INK_CLASSES[cls]);
    if (!cls && !fill) {
      report.push(`FAIL ink-token: unclassed, unfilled <text> (inherits unknown color): ${tag}`);
      failures++;
    }
  }
}

// Rule 2: every used ink meets AA (4.5:1, diagram text is small) on --surface, both themes.
for (const [theme, vars] of Object.entries(themes)) {
  const surface = vars['surface'];
  for (const ink of usedInks) {
    const hex = vars[ink];
    const ratio = contrast(hex, surface);
    const ok = ratio >= 4.5;
    report.push(`${ok ? 'PASS' : 'FAIL'} ${theme}: --${ink} (${hex}) on --surface (${surface}) = ${ratio.toFixed(2)}:1 (need 4.5)`);
    if (!ok) failures++;
  }
  // Series fills must be distinguishable from the surface itself (3:1 non-text graphics).
  for (const series of ['accent', 'accent-4', 'positive']) {
    const ratio = contrast(vars[series], surface);
    const ok = ratio >= 3;
    report.push(`${ok ? 'PASS' : 'FAIL'} ${theme}: series --${series} (${vars[series]}) vs surface = ${ratio.toFixed(2)}:1 (need 3.0 graphics)`);
    if (!ok) failures++;
  }
}

console.log(report.join('\n'));
console.log(failures ? `\n${failures} FAILURE(S)` : '\nALL CHECKS PASS');
process.exit(failures ? 1 : 0);
