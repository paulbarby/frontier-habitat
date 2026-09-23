// tour.mjs — a fixed set of review screenshots of a web build, all invisible.
// usage: node tools/tour.mjs <build dir> <out dir> [save=res://content/saves/showcase_day9.fhsave]
// It runs three sessions: the title screen, a day tour through every screen, and a night tour.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [dir = 'build/web', out = 'docs/shots/tour', save = 'res://content/saves/showcase_day9.fhsave'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const shoot = (name, query, steps) => {
  const stepsFile = path.join(out, `_${name}.json`);
  fs.writeFileSync(stepsFile, JSON.stringify(steps.map(s => s.shot ? { shot: path.join(out, s.shot) } : s)));
  const r = spawnSync('node', ['tools/shoot.mjs', '--gpu', '--dir', dir, '--query', query, '--steps', stepsFile, '--wait', '60', '--settle', '4'], { encoding: 'utf8' });
  process.stdout.write(r.stdout + r.stderr);
  fs.rmSync(stepsFile, { force: true });
};

shoot('title', 'title=1', [{ wait: 3 }, { shot: '01_title.png' }]);

shoot('day', `load=${save}&speed=1`, [
  { cmd: 'zoom 75' }, { cmd: 'pitch 50' }, { wait: 2.5 }, { shot: '02_colony_wide.png' },
  { cmd: 'zoom 28' }, { cmd: 'pitch 38' }, { cmd: 'select greenhouse' }, { wait: 2.5 }, { shot: '03_close_greenhouse.png' },
  { cmd: 'select habitat' }, { wait: 2 }, { shot: '04_inspector_habitat.png' },
  { cmd: 'close' }, { cmd: 'zoom 60' }, { cmd: 'overlay power' }, { wait: 2 }, { shot: '05_overlay_power.png' }, { cmd: 'overlay off' },
  { cmd: 'open research' }, { wait: 1.5 }, { shot: '06_research.png' }, { cmd: 'close' },
  { cmd: 'open goals' }, { wait: 1.5 }, { shot: '07_goals.png' }, { cmd: 'close' },
  { cmd: 'open awards' }, { wait: 1.5 }, { shot: '08_awards.png' }, { cmd: 'close' },
  { cmd: 'open dashboard' }, { wait: 1.5 }, { shot: '09_dashboard.png' }, { cmd: 'close' },
  { cmd: 'open inventory' }, { wait: 1.5 }, { shot: '10_inventory.png' }, { cmd: 'close' },
  { eval: 'JSON.stringify({tick: window.__fh.tick, day: window.__fh.day, fps: window.__fh.fps})' },
]);

shoot('night', `load=${save}&speed=1&fast=260`, [
  { cmd: 'zoom 55' }, { cmd: 'pitch 42' }, { wait: 4 }, { shot: '11_night.png' },
  { cmd: 'zoom 24' }, { cmd: 'select kitchen' }, { wait: 3 }, { shot: '12_night_close.png' },
]);
console.log('tour written to', path.resolve(out));
