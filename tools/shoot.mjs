// shoot.mjs — screenshots of the WEB build in an invisible (headless) Chrome.
// Nothing opens on the desktop. No dependencies: Node 22 has fetch and WebSocket.
//
// usage:
//   node tools/shoot.mjs --dir build/web --out shots/a.png [--query "seed=1001&demo=1&fast=600"]
//                        [--size 1600x900] [--wait 30] [--gpu] [--steps steps.json]
//
//   --dir    folder with index.html of a web export (served on a free local port)
//   --out    PNG path for a single screenshot (taken when the game reports ready + --settle)
//   --query  URL query string; the game reads it as boot parameters (docs/AAA_DESIGN.md §14)
//   --wait   seconds to wait for window.__fh.ready (default 60)
//   --settle seconds to wait after ready before the first shot (default 3)
//   --gpu    use the real GPU through ANGLE/D3D11 (default: SwiftShader software WebGL)
//   --steps  JSON list of steps: {"cmd": "text"} calls window.__fh.cmd(text);
//            {"wait": seconds}; {"shot": "path.png"}; {"eval": "js expression"} prints the result.
//   --console  print the page console to stdout
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf('--' + name); return i >= 0 && i + 1 < args.length && !args[i + 1].startsWith('--') ? args[i + 1] : dflt; };
const flag = (name) => args.includes('--' + name);

const DIR = path.resolve(opt('dir', 'build/web'));
const OUT = opt('out', '');
const QUERY = opt('query', '');
const [W, H] = opt('size', '1600x900').split('x').map(Number);
const WAIT = Number(opt('wait', '60'));
const SETTLE = Number(opt('settle', '3'));
const STEPS = opt('steps', '') ? JSON.parse(fs.readFileSync(opt('steps', ''), 'utf8')) : null;
const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));
if (!fs.existsSync(path.join(DIR, 'index.html'))) { console.error('no index.html in ' + DIR); process.exit(2); }

// ---------------------------------------------------------------- static server
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

// ---------------------------------------------------------------- chrome
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-shoot-'));
const gl = flag('gpu') ? ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'] : ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'];
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, `--window-size=${W},${H}`,
  '--hide-scrollbars', '--mute-audio', '--no-first-run', '--no-default-browser-check', '--autoplay-policy=no-user-gesture-required', ...gl, 'about:blank'],
  { stdio: ['ignore', 'ignore', 'pipe'] });
let wsUrl = '';
for (let i = 0; i < 100 && !wsUrl; i++) {
  await new Promise(r => setTimeout(r, 100));
  const f = path.join(profile, 'DevToolsActivePort');
  if (fs.existsSync(f)) { const [p] = fs.readFileSync(f, 'utf8').split('\n'); wsUrl = p; }
}
if (!wsUrl) { console.error('chrome did not start'); process.exit(3); }
const list = await (await fetch(`http://127.0.0.1:${wsUrl}/json/list`)).json();
const page = list.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let seq = 0; const pending = new Map();
ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method === 'Runtime.consoleAPICalled' && flag('console')) console.log('[page]', m.params.args.map(a => a.value ?? a.description).join(' '));
  else if (m.method === 'Runtime.exceptionThrown') console.log('[page error]', m.params.exceptionDetails.text, m.params.exceptionDetails.exception?.description || '');
});
const send = (method, params = {}) => new Promise(r => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }); return r.result?.result?.value; };
const shot = async (file) => {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, Buffer.from(r.result.data, 'base64'));
  console.log('shot', path.resolve(file));
};
const sleep = (s) => new Promise(r => setTimeout(r, s * 1000));

await send('Runtime.enable');
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
const url = `http://127.0.0.1:${port}/index.html${QUERY ? '?' + QUERY : ''}`;
await send('Page.navigate', { url });
const t0 = Date.now();
let ready = false;
while ((Date.now() - t0) / 1000 < WAIT) {
  ready = await evaluate('!!(window.__fh && window.__fh.ready)');
  if (ready) break;
  await sleep(0.5);
}
console.log(ready ? `ready after ${((Date.now() - t0) / 1000).toFixed(1)} s` : `NOT ready after ${WAIT} s (shooting anyway)`);
await sleep(SETTLE);
if (OUT) await shot(OUT);
for (const st of STEPS || []) {
  if (st.cmd !== undefined) console.log('cmd', st.cmd, '->', await evaluate(`window.__fh && window.__fh.cmd ? String(window.__fh.cmd(${JSON.stringify(st.cmd)})) : 'no cmd hook'`));
  if (st.wait !== undefined) await sleep(st.wait);
  if (st.eval !== undefined) console.log('eval', st.eval, '->', JSON.stringify(await evaluate(st.eval)));
  if (st.shot !== undefined) await shot(st.shot);
}
ws.close();
chrome.kill();
server.close();
try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(0);
