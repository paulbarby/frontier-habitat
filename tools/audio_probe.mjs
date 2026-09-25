// audio_probe.mjs — measures what a web build actually sends to the speakers.
// usage: node tools/audio_probe.mjs [build dir=build/web] [--query "seed=1001"] [--music 0|1] [--min-db -45]
//
// Copies the build to a temp folder, adds an AnalyserNode tap on every connection to the Web Audio
// destination, runs the game in invisible headless Chrome with the GPU (tools/shoot.mjs), and
// prints the peak and RMS level in dBFS over 5 s of play. Exit code 1 when the peak is below
// --min-db. A level of -inf means silence. (Chrome runs with --mute-audio: the graph still runs.)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const dir = path.resolve(ROOT, args[0] && !args[0].startsWith('--') ? args[0] : 'build/web');
const query = opt('query', 'seed=1001');
const minDb = Number(opt('min-db', '-45'));
const music = opt('music', '');

const PROBE = `
(function(){
  const cn = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(t, ...r){
    if (t instanceof AudioDestinationNode) {
      const c = this.context;
      if (!c.__an) { c.__an = c.createAnalyser(); c.__an.fftSize = 2048; window.__an = c.__an; window.__actx = c; }
      cn.call(this, c.__an);
    }
    return cn.call(this, t, ...r);
  };
  window.__level = async function(ms){
    if (!window.__an) return {peak: 0, rms: 0, state: 'no destination connection'};
    const a = new Float32Array(2048); let peak = 0, rms = 0; const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      window.__an.getFloatTimeDomainData(a); let s = 0, m = 0;
      for (const v of a) { s += v * v; m = Math.max(m, Math.abs(v)); }
      peak = Math.max(peak, m); rms = Math.max(rms, Math.sqrt(s / a.length));
      await new Promise(x => setTimeout(x, 50));
    }
    return {peak, rms, state: window.__actx.state};
  };
})();`;

if (!fs.existsSync(path.join(dir, 'index.html'))) { console.error('no index.html in ' + dir); process.exit(2); }
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-audio-'));
for (const f of fs.readdirSync(dir)) {
  const src = path.join(dir, f);
  if (fs.statSync(src).isFile()) { try { fs.linkSync(src, path.join(tmp, f)); } catch { fs.copyFileSync(src, path.join(tmp, f)); } }
}
fs.writeFileSync(path.join(tmp, 'probe.js'), PROBE);
const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8').replace('<head>', '<head><script src="probe.js"></script>');
fs.rmSync(path.join(tmp, 'index.html'));
fs.writeFileSync(path.join(tmp, 'index.html'), html);

const steps = [{ wait: 3 }];
if (music !== '') steps.push({ eval: `window.__fh && window.__fh.cmd ? String(window.__fh.cmd('volume music ${music}')) : 'no cmd'` });
steps.push({ cmd: 'speed 1' }, { wait: 3 },
  { eval: `(async () => ({fps: window.__fh && window.__fh.fps, level: await window.__level(5000)}))()` });
const stepsFile = path.join(tmp, 'steps.json');
fs.writeFileSync(stepsFile, JSON.stringify(steps));

const r = spawnSync(process.execPath, [path.join(ROOT, 'tools/shoot.mjs'), '--gpu', '--dir', tmp, '--query', query, '--steps', stepsFile],
  { encoding: 'utf8', timeout: 240000 });
fs.rmSync(tmp, { recursive: true, force: true });
const line = (r.stdout || '').split('\n').filter(l => l.includes('"level"')).pop();
if (!line) { console.error('no measurement\n' + r.stdout + r.stderr); process.exit(2); }
const res = JSON.parse(line.slice(line.indexOf('-> ') + 3));
const db = (v) => v > 0 ? (20 * Math.log10(v)).toFixed(1) : '-inf';
console.log(`fps ${res.fps}  audio context ${res.level.state}  peak ${db(res.level.peak)} dBFS  rms ${db(res.level.rms)} dBFS  (limit ${minDb} dBFS)`);
const ok = res.level.peak > 0 && 20 * Math.log10(res.level.peak) >= minDb;
console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 1);
