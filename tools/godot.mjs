// godot.mjs — the ONE way to run Godot for this project. It never opens a window.
// Editor-mode operations (import, export) hold a lock, because two Godot editors
// importing the same project at once corrupt .godot/imported.
//
// usage:
//   node tools/godot.mjs import                 re-import changed assets (locked)
//   node tools/godot.mjs export <outdir>        web export to <outdir>/index.html (locked; imports first)
//   node tools/godot.mjs check                  parse every .gd file; prints errors; exit 1 on any
//   node tools/godot.mjs test [filter]          headless test suite (tests/run_tests.gd)
//   node tools/godot.mjs script <res://x.gd> [args...]   run a headless SceneTree script
//
// Agents: export to your OWN folder (build/web_<you>/). Only the orchestrator writes build/web/.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GODOT = 'D:/Tools/Godot_v4.4.1-stable_win64_console.exe';
const LOCK = path.join(ROOT, '.godot_editor.lock');
const [cmd, ...rest] = process.argv.slice(2);

function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }

function withLock(fn) {
  const t0 = Date.now();
  for (;;) {
    try { fs.mkdirSync(LOCK); break; } catch {
      // A lock older than 20 minutes is stale (a crashed run).
      try { if (Date.now() - fs.statSync(LOCK).mtimeMs > 20 * 60 * 1000) { fs.rmSync(LOCK, { recursive: true, force: true }); continue; } } catch {}
      if (Date.now() - t0 > 30 * 60 * 1000) { console.error('lock wait timed out'); process.exit(9); }
      if ((Date.now() - t0) % 30000 < 1000) console.log('waiting for the Godot editor lock...');
      sleep(1000);
    }
  }
  fs.writeFileSync(path.join(LOCK, 'owner.txt'), `${process.pid} ${new Date().toISOString()} ${cmd} ${rest.join(' ')}\n`);
  try { return fn(); } finally { fs.rmSync(LOCK, { recursive: true, force: true }); }
}

function run(args, { quiet = false } = {}) {
  const r = spawnSync(GODOT, args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const noise = /Parameter "t" is null|^\s*at: (cleanup|clear)|resources still in use|ObjectDB instances leaked|^Godot Engine v|^\s*$/;
  const lines = out.split(/\r?\n/).filter(l => !noise.test(l));
  if (!quiet) console.log(lines.join('\n'));
  return { code: r.status ?? 1, lines };
}

switch (cmd) {
  case 'import':
    withLock(() => run(['--headless', '--path', ROOT, '--import'], { quiet: true }));
    console.log('import done');
    break;
  case 'export': {
    const out = path.resolve(ROOT, rest[0] || 'build/web');
    if (path.resolve(out) === path.resolve(ROOT, 'build/web') && !process.env.FH_ORCHESTRATOR) {
      console.error('build/web belongs to the orchestrator. Export to build/web_<you>/ instead.');
      process.exit(2);
    }
    fs.mkdirSync(out, { recursive: true });
    for (const f of fs.readdirSync(out)) if (f.startsWith('index.')) fs.rmSync(path.join(out, f), { force: true });
    const r = withLock(() => {
      run(['--headless', '--path', ROOT, '--import'], { quiet: true });
      return run(['--headless', '--path', ROOT, '--export-release', 'Web', path.join(out, 'index.html')], { quiet: true });
    });
    const errs = r.lines.filter(l => /ERROR|SCRIPT ERROR|Parse Error/i.test(l));
    if (errs.length) console.log(errs.slice(0, 40).join('\n'));
    const ok = fs.existsSync(path.join(out, 'index.pck'));
    console.log(ok ? `exported to ${out} (pck ${(fs.statSync(path.join(out, 'index.pck')).size / 1e6).toFixed(1)} MB)` : 'EXPORT FAILED');
    process.exit(ok ? 0 : 1);
  }
  case 'check': {
    const r = run(['--headless', '--path', ROOT, '--script', 'res://tools/check_scripts.gd'], { quiet: true });
    const bad = r.lines.filter(l => /SCRIPT ERROR|Parse Error|^FAILED |^ERROR/.test(l));
    console.log(r.lines.filter(l => /^checked /.test(l)).join('\n'));
    if (bad.length || r.code !== 0) { console.log(bad.slice(0, 60).join('\n')); process.exit(1); }
    break;
  }
  case 'test': {
    const r = run(['--headless', '--path', ROOT, '--script', 'res://tests/run_tests.gd', ...(rest.length ? ['--', ...rest] : [])], { quiet: true });
    console.log(r.lines.filter(l => !l.startsWith('RUN ')).join('\n'));
    process.exit(r.code);
  }
  case 'script': {
    const [script, ...sargs] = rest;
    const r = run(['--headless', '--path', ROOT, '--script', script, ...(sargs.length ? ['--', ...sargs] : [])]);
    process.exit(r.code);
  }
  default:
    console.log('usage: node tools/godot.mjs import | export <outdir> | check | test [filter] | script <res://x.gd> [args]');
    process.exit(2);
}
