// fetch_web_templates.mjs
// Reads ONLY the web export templates out of the official Godot export-template
// archive (a 1.2 GB zip) with HTTP range requests. Nothing else is downloaded.
// usage: node tools/fetch_web_templates.mjs
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const VERSION = '4.4.1-stable';
const URL_TPZ = `https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_export_templates.tpz`;
const WANT = ['templates/web_nothreads_release.zip', 'templates/web_nothreads_debug.zip', 'templates/version.txt'];
const DEST = path.join(process.env.APPDATA, 'Godot', 'export_templates', '4.4.1.stable');

async function range(start, end) {
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const r = await fetch(URL_TPZ, { headers: { Range: `bytes=${start}-${end}` }, redirect: 'follow' });
      if (r.status !== 206) throw new Error(`expected 206, got ${r.status}`);
      const buf = Buffer.from(await r.arrayBuffer());
      if (buf.length !== end - start + 1) throw new Error(`short read ${buf.length} of ${end - start + 1}`);
      return buf;
    } catch (e) {
      if (attempt === 4) throw e;
      console.log(`  retry ${attempt}: ${e.message}`);
      await new Promise(res => setTimeout(res, 1500 * attempt));
    }
  }
}

const head = await fetch(URL_TPZ, { method: 'HEAD', redirect: 'follow' });
const size = Number(head.headers.get('content-length'));
console.log(`archive ${URL_TPZ}\nsize ${size} bytes`);

// End of central directory record.
const tailLen = Math.min(size, 65557);
const tail = await range(size - tailLen, size - 1);
let eocd = -1;
for (let i = tail.length - 22; i >= 0; i--) if (tail.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
if (eocd < 0) throw new Error('end-of-central-directory record not found');
const cdSize = tail.readUInt32LE(eocd + 12), cdOffset = tail.readUInt32LE(eocd + 16);
if (cdOffset === 0xffffffff) throw new Error('zip64 archive: not supported by this script');
const cd = await range(cdOffset, cdOffset + cdSize - 1);

const entries = new Map();
for (let p = 0; p + 46 <= cd.length && cd.readUInt32LE(p) === 0x02014b50;) {
  const method = cd.readUInt16LE(p + 10), crc = cd.readUInt32LE(p + 16);
  const csize = cd.readUInt32LE(p + 20), usize = cd.readUInt32LE(p + 24);
  const nlen = cd.readUInt16LE(p + 28), xlen = cd.readUInt16LE(p + 30), clen = cd.readUInt16LE(p + 32);
  const lho = cd.readUInt32LE(p + 42), name = cd.toString('utf8', p + 46, p + 46 + nlen);
  entries.set(name, { method, crc, csize, usize, lho });
  p += 46 + nlen + xlen + clen;
}
console.log(`central directory: ${entries.size} entries`);

fs.mkdirSync(DEST, { recursive: true });
let total = 0;
for (const name of WANT) {
  const e = entries.get(name);
  if (!e) throw new Error(`entry not found: ${name}`);
  const lh = await range(e.lho, e.lho + 29);
  if (lh.readUInt32LE(0) !== 0x04034b50) throw new Error(`bad local header for ${name}`);
  const dataStart = e.lho + 30 + lh.readUInt16LE(26) + lh.readUInt16LE(28);
  console.log(`fetch ${name}: ${e.csize} bytes compressed`);
  const raw = e.csize ? await range(dataStart, dataStart + e.csize - 1) : Buffer.alloc(0);
  const data = e.method === 8 ? zlib.inflateRawSync(raw) : raw;
  if (data.length !== e.usize) throw new Error(`size mismatch for ${name}`);
  if ((zlib.crc32(data) >>> 0) !== e.crc) throw new Error(`CRC mismatch for ${name}`);
  const out = path.join(DEST, path.basename(name));
  fs.writeFileSync(out, data);
  total += e.csize;
  console.log(`  wrote ${out} (${data.length} bytes, CRC ok)`);
}
console.log(`done. downloaded ${total} bytes of template data.`);
