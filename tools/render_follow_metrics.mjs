// render_follow_metrics.mjs (RENDER) - the follow-view smoothness metrics from fprobe CSV files
// (tools/render_follow_probe.mjs writes them). One analyser for the before and after runs.
//   node tools/render_follow_metrics.mjs <dir> [<dir2> ...]   -> a table per case
// Steady walking: frames i-6..i+6 all walk or run (loco) at over 0.5 m/s game speed, same person,
// no camera cut (a new person, a jump over 2 m, the first 1 s). "straight": also the body yaw
// stays within 4 deg over the window.
// Second differences are per 1/60 s (each step scaled by (1/60) / its frame time), so a late frame of
// the browser is not a jerk; "raw" = the plain per-frame second difference.
import fs from 'node:fs';
import path from 'node:path';

const H = 1 / 60;
const ad = (a, b) => { let d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; };
const rms = (a) => a.length ? Math.sqrt(a.reduce((s, x) => s + x * x, 0) / a.length) : 0;

export function analyse(file) {
  const L = fs.readFileSync(file, 'utf8').trim().split('\n');
  if (L.length < 30) return null;
  const hd = L[0].split(',');
  const R = L.slice(1).map(l => { const v = l.split(','); const o = {}; hd.forEach((h, i) => o[h] = isNaN(Number(v[i])) ? v[i] : Number(v[i])); return o; });
  // cuts: a new person or a jump over 2 m, and 1 s after it
  let cutUntil = -1;
  for (let i = 0; i < R.length; i++) {
    const r = R[i];
    if (i > 0 && (r.id !== R[i - 1].id || Math.hypot(r.bx - R[i - 1].bx, r.bz - R[i - 1].bz) > 2)) cutUntil = r.t + 1.0;
    r.cutx = r.cut === 1 || r.t < cutUntil;
  }
  // mode 'steady': straight AND the walker's speed (game m/s) within 5 % over the window.
  const steady = (i, straight, flat = false) => {
    if (i < 6 || i + 6 >= R.length) return false;
    for (let j = i - 6; j <= i + 6; j++) {
      const r = R[j];
      if (r.cutx || !(r.key === 'walk' || r.key === 'run') || r.v < 0.5 || r.id !== R[i].id) return false;
      if (straight && Math.abs(ad(R[i - 6].yaw, r.yaw)) > 4 * Math.PI / 180) return false;
      if (flat && Math.abs(r.v - R[i].v) > 0.05 * R[i].v) return false;
    }
    return true;
  };
  const out = { frames: R.length, secs: +(R[R.length - 1].t).toFixed(1) };
  const dts = R.map(r => r.dt);
  out.fps = +(R.length / dts.reduce((a, b) => a + b, 0)).toFixed(1);
  out.late_frames = dts.filter(d => d > 0.025).length;
  let pops = 0, pulled = 0, sw = 0, moveT = 0, flick = 0, lastSw = -9;
  for (let i = 1; i < R.length; i++) {
    const r = R[i], p = R[i - 1];
    if (r.id !== p.id) lastSw = -9;
    if (r.cutx || r.id !== p.id) continue;
    if (r.pull < 0.98) pulled++;
    if (Math.abs(r.pull - p.pull) > 0.08) pops++;
    if (r.key !== p.key) { if (r.t - lastSw < 0.6) flick++; lastSw = r.t; }
    if (r.v > 0.3 || p.v > 0.3) { moveT += r.dt; if (r.key !== p.key) sw++; }
  }
  Object.assign(out, { pops, pulled_frames: pulled, move_s: +moveT.toFixed(1), clip_sw: sw, clip_sw_min: +(sw / Math.max(moveT / 60, 1e-3)).toFixed(1), flicker: flick });
  // clip changes inside steady-speed windows (the target: none)
  let ssw = 0;
  for (let i = 1; i < R.length; i++) if (R[i].key !== R[i - 1].key && R[i].id === R[i - 1].id && steady(i, false, true)) ssw++;
  out.steady_clip_sw = ssw;
  for (const mode of ['walk', 'straight', 'steady']) {
    const hj = [], hr = [], cj = [], cr = [], cy = [], yr = [], sr = [], ey = [];
    let n = 0;
    for (let i = 1; i < R.length - 1; i++) {
      if (!steady(i, mode !== 'walk', mode === 'steady')) continue;
      n++;
      const a = R[i - 1], b = R[i], c = R[i + 1];
      const k1 = H / Math.max(b.dt, 1e-3), k2 = H / Math.max(c.dt, 1e-3);
      hj.push(Math.hypot((c.sx - b.sx) * k2 - (b.sx - a.sx) * k1, (c.sy - b.sy) * k2 - (b.sy - a.sy) * k1));
      hr.push(Math.hypot(c.sx - 2 * b.sx + a.sx, c.sy - 2 * b.sy + a.sy));
      cj.push(1000 * Math.hypot((c.cx - b.cx) * k2 - (b.cx - a.cx) * k1, (c.cy - b.cy) * k2 - (b.cy - a.cy) * k1, (c.cz - b.cz) * k2 - (b.cz - a.cz) * k1));
      cr.push(1000 * Math.hypot(c.cx - 2 * b.cx + a.cx, c.cy - 2 * b.cy + a.cy, c.cz - 2 * b.cz + a.cz));
      cy.push(180 / Math.PI * (ad(b.cyaw, c.cyaw) * k2 - ad(a.cyaw, b.cyaw) * k1));
      yr.push(180 / Math.PI * (ad(b.yaw, c.yaw) * k2 - ad(a.yaw, b.yaw) * k1));
      ey.push(1000 * ((c.eye - b.eye) * k2 - (b.eye - a.eye) * k1));
      const v1 = Math.hypot(b.bx - a.bx, b.bz - a.bz) / Math.max(b.dt, 1e-4);
      let ds = 0, ts = 0;
      for (let j = i - 5; j <= i + 6; j++) { ds += Math.hypot(R[j].bx - R[j - 1].bx, R[j].bz - R[j - 1].bz); ts += R[j].dt; }
      const vm = ds / Math.max(ts, 1e-4);
      if (vm > 0.2) sr.push((v1 - vm) / vm * 100);
    }
    const f = (x, d = 3) => +x.toFixed(d);
    out[mode] = { n, head_jit_px: f(rms(hj)), head_jit_raw_px: f(rms(hr)), cam_jerk_mm: f(rms(cj)), cam_jerk_raw_mm: f(rms(cr)), cam_yaw_deg: f(rms(cy), 4),
      speed_rip_pct: f(rms(sr), 2), yaw_rip_deg: f(rms(yr), 4) };
  }
  return out;
}

if (process.argv[1] && process.argv[1].endsWith('render_follow_metrics.mjs')) {
  for (const dir of process.argv.slice(2)) {
    for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.csv')).sort()) {
      const m = analyse(path.join(dir, f));
      if (!m) { console.log(dir, f, 'no data'); continue; }
      const s = m.straight, w = m.walk;
      console.log(`${path.basename(dir)} ${f.replace('.csv', '')}: fps ${m.fps} late ${m.late_frames} | STRAIGHT n ${s.n} head ${s.head_jit_px}px (raw ${s.head_jit_raw_px}) cam ${s.cam_jerk_mm}mm (raw ${s.cam_jerk_raw_mm}) camyaw ${s.cam_yaw_deg}deg speed ${s.speed_rip_pct}% yaw ${s.yaw_rip_deg}deg | WALK n ${w.n} head ${w.head_jit_px}px cam ${w.cam_jerk_mm}mm speed ${w.speed_rip_pct}% | pops ${m.pops} pulled ${m.pulled_frames} | STEADY n ${m.steady.n} head ${m.steady.head_jit_px}px cam ${m.steady.cam_jerk_mm}mm speed ${m.steady.speed_rip_pct}% clip_sw ${m.steady_clip_sw} | clip_sw/min ${m.clip_sw_min} (${m.clip_sw} in ${m.move_s}s) flicker(<0.6s) ${m.flicker}`);
    }
  }
}
