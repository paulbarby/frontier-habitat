// render_export.mjs (RENDER) — web export from a private MIRROR of the project, so a file
// another agent is half-way through editing cannot break my build. The mirror is refreshed
// with robocopy, parse-checked there, and exported with the mirror's own tools/godot.mjs
// (its own editor lock) to <project>/build/web_render. Retries while the check fails on
// files that are not RENDER's.
//   node tools/render_export.mjs [--tries 6] [--keep-sim]
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MIRROR = path.join(os.tmpdir(), 'fh_render_mirror');
const OUT = path.join(ROOT, 'build', 'web_render');
const args = process.argv.slice(2);
const tries = Number(args[args.indexOf('--tries') + 1] || 6) || 6;
const DIRS = ['.godot', 'assets', 'content', 'presentation', 'shaders', 'sim', 'ui', 'tools', 'templates'];
const FILES = ['project.godot', 'export_presets.cfg', 'main.tscn', 'icon.svg'];

function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
function mirror() {
  fs.mkdirSync(MIRROR, { recursive: true });
  for (const d of DIRS) {
    const src = path.join(ROOT, d);
    if (!fs.existsSync(src)) continue;
    const xd = d === '.godot' ? ['/XD', 'editor', 'shader_cache'] : [];
    spawnSync('robocopy', [src, path.join(MIRROR, d), '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1', ...xd], { encoding: 'utf8' });
  }
  for (const f of FILES) {
    const src = path.join(ROOT, f);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(MIRROR, f));
  }
}
function run(cmd) {
  const r = spawnSync('node', [path.join(MIRROR, 'tools', 'godot.mjs'), ...cmd], { cwd: MIRROR, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  return { code: r.status ?? 1, out: (r.stdout || '') + (r.stderr || '') };
}

for (let i = 1; i <= tries; i++) {
  mirror();
  const c = run(['check']);
  // Godot 4.4.1 can crash at EXIT (0xC0000005, leaked GDScript cycles in the UI theme scripts)
  // after every script parsed: the check's own verdict line decides, not the exit code.
  const parsed = /checked \d+ scripts, 0 failed/.test(c.out) && !/^FAILED |SCRIPT ERROR|Parse Error/m.test(c.out);
  if (c.code === 0 || parsed) {
    // Furniture grids (fx_nav) for the models in this mirror: never stale in my build.
    // Import first: the bake must see the same imported models as the export (a .glb newer than the
    // mirror's import cache was baked from the old import and its grid did not match, 2026-09-30).
    run(['import']);
    const b = run(['script', 'res://tools/render_nav_bake.gd']);
    console.log((b.out.match(/render_nav_bake:[^\n]*/) || ['nav bake: no output'])[0]);
    const e = run(['export', OUT]);
    const pck = path.join(OUT, 'index.pck');
    if (fs.existsSync(pck)) console.log('pck ' + (fs.statSync(pck).size / 1048576).toFixed(1) + ' MB');
    console.log(e.out.split(/\r?\n/).filter(l => /exported|EXPORT FAILED|SCRIPT ERROR|Parse Error/.test(l)).join('\n'));
    const ok = fs.existsSync(path.join(OUT, 'index.pck'));
    console.log(ok ? `ok (try ${i}, mirror ${MIRROR})` : 'export failed');
    process.exit(ok ? 0 : 1);
  }
  const bad = c.out.split(/\r?\n/).filter(l => /^FAILED /.test(l));
  const mine = bad.filter(l => /presentation\/(world_view|models|camera_rig|fx_)|shaders\//.test(l));
  console.log(`try ${i}: check failed (${bad.length} scripts${mine.length ? ', INCLUDING RENDER files' : ''}): ${bad.slice(0, 4).join(' | ')}`);
  if (mine.length && bad.length === mine.length) { console.log(c.out); process.exit(1); }
  sleep(45000);
}
process.exit(1);
