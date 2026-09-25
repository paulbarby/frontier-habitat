// audio_glitch_probe.mjs — counts audio dropouts (the crackle) of a web build at a capped frame rate.
//
//   node tools/ui/audio_glitch_probe.mjs build/web_ui [--query "load=...&title=0"] [--fps 40] [--speed 4] [--seconds 10] [--stall 60]
//   --stall N: halfway, runs "fast N" (a main-thread stall) as a positive control: it must show dropouts.
//
// Like tools/audio_probe.mjs (orchestrator), it copies the build to a temp folder and taps every
// connection to the Web Audio destination. Here the tap is an AudioWorklet (audio thread) that sees
// EVERY render quantum (128 samples). A dropout = a quantum of exact silence right after a quantum
// with sound (peak > 1e-4): Godot's worklet writes nothing when its ring buffer runs dry. The engine writes silence when
// its mixer does not fill the buffer in time (underrun), which is heard as a click or crackle.
// The game runs with `maxfps <fps>` (automation command) and at `speed <speed>`.
// Prints: fps, seconds measured, dropouts, dropouts per minute, peak dBFS.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const dir = path.resolve(ROOT, args[0] && !args[0].startsWith('--') ? args[0] : 'build/web_ui');
const query = opt('query', 'load=res://content/saves/showcase_v3_late.fhsave&title=0');
const fps = Number(opt('fps', '0'));
const burn = Number(opt('burn', '0'));      // ms of busy work per frame: a slow machine (the frame-rate cap silences web audio)
const speed = Number(opt('speed', '4'));
const secs = Number(opt('seconds', '10'));
const stall = Number(opt('stall', '0'));   // positive control: a main-thread stall of about N game seconds of simulation

const PROBE = `
(function(){
  // The tap is an AudioWorklet: it runs on the audio thread, so it sees every render quantum even
  // while the main thread is blocked (a ScriptProcessor would drop those blocks unseen).
  const TAP = "class T extends AudioWorkletProcessor{constructor(){super();this.q=0;this.drops=0;this.peak=0;this.prev=0;this.n=0;this.port.onmessage=(e)=>{this.q=0;this.drops=0;this.peak=0;};}" +
    "process(i){const c=i[0]&&i[0][0];if(!c)return true;let m=0;for(let k=0;k<c.length;k++){const v=Math.abs(c[k]);if(v>m)m=v;}" +
    "if(m>this.peak)this.peak=m;if(m===0&&this.prev>1e-4)this.drops++;this.prev=m;this.q++;if(++this.n%200===0)this.port.postMessage({q:this.q,drops:this.drops,peak:this.peak,rate:sampleRate});return true;}}" +
    "registerProcessor('probe-tap',T);";
  const url = URL.createObjectURL(new Blob([TAP], {type: 'application/javascript'}));
  const cn = AudioNode.prototype.connect;
  const st = {q: 0, drops: 0, peak: 0, rate: 48000, ready: false};
  window.__glitch = st;
  window.__glitchReset = () => { if (st.node) st.node.port.postMessage('reset'); st.q = 0; st.drops = 0; st.peak = 0; return 'armed'; };
  // Every node that connects to the destination feeds ONE tap (inputs sum). Godot connects two
  // worklets there (the mixer and a silent position worklet); tapping only one gives wrong results.
  const pending = [];
  let loading = null;
  AudioNode.prototype.connect = function(t, ...r){
    if (t instanceof AudioDestinationNode && !this.__tapped) {
      this.__tapped = true;
      const src = this, c = this.context;
      if (st.node) { cn.call(src, st.node); }
      else {
        pending.push(src);
        if (!loading) loading = c.audioWorklet.addModule(url).then(() => {
          const node = new AudioWorkletNode(c, 'probe-tap');
          const g = c.createGain(); g.gain.value = 0;
          cn.call(node, g); cn.call(g, c.destination);
          node.port.onmessage = (e) => Object.assign(st, e.data);
          st.node = node; st.ready = true;
          for (const s of pending) cn.call(s, node);
        });
      }
    }
    return cn.call(this, t, ...r);
  };
})();`;

if (!fs.existsSync(path.join(dir, 'index.html'))) { console.error('no index.html in ' + dir); process.exit(2); }
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-glitch-'));
for (const f of fs.readdirSync(dir)) {
  const src = path.join(dir, f);
  if (fs.statSync(src).isFile()) { try { fs.linkSync(src, path.join(tmp, f)); } catch { fs.copyFileSync(src, path.join(tmp, f)); } }
}
fs.writeFileSync(path.join(tmp, 'probe.js'), PROBE);
const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8').replace('<head>', '<head><script src="probe.js"></script>');
fs.rmSync(path.join(tmp, 'index.html'));
fs.writeFileSync(path.join(tmp, 'index.html'), html);

const steps = [{ wait: 3 }, ...(fps > 0 ? [{ cmd: `maxfps ${fps}` }] : []), ...(burn > 0 ? [{ cmd: `burn ${burn}` }] : []), { cmd: `speed ${speed}` }, { wait: 4 },
  { eval: `window.__glitchReset()` },
  { wait: secs / 2 }, ...(stall > 0 ? [{ cmd: `fast ${stall}` }] : []), { wait: secs / 2 },
  { wait: 1 }, { eval: `JSON.stringify({fps: window.__fh && window.__fh.fps, g: {q: window.__glitch.q, drops: window.__glitch.drops, peak: window.__glitch.peak, rate: window.__glitch.rate, ready: window.__glitch.ready}})` }];
const stepsFile = path.join(tmp, 'steps.json');
fs.writeFileSync(stepsFile, JSON.stringify(steps));
const r = spawnSync(process.execPath, [path.join(ROOT, 'tools/shoot.mjs'), '--gpu', '--dir', tmp, '--query', query, '--steps', stepsFile, '--wait', '90'],
  { encoding: 'utf8', timeout: 300000 });
fs.rmSync(tmp, { recursive: true, force: true });
const line = (r.stdout || '').split('\n').filter(l => l.includes('JSON.stringify({fps')).pop();
if (!line) { console.error('no measurement\n' + r.stdout + r.stderr); process.exit(2); }
const res = JSON.parse(JSON.parse(line.slice(line.indexOf('-> ') + 3)));
const g = res.g;
const measured = g.q * 128 / (g.rate || 48000);
const db = g.peak > 0 ? (20 * Math.log10(g.peak)).toFixed(1) : '-inf';
console.log(`fps ${res.fps}  measured ${measured.toFixed(1)} s  dropouts ${g.drops}  (${(g.drops / Math.max(measured, 0.1) * 60).toFixed(1)} per minute)  peak ${db} dBFS`);
