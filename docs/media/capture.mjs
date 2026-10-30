// Renders docs/media/scene.html with headless Chrome: stills into docs/img and
// video frames into a work folder. No npm packages: Node 22's WebSocket talks to
// the DevTools protocol directly.
//   node docs/media/capture.mjs stills
//   node docs/media/capture.mjs frames <lang> <outDir> [fps]
//   node docs/media/capture.mjs still <query> <out.png>     (one-off preview)
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const imgDir = path.join(here, '..', 'img');
const chromePath = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const port = 9400 + Math.floor(Math.random() * 400);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'winlego-chrome-'));
const chrome = spawn(chromePath, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--window-size=1600,900', '--no-first-run', '--no-default-browser-check',
  '--force-color-profile=srgb', '--allow-file-access-from-files', 'about:blank',
], { stdio: 'ignore' });

async function getJSON(p) {
  for (let i = 0; i < 150; i++) {
    try { return await (await fetch(`http://127.0.0.1:${port}${p}`)).json(); } catch { await sleep(100); }
  }
  throw new Error('Chrome did not start');
}

const page = (await getJSON('/json/list')).find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 0;
const pending = new Map();
ws.onmessage = e => {
  const m = JSON.parse(e.data);
  if (!m.id || !pending.has(m.id)) return;
  const { res, rej } = pending.get(m.id);
  pending.delete(m.id);
  m.error ? rej(new Error(m.error.message)) : res(m.result);
};
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = ++nextId;
  pending.set(id, { res, rej });
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expr => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

async function load(query, { width = 1600, height = 900, scale = 1 } = {}) {
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: scale, mobile: false });
  await send('Page.navigate', { url: `file://${path.join(here, 'scene.html')}?${query}` });
  await sleep(150);
  for (let i = 0; i < 100 && !(await evaluate('window.ready === true')); i++) await sleep(50);
}

async function screenshot(file, clip) {
  // Let the last DOM change paint before grabbing it.
  await evaluate('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))');
  const params = { format: 'png' };
  if (clip) params.clip = { ...clip, scale: 1 };
  const { data } = await send('Page.captureScreenshot', params);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(data, 'base64'));
  return file;
}

async function stills() {
  await load('mode=menu', { scale: 2 });
  console.log(await screenshot(path.join(imgDir, 'menu.png'), await evaluate('window.clip')));
  await load('mode=desk&t=10.9', { scale: 2 });
  console.log(await screenshot(path.join(imgDir, 'overlay.png'), await evaluate('window.clip')));
  for (const lang of ['en', 'ko']) {
    await load(`mode=desk&lang=${lang}&t=18.4`, { scale: 2 });
    console.log(await screenshot(path.join(imgDir, `boundary-${lang}.png`), await evaluate('window.clip')));
  }
}

async function frames(lang, outDir, fps) {
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
  await load(`mode=video&lang=${lang}`);
  const duration = await evaluate('window.DURATION');
  const count = Math.round(duration * fps);
  for (let f = 0; f < count; f++) {
    await evaluate(`render(${f / fps})`);
    await screenshot(path.join(outDir, `${String(f).padStart(5, '0')}.png`));
    if (f % 100 === 0) console.log(`${lang}: frame ${f}/${count}`);
  }
  console.log(`${lang}: ${count} frames → ${outDir}`);
}

try {
  const [cmd, a, b, c] = process.argv.slice(2);
  if (cmd === 'stills') await stills();
  else if (cmd === 'frames') await frames(a, b, Number(c || 30));
  else if (cmd === 'still') {
    await load(a, { scale: 1 });
    console.log(await screenshot(b));
  } else throw new Error('usage: capture.mjs stills | frames <lang> <outDir> [fps] | still <query> <out.png>');
} finally {
  ws.close();
  const exited = new Promise(r => chrome.once('exit', r));
  chrome.kill();
  await exited;
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome may still be flushing */ }
}
