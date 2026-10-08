// Renders public/icons/icon.svg to the PNG sizes phones need for
// "Add to Home Screen". Run: node scripts/make-icons.mjs (needs playwright-core
// and a Chromium; set CHROMIUM_PATH if it is not on the default path).
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright-core';

const svg = readFileSync(new URL('../public/icons/icon.svg', import.meta.url), 'utf8');
const out = (name) => new URL(`../public/icons/${name}`, import.meta.url).pathname;
const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
const page = await browser.newPage();

async function render(name, size, fullBleed) {
  await page.setViewportSize({ width: size, height: size });
  const inner = fullBleed ? svg.replace('rx="112"', 'rx="0"') : svg;
  const scale = 1;
  await page.setContent(
    `<html><body style="margin:0;background:${fullBleed ? '#1d1538' : 'transparent'};display:grid;place-items:center;width:${size}px;height:${size}px">` +
      `<div style="width:${size * scale}px;height:${size * scale}px">${inner.replace('<svg ', '<svg width="100%" height="100%" ')}</div></body></html>`,
  );
  await page.screenshot({ path: out(name), omitBackground: !fullBleed });
}

await render('icon-192.png', 192, false);
await render('icon-512.png', 512, false);
await render('icon-maskable-512.png', 512, true);
await render('apple-touch-icon.png', 180, true);
await browser.close();
console.log('icons written');
