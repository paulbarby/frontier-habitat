// render_perf.mjs (RENDER) — frame-rate measurement of a web build in invisible headless
// Chrome on the real GPU, with the 60 fps frame cap OFF (--disable-gpu-vsync
// --disable-frame-rate-limit), so the number is what the frame really costs.
// Nothing opens on the desktop. Same page hooks as tools/shoot.mjs.
//
//   node tools/render_perf.mjs --dir build/web_render --query "..." [--size 1600x900]
//        [--pre steps.json] --secs 10 [--label text] [--out perf.json]
//
// --pre: steps as in shoot.mjs ({cmd}|{eval}|{wait}) run before the measurement.
// Then __fhr stats are sampled every 0.5 s for --secs seconds; prints mean / min fps, mean
// draw calls, primitives, RENDER script ms (view_ms), Godot process ms.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && i + 1 < args.length ? args[i + 1] : d; };
const DIR = path.resolve(opt('dir', 'build/web_render'));
const QUERY = opt('query', '');
const [W, H] = opt('size', '1600x900').split('x').map(Number);
const SECS = Number(opt('secs', '10'));
const PRE = opt('pre', '') ? JSON.parse(fs.readFileSync(opt('pre', ''), 'utf8')) : [];
const LABEL = opt('label', '');
const OUT = opt('out', '');
const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));

const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(DIR, rel);
  if (!file.startsWith(DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-perf-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, `--window-size=${W},${H}`,
  '--hide-scrollbars', '--mute-audio', '--no-first-run', '--no-default-browser-check', '--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist',
  '--disable-gpu-vsync', '--disable-frame-rate-limit', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
let wsUrl = '';
for (let i = 0; i < 100 && !wsUrl; i++) {
  await new Promise(r => setTimeout(r, 100));
  const f = path.join(profile, 'DevToolsActivePort');
  if (fs.existsSync(f)) wsUrl = fs.readFileSync(f, 'utf8').split('\n')[0];
}
const list = await (await fetch(`http://127.0.0.1:${wsUrl}/json/list`)).json();
const ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let seq = 0; const pending = new Map();
ws.addEventListener('message', (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const sleep = (s) => new Promise(r => setTimeout(r, s * 1000));
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: `http://127.0.0.1:${port}/index.html${QUERY ? '?' + QUERY : ''}` });
const t0 = Date.now();
while ((Date.now() - t0) / 1000 < 90 && !(await evaluate('!!(window.__fh && window.__fh.ready)'))) await sleep(0.5);
await sleep(3);
for (const st of PRE) {
  if (st.cmd !== undefined) await evaluate(`window.__fh.cmd(${JSON.stringify(st.cmd)})`);
  if (st.eval !== undefined) console.log('pre', st.eval, '->', JSON.stringify(await evaluate(st.eval)));
  if (st.wait !== undefined) await sleep(st.wait);
}
const samples = [];
const tEnd = Date.now() + SECS * 1000;
while (Date.now() < tEnd) {
  await sleep(0.5);
  const s = await evaluate("(window.__fhr && window.__fhr.cmd('stats'), window.__fhr ? window.__fhr.last : '{}')");
  try { samples.push(JSON.parse(s)); } catch {}
}
const mean = (k) => samples.reduce((a, s) => a + Number(s[k] || 0), 0) / Math.max(1, samples.length);
const min = (k) => Math.min(...samples.map(s => Number(s[k] || 0)));
const last = samples[samples.length - 1] || {};
const res = { label: LABEL, query: QUERY, samples: samples.length, fps_mean: +mean('fps').toFixed(1), fps_min: min('fps'),
  draw_calls: Math.round(mean('draw_calls')), draw_calls_max: Math.max(...samples.map(s => Number(s.draw_calls || 0))),
  primitives: Math.round(mean('primitives')), view_ms: +mean('view_ms').toFixed(2), process_ms: +mean('process_ms').toFixed(2),
  colonists: last.colonists, structures: last.structures, quality: last.quality, prof: last.prof, npc_ms: last.npc && last.npc.ms, map: last.terrain && last.terrain.map, lod: last.lod };
console.log(JSON.stringify(res));
if (OUT) { const prev = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT, 'utf8')) : []; prev.push({ at: new Date().toISOString(), ...res }); fs.writeFileSync(OUT, JSON.stringify(prev, null, 1)); }
ws.close(); chrome.kill(); server.close();
try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(0);
