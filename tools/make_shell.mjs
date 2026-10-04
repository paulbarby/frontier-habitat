// make_shell.mjs — builds templates/web_shell.html (the web export's HTML shell with the
// loading screen) from templates/web_shell.src.html: inlines templates/loader_bg.jpg as a data
// URI and writes the version from project.godot. Run it after changing either source file:
//   node tools/make_shell.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = fs.readFileSync(path.join(ROOT, 'templates/web_shell.src.html'), 'utf8');
const bg = fs.readFileSync(path.join(ROOT, 'templates/loader_bg.jpg')).toString('base64');
const proj = fs.readFileSync(path.join(ROOT, 'project.godot'), 'utf8');
const version = (proj.match(/config\/version="([^"]+)"/) || [, '?'])[1];
const out = src.replace('@BG@', 'data:image/jpeg;base64,' + bg).replace('@VERSION@', version).replaceAll('@PACK_URL@', process.env.FH_PACK_URL || '');
fs.writeFileSync(path.join(ROOT, 'templates/web_shell.html'), out);
console.log(`templates/web_shell.html written (${(out.length / 1024).toFixed(0)} KB, version ${version})`);
