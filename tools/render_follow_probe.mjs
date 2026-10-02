// render_follow_probe.mjs (RENDER) - follow-view smoothness probe in the web build on the real GPU
// (headless Chrome through tools/shoot.mjs --gpu; nothing opens on the desktop).
// Runs world_view debug "fprobe" (presentation/fx_follow_probe.gd) for each case and writes
// <out>/<case>.json (metrics) and <out>/<case>.csv (every frame).
//
//   node tools/render_follow_probe.mjs --out build/web_render/fprobe_before [--cases in1,in4,out1,out4,dome1]
//        [--secs 20] [--strip art/critic_input/render/x_strip]   (6 frames of the first case, 0.25 s apart)
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && i + 1 < args.length ? args[i + 1] : d; };
const OUT = path.resolve(ROOT, opt('out', 'build/web_render/fprobe'));
const SECS = Number(opt('secs', '20'));
const STRIP = opt('strip', '');
const CASES = {
  in1: { save: 'showcase_v3_late.fhsave', want: 'in', speed: 1 },
  in4: { save: 'showcase_v3_late.fhsave', want: 'in', speed: 4 },
  out1: { save: 'showcase_v3_late.fhsave', want: 'out', speed: 1 },
  out4: { save: 'showcase_v3_late.fhsave', want: 'out', speed: 4 },
  dome1: { save: 'dome_v5.fhsave', want: 'b:super_dome', speed: 1 },
  apt1: { save: 'civic_v5.fhsave', want: 'b:apartment', speed: 1 },
};
const list = opt('cases', 'in1,in4,out1,out4,dome1').split(',');
fs.mkdirSync(OUT, { recursive: true });
const summary = {};
for (const name of list) {
  const c = CASES[name];
  if (!c) { console.log('unknown case', name); continue; }
  const steps = [
    { eval: `window.__fhr.cmd('loadurl ${c.save}')` }, { wait: 14 },
    { cmd: `speed ${c.speed}` }, { wait: 2 },
    { eval: `(window.__fhr.cmd('fprobe start ${SECS} ${c.want}'), window.__fhr.last)` }, { wait: SECS + 1.5 },
    { eval: `(window.__fhr.cmd('fprobe get'), window.__fhr.last)` },
    { eval: `(window.__fhr.cmd('fprobe csv'), window.__fhr.last)` },
  ];
  if (STRIP && name === list[0]) {
    steps.push({ eval: `window.__fhr.cmd('fprobe start 4 ${c.want}')` }, { wait: 1.2 });
    for (let i = 0; i < 6; i++) steps.push({ shot: path.resolve(ROOT, `${STRIP}_${i}.png`) }, { wait: 0.1 });
    steps.push({ eval: `(window.__fhr.cmd('fprobe get'), window.__fhr.last)` });
  }
  const sf = path.join(os.tmpdir(), `render_fprobe_${name}.json`);
  fs.writeFileSync(sf, JSON.stringify(steps));
  const r = spawnSync('node', [path.join(ROOT, 'tools', 'shoot.mjs'), '--dir', path.resolve(ROOT, opt('dir', 'build/web_render')), '--gpu', '--wait', '120', '--settle', '2',
    '--query', 'title=0', '--steps', sf], { encoding: 'utf8', maxBuffer: 64 << 20, env: { ...process.env, FH_ORCHESTRATOR: '1' } });
  fs.writeFileSync(path.join(OUT, `${name}.log`), (r.stdout || '') + '\n--- stderr\n' + (r.stderr || ''));
  const lines = (r.stdout || '').split('\n');
  const grab = (key) => { const l = lines.filter(x => x.startsWith(`eval (window.__fhr.cmd('fprobe ${key}`)); return l.map(x => JSON.parse(x.slice(x.indexOf('-> ') + 3))); };
  const gets = grab('get');
  const csv = grab('csv')[0] || '';
  let rep = {};
  try { rep = JSON.parse(gets[0]) || {}; } catch { rep = { error: String(gets[0]) }; }
  if (!rep || typeof rep !== 'object') rep = { error: String(gets[0]) };
  rep.case = name; rep.save = c.save; rep.speed = c.speed;
  fs.writeFileSync(path.join(OUT, `${name}.json`), JSON.stringify(rep, null, 1));
  fs.writeFileSync(path.join(OUT, `${name}.csv`), csv);
  summary[name] = rep;
  const s = rep.straight || {}; const w = rep.walk || {};
  console.log(`${name}: fps ${rep.fps} frames ${rep.frames} hops ${rep.hops} | straight n ${s.n} head ${s.head_jit_px}px cam ${s.cam_jerk_mm}mm yaw ${s.cam_yaw_deg}deg spd ${s.speed_rip_pct}% byaw ${s.yaw_rip_deg}deg | walk n ${w.n} head ${w.head_jit_px}px cam ${w.cam_jerk_mm}mm spd ${w.speed_rip_pct}% | pops ${rep.pops} pulled ${rep.pulled_frames} clip_sw/min ${rep.clip_sw_min} occluded ${rep.occluded_frames} wall_centre ${rep.wall_centre_frames} off_screen ${rep.off_screen_frames}`);
}
fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 1));
