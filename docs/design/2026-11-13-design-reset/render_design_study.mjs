import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';

const folder = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(process.env.APPDATA, 'npm', 'render.cjs'));
const puppeteer = require('puppeteer-core');
const browser = await puppeteer.launch({
  executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  headless: true,
});
try {
  for (const name of ['direction-study', 'system-study']) {
    const page = await browser.newPage();
    const svg = readFileSync(join(folder, name + '.svg'), 'utf8');
    const width = Number(svg.match(/width="(\d+)"/)[1]);
    const height = Number(svg.match(/height="(\d+)"/)[1]);
    await page.setViewport({width, height, deviceScaleFactor: 1});
    await page.setContent('<html><head><meta charset="utf-8"></head><body style="margin:0">' + svg + '</body></html>');
    await page.evaluate(() => document.fonts.ready);
    const overflows = await page.evaluate(() => [...document.querySelectorAll('svg > g > text')].flatMap(el => {
      const box = el.getBBox();
      return box.x + box.width > 379 ? [{text: el.textContent, right: Math.round(box.x + box.width)}] : [];
    }));
    assert.deepEqual(overflows, [], name + ': text exceeds phone bounds');
    await page.screenshot({path: join(folder, name + '.png'), fullPage: true});
    console.log(name + ': rendered; horizontal text bounds passed');
    await page.close();
  }
} finally {
  await browser.close();
}
