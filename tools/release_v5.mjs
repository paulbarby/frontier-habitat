// release_v5.mjs (orchestrator) - builds the 5.0 release for GitHub Pages + Cloudflare R2.
// GitHub refuses files over 100 MB, and index.pck is about 186 MB, so index.pck is served from a public
// Cloudflare R2 bucket; every other file (index.html, index.js, index.wasm 43.7 MB, icons) stays on GitHub Pages.
//
//   FH_PACK_URL=https://<public-r2-host>/frontier-habitat/5.0.0/index.pck node tools/release_v5.mjs build
//   node tools/release_v5.mjs upload <bucket>        (needs `npx wrangler login` done by Paul once)
//   FH_PACK_URL=... node tools/release_v5.mjs verify  (HTTP 200, size, CORS header on the R2 file)
//
// build:  writes the shell with FH_PACK_URL, exports to build/web, moves build/web/index.pck to
//         build/release_pack/index.pck (git-ignored; build/web/index.pck is git-ignored too).
// upload: puts build/release_pack/index.pck into R2 at frontier-habitat/<version>/index.pck.
// verify: checks the public URL answers 200 with the right size and Access-Control-Allow-Origin.
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..');
const version = (fs.readFileSync(path.join(ROOT, 'project.godot'), 'utf8').match(/config\/version="([^"]+)"/) || [])[1] || '0';
const cmd = process.argv[2];
const run = (c, env = {}) => execSync(c, { cwd: ROOT, stdio: 'inherit', env: { ...process.env, FH_ORCHESTRATOR: '1', ...env } });
const packOut = path.join(ROOT, 'build', 'release_pack', 'index.pck');

if (cmd === 'build') {
  if (!process.env.FH_PACK_URL) { console.error('set FH_PACK_URL to the public R2 URL of index.pck'); process.exit(2); }
  run('node tools/make_shell.mjs');
  run('node tools/godot.mjs export build/web');
  fs.mkdirSync(path.dirname(packOut), { recursive: true });
  fs.renameSync(path.join(ROOT, 'build', 'web', 'index.pck'), packOut);
  run('node tools/make_shell.mjs', { FH_PACK_URL: '' });   // the working copy goes back to a local pack
  console.log(`release ${version}: build/web ready (no pck), pack at ${packOut} (${(fs.statSync(packOut).size / 1e6).toFixed(1)} MB)`);
} else if (cmd === 'upload') {
  const bucket = process.argv[3];
  if (!bucket) { console.error('usage: release_v5.mjs upload <bucket>'); process.exit(2); }
  run(`npx wrangler r2 object put ${bucket}/frontier-habitat/${version}/index.pck --file "${packOut}" --content-type application/octet-stream --remote`);
} else if (cmd === 'verify') {
  const url = process.env.FH_PACK_URL;
  const r = await fetch(url, { method: 'HEAD', headers: { Origin: 'https://paulbarby.github.io' } });
  const size = Number(r.headers.get('content-length') || 0);
  const cors = r.headers.get('access-control-allow-origin');
  const want = fs.existsSync(packOut) ? fs.statSync(packOut).size : 0;
  console.log(`status ${r.status}, size ${size} (local ${want}), CORS ${cors}`);
  process.exit(r.status === 200 && (!want || size === want) && cors ? 0 : 1);
} else {
  console.error('usage: release_v5.mjs build | upload <bucket> | verify');
  process.exit(2);
}
