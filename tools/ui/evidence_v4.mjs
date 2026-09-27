// evidence_v4.mjs — screenshots of every screen in the version-4 style (critic round 15), by day
// and at night, at 1600x900 and 1280x720, from the web build. Nothing opens on the desktop.
//   node tools/ui/evidence_v4.mjs [--dir build/web_ui] [--out docs/shots/v4] [--only 1600x900]
// Writes <out>/<size>_<day|night>_<name>.png, plus <out>/<size>_scale80_*.png and _scale125_*.png.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const DIR = opt('dir', 'build/web_ui');
const OUT = path.resolve(opt('out', 'docs/shots/v4'));
const ONLY = opt('only', '');
fs.mkdirSync(OUT, { recursive: true });
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fh-ev4-'));
const P = (s) => path.join(OUT, s).replace(/\\/g, '/');
const TIME = { day: 180, night: 450 };
const SAVE = 'load=res://content/saves/showcase_v3_late.fhsave&debug=1';

function playSteps(size, tod) {
  const n = (s) => ({ shot: P(`${size}_${tod}_${s}.png`) });
  const t = { cmd: `time ${TIME[tod]}` };
  const open = (name, shot, tab) => [{ cmd: `open ${name}` }, ...(tab ? [{ cmd: `tab ${tab}` }] : []), { wait: 1.5 }, n(shot), { cmd: 'close' }, { wait: 0.4 }];
  return [
    { wait: 3 }, { cmd: 'speed 0' }, t,
    { cmd: 'select research_lab' }, { wait: 2 }, n('hud_inspector_building'),
    { cmd: 'agent 3' }, { wait: 1.5 }, n('hud_inspector_colonist'),
    { cmd: 'closeall' }, { cmd: 'find lab' }, { wait: 1.5 }, n('hud_find'),
    { cmd: 'findmark habitat' }, { cmd: 'closeall' }, { wait: 1.5 }, n('hud_find_marks'), { cmd: 'findmark off' },
    { cmd: 'closeall' }, { cmd: 'toast Saved to slot 1.' }, { cmd: 'award first_breath' }, { wait: 1 }, n('hud_toast_award'),
    { wait: 4 },
    ...open('goals', 'screen_goals'),
    ...open('research', 'screen_research_tree'),
    ...open('research', 'screen_research_labs', 'labs'),
    ...open('dashboard', 'screen_dashboard_overview'),
    ...open('dashboard', 'screen_dashboard_food', 'food'),
    ...open('dashboard', 'screen_dashboard_hazards', 'hazards'),
    ...open('inventory', 'screen_inventory'),
    ...open('colonists', 'screen_colonists'),
    ...open('awards', 'screen_awards'),
    ...open('menu', 'screen_menu'),
    ...open('settings', 'screen_settings'),
    ...open('saveload', 'screen_saveload'),
    ...open('help', 'screen_help'),
    ...open('newcolony', 'screen_newcolony'),
    // Ships: a powered landing pad, then a trader and a shuttle (as tools/ui/test_ships_ui.gd).
    { eval: "(function(){window.__fh.cmd('findspot landing_pad 1 40'); var p=window.__fh.last; window.__fh.cmd('place landing_pad 1 '+p); return p+' -> '+window.__fh.last;})()" },
    { cmd: 'speed 1' }, { cmd: 'fast 400' },
    { eval: "(function(){window.__fh.cmd('idof landing_pad'); var id=window.__fh.last; window.__fh.cmd('cable '+id); return id+' -> '+window.__fh.last;})()" },
    { cmd: 'fast 200' }, { cmd: 'ship trader 30' }, { cmd: 'ship shuttle 90' }, { cmd: 'speed 0' }, t, { wait: 2 },
    n('hud_traffic_panel'),
    ...open('shuttle', 'screen_shuttle'),
    { cmd: 'speed 1' }, { cmd: 'fast 60' }, { cmd: 'speed 0' }, t,
    { eval: "(function(){window.__fh.cmd('traffic'); var s=String(window.__fh.last); var id=(s.split('| ')[1]||'').split(' ')[0]; window.__fh.cmd('trade '+id+' sell biomass 1'); return id+' -> '+window.__fh.last;})()" },
    { cmd: 'trade' }, { wait: 1.5 }, n('screen_trade'), { cmd: 'close' },
    { cmd: 'open visitors' }, { wait: 1.5 }, n('screen_colonists_visitors'), { cmd: 'close' },
    // Last: the end screens stay open over the game.
    ...open('victory', 'screen_victory'),
    { cmd: 'open lost' }, { wait: 1.5 }, n('screen_lost'),
  ];
}

// Find, marks, label layer and the minimap family icons (V4_DESIGN §3.4).
function findSteps(size, tod) {
  const n = (s) => ({ shot: P(`${size}_${tod}_${s}.png`) });
  return [{ wait: 3 }, { cmd: 'speed 0' }, { cmd: `time ${TIME[tod]}` },
    { cmd: 'find lab' }, { wait: 1.5 }, n('hud_find'),
    { cmd: 'closeall' }, { cmd: 'findmark habitat' }, { wait: 1.5 }, n('hud_find_marks'), { cmd: 'findmark off' },
    { cmd: 'findlabels all' }, { cmd: 'minimap zoom' }, { wait: 1.5 }, n('hud_find_labels_minimap_icons'), { cmd: 'findlabels off' }, { cmd: 'minimap whole' },
    { cmd: 'open newcolony' }, { wait: 1.5 }, n('screen_newcolony'), { cmd: 'close' }];
}

function titleSteps(size, tod) {
  const n = (s) => ({ shot: P(`${size}_${tod}_${s}.png`) });
  return [{ wait: 4 }, { cmd: `time ${TIME[tod]}` }, { wait: 2 }, n('title'), { cmd: 'open settings' }, { wait: 1.5 }, n('title_settings')];
}

function scaleSteps(size, scale) {
  const n = (s) => ({ shot: P(`${size}_scale${Math.round(scale * 100)}_${s}.png`) });
  return [{ wait: 3 }, { cmd: 'speed 0' }, { cmd: `uiscale ${scale}` }, { cmd: 'time 180' }, { wait: 1 },
    { cmd: 'select research_lab' }, { wait: 2 }, n('hud_inspector'), { cmd: 'closeall' },
    { cmd: 'open research' }, { wait: 1.5 }, n('screen_research'), { cmd: 'close' },
    { cmd: 'open settings' }, { wait: 1.5 }, n('screen_settings'), { cmd: 'close' }, { cmd: 'uiscale 1' }];
}

function shoot(size, query, steps, tag) {
  const f = path.join(tmp, `${tag}.json`);
  fs.writeFileSync(f, JSON.stringify(steps, null, 1));
  const r = spawnSync(process.execPath, ['tools/shoot.mjs', '--gpu', '--dir', DIR, '--size', size, '--query', query, '--steps', f, '--wait', '90'], { encoding: 'utf8', timeout: 900000 });
  const shots = (r.stdout || '').split('\n').filter(l => l.startsWith('shot ')).length;
  const errs = (r.stdout + r.stderr).split('\n').filter(l => /error|refused|unknown/i.test(l)).slice(0, 6);
  console.log(`${tag}: ${shots} shots${errs.length ? '  !! ' + errs.join(' | ') : ''}`);
}

const FIND_ONLY = args.includes('--find-only');
for (const size of ['1600x900', '1280x720']) {
  if (FIND_ONLY) { if (!ONLY || ONLY === size) for (const tod of ['day', 'night']) shoot(size, SAVE, findSteps(size, tod), `${size}_${tod}_find`); continue; }
  if (ONLY && ONLY !== size) continue;
  for (const tod of ['day', 'night']) {
    shoot(size, SAVE, playSteps(size, tod), `${size}_${tod}_play`);
    shoot(size, SAVE, findSteps(size, tod), `${size}_${tod}_find`);
    shoot(size, 'title=1', titleSteps(size, tod), `${size}_${tod}_title`);
  }
  if (size === '1600x900') for (const sc of [0.8, 1.25]) shoot(size, SAVE, scaleSteps(size, sc), `${size}_scale${sc}`);
}
