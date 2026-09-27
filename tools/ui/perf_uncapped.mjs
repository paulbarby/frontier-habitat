// perf_uncapped.mjs — frame rate of a web build WITHOUT the vsync cap, in invisible headless Chrome
// with the real GPU, so that GPU cost differences (for example the glass blur) show.
//
//   node tools/ui/perf_uncapped.mjs build/web_ui --query "load=...&title=0&speed=0" --steps s.json
//
// Steps as in tools/shoot.mjs: {"cmd": text}, {"wait": s}, {"eval": js}. An eval of the special
// string "FPS <label> <seconds>" averages window.__fh.fps over that time and prints it.
// Chrome flags: --disable-gpu-vsync --disable-frame-rate-limit (plus the GPU flags of shoot.mjs).
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const DIR = path.resolve(args[0] && !args[0].startsWith('--') ? args[0] : 'build/web_ui');
const QUERY = opt('query', '');
const STEPS = JSON.parse(fs.readFileSync(opt('steps', ''), 'utf8'));
const [W, H] = opt('size', '1600x900').split('x').map(Number);
const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (rel.endsWith('/')) rel += 'index.html';
  const f = path.join(DIR, rel);
  if (!f.startsWith(DIR) || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-perf-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, `--window-size=${W},${H}`, '--mute-audio',
  '--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--disable-gpu-vsync', '--disable-frame-rate-limit', 'about:blank'], { stdio: 'ignore' });
let port = '';
for (let i = 0; i < 100 && !port; i++) { await new Promise(r => setTimeout(r, 100)); try { port = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0]; } catch {} }
const page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let seq = 0; const pend = new Map();
ws.addEventListener('message', ev => { const m = JSON.parse(ev.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const id = ++seq; pend.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const sleep = s => new Promise(r => setTimeout(r, s * 1000));
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/index.html${QUERY ? '?' + QUERY : ''}` });
for (let i = 0; i < 180 && !(await ev('!!(window.__fh && window.__fh.ready)')); i++) await sleep(0.5);
await sleep(3);
for (const st of STEPS) {
  if (st.cmd !== undefined) await ev(`window.__fh.cmd(${JSON.stringify(st.cmd)})`);
  if (st.wait !== undefined) await sleep(st.wait);
  if (st.eval !== undefined) {
    const m = /^FPS (\S+) (\d+)$/.exec(st.eval);
    if (m) {
      const n = Number(m[2]) * 2; let sum = 0, lo = 1e9;
      for (let i = 0; i < n; i++) { await sleep(0.5); const f = Number(await ev('window.__fh.fps')); sum += f; lo = Math.min(lo, f); }
      console.log(`${m[1]}: mean ${(sum / n).toFixed(1)} fps, lowest ${lo.toFixed(1)}`);
    } else console.log(st.eval, '->', JSON.stringify(await ev(st.eval)));
  }
}
ws.close(); chrome.kill(); server.close();
try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(0);
