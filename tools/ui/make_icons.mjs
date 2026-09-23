// make_icons.mjs — writes the Frontier Habitat 2.0 icon set.
//
//   node tools/ui/make_icons.mjs
//
// Output: assets/ui/icons/<name>.svg (one file per icon) and assets/ui/icons/icons.json
// ({name: svg}). The game rasterises icons from the JSON at the exact pixel size it needs
// (ui/theme/icons.gd); the .svg files are the same drawings for people and the importer.
//
// Style: one flat duotone glyph family on a 24 x 24 grid. Everything is white; the game
// tints icons. Primary shapes are opaque, secondary shapes are 45% white. Strokes are 2 px
// with round caps and joins. Holes are cut with even-odd fills, never drawn in black.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(ROOT, 'assets', 'ui', 'icons');
const S2 = 0.45; // secondary opacity

// ---------------------------------------------------------------- primitives
const f = (n) => Number(n.toFixed(2));
const P = (d, o = 1, rule = '') => `<path d="${d}" fill="#fff"${o < 1 ? ` fill-opacity="${o}"` : ''}${rule ? ` fill-rule="${rule}"` : ''}/>`;
const EO = (d, o = 1) => P(d, o, 'evenodd');
const S = (d, w = 2, o = 1) => `<path d="${d}" fill="none" stroke="#fff" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"${o < 1 ? ` stroke-opacity="${o}"` : ''}/>`;
const C = (cx, cy, r, o = 1) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"${o < 1 ? ` fill-opacity="${o}"` : ''}/>`;
const CS = (cx, cy, r, w = 2, o = 1) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#fff" stroke-width="${w}"${o < 1 ? ` stroke-opacity="${o}"` : ''}/>`;
const R = (x, y, w, h, rx = 0, o = 1) => `<rect x="${x}" y="${y}" width="${w}" height="${h}"${rx ? ` rx="${rx}"` : ''} fill="#fff"${o < 1 ? ` fill-opacity="${o}"` : ''}/>`;
const RS = (x, y, w, h, rx = 0, sw = 2, o = 1) => `<rect x="${x}" y="${y}" width="${w}" height="${h}"${rx ? ` rx="${rx}"` : ''} fill="none" stroke="#fff" stroke-width="${sw}"${o < 1 ? ` stroke-opacity="${o}"` : ''}/>`;
const E = (cx, cy, rx, ry, o = 1, rot = 0) => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="#fff"${o < 1 ? ` fill-opacity="${o}"` : ''}${rot ? ` transform="rotate(${rot} ${cx} ${cy})"` : ''}/>`;
const G = (t, ...body) => `<g transform="${t}">${body.join('')}</g>`;

// Path pieces for even-odd holes.
const circ = (cx, cy, r) => `M${f(cx - r)} ${f(cy)}a${r} ${r} 0 1 0 ${f(2 * r)} 0a${r} ${r} 0 1 0 ${f(-2 * r)} 0z`;
const rect = (x, y, w, h) => `M${x} ${y}h${w}v${h}h${-w}z`;
const rrect = (x, y, w, h, r) => `M${f(x + r)} ${y}h${f(w - 2 * r)}a${r} ${r} 0 0 1 ${r} ${r}v${f(h - 2 * r)}a${r} ${r} 0 0 1 ${-r} ${r}h${f(-(w - 2 * r))}a${r} ${r} 0 0 1 ${-r} ${-r}v${f(-(h - 2 * r))}a${r} ${r} 0 0 1 ${r} ${-r}z`;
const poly = (pts) => 'M' + pts.map(([x, y]) => `${f(x)} ${f(y)}`).join('L') + 'z';
function star(cx, cy, ro, ri, n = 5, rot = -90) {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const r = i % 2 === 0 ? ro : ri;
    const a = (rot + (i * 180) / n) * Math.PI / 180;
    pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
  }
  return poly(pts);
}
function gear(cx, cy, teeth, ro, ri, hole) {
  const pts = [];
  const step = (Math.PI * 2) / teeth;
  for (let i = 0; i < teeth; i++) {
    const a = i * step - Math.PI / 2;
    const w = step * 0.22;
    pts.push([cx + Math.cos(a - step / 2 + w) * ri, cy + Math.sin(a - step / 2 + w) * ri]);
    pts.push([cx + Math.cos(a - w * 1.1) * ro, cy + Math.sin(a - w * 1.1) * ro]);
    pts.push([cx + Math.cos(a + w * 1.1) * ro, cy + Math.sin(a + w * 1.1) * ro]);
    pts.push([cx + Math.cos(a + step / 2 - w) * ri, cy + Math.sin(a + step / 2 - w) * ri]);
  }
  return poly(pts) + (hole > 0 ? circ(cx, cy, hole) : '');
}
function rays(cx, cy, r0, r1, n, w = 2, o = 1, rot = 0) {
  let d = '';
  for (let i = 0; i < n; i++) {
    const a = (rot + (i * 360) / n) * Math.PI / 180;
    d += `M${f(cx + Math.cos(a) * r0)} ${f(cy + Math.sin(a) * r0)}L${f(cx + Math.cos(a) * r1)} ${f(cy + Math.sin(a) * r1)}`;
  }
  return S(d, w, o);
}
const hexagon = (cx, cy, r, rot = 0) => poly([...Array(6)].map((_, i) => { const a = (rot + i * 60) * Math.PI / 180; return [cx + Math.cos(a) * r, cy + Math.sin(a) * r]; }));
function octagon(cx, cy, r) { return poly([...Array(8)].map((_, i) => { const a = (22.5 + i * 45) * Math.PI / 180; return [cx + Math.cos(a) * r, cy + Math.sin(a) * r]; })); }

// Shared shapes
const DROP = 'M12 2.5c3.3 4.3 7 8.2 7 12.2a7 7 0 0 1-14 0c0-4 3.7-7.9 7-12.2z';
const BOLT = 'M13.6 2 5 13.4h6.2L9.6 22 19 9.8h-6.3z';
const BOWL = 'M2.5 11.5h19a9.5 8 0 0 1-19 0z';
const LEAF = 'M5 19C5 10 10 5 20 4c0 10-5 15-15 15z';
const FLASK_BODY = 'M9 2.5h6v2h-1.2v4.8l5.6 9.4a1.8 1.8 0 0 1-1.5 2.8H6.1a1.8 1.8 0 0 1-1.5-2.8l5.6-9.4V4.5H9z';
const FLASK_LIQ = 'M7 14.5h10l2.3 3.9a1.2 1.2 0 0 1-1 1.8H5.7a1.2 1.2 0 0 1-1-1.8z';
const ROCKET = 'M12 1.8c3.6 2.6 5.2 6.8 5.2 11.2l-2 3.4H8.8l-2-3.4C6.8 8.6 8.4 4.4 12 1.8z' + circ(12, 9, 2);
const WRENCH = 'M20.6 7.4a5.4 5.4 0 0 1-7.1 5.1l-7.3 7.3a2 2 0 0 1-2.9-2.9l7.3-7.3a5.4 5.4 0 0 1 5.1-7.1l-3.1 3.1 0.8 2.6 2.6 0.8z';
const CROSS = 'M9 3h6v6h6v6h-6v6H9v-6H3V9h6z';
const WHEAT = S('M12 22V5', 1.8) + E(9.6, 16.5, 1.6, 3, 1, -35) + E(14.4, 16.5, 1.6, 3, 1, 35) + E(9.6, 11.6, 1.6, 3, 1, -35) + E(14.4, 11.6, 1.6, 3, 1, 35) + E(9.9, 6.9, 1.4, 2.7, 1, -35) + E(14.1, 6.9, 1.4, 2.7, 1, 35) + E(12, 3.4, 1.3, 2.2);
const PEOPLE = C(9, 7.5, 3.6) + P('M2.2 20.5a6.8 6.8 0 0 1 13.6 0z') + C(17.2, 8.6, 2.8, S2) + P('M15 14.1a5.6 5.6 0 0 1 7 5.6v0.8h-4.6a8.6 8.6 0 0 0-2.4-6.4z', S2);
const MEDAL = P('M6.5 1.8h4.4l2.6 5.6-2.6 2.3z', S2) + P('M13.1 1.8h4.4l-3.9 7.9-2.3-2z', S2) + EO(circ(12, 15.2, 6.8) + star(12, 15.4, 3.9, 1.7));

const icons = {
  // ---------------------------------------------------------------- actions
  close: S('M6 6l12 12M18 6 6 18', 2.4),
  check: S('M4.8 12.6l4.6 4.6L19.4 7.2', 2.6),
  plus: S('M12 5v14M5 12h14', 2.4),
  minus: S('M5 12h14', 2.4),
  chevron_left: S('M15 5l-7 7 7 7', 2.4),
  chevron_right: S('M9 5l7 7-7 7', 2.4),
  chevron_up: S('M5 15l7-7 7 7', 2.4),
  chevron_down: S('M5 9l7 7 7-7', 2.4),
  arrow_up: S('M12 19V5M6 11l6-6 6 6', 2.2),
  arrow_down: S('M12 5v14M6 13l6 6 6-6', 2.2),
  arrow_right: S('M5 12h14M13 6l6 6-6 6', 2.2),
  trend_up: S('M3.5 16.5l5.5-5.5 4 4 7.5-7.5', 2.2) + S('M15 7.5h5.5V13', 2.2),
  trend_down: S('M3.5 7.5l5.5 5.5 4-4 7.5 7.5', 2.2) + S('M15 16.5h5.5V11', 2.2),
  trend_flat: S('M3.5 12h16', 2.2) + S('M15.5 8l4 4-4 4', 2.2),
  pause: R(6, 4.5, 4, 15, 1.2) + R(14, 4.5, 4, 15, 1.2),
  play: P('M7 4.6v14.8a1 1 0 0 0 1.5.86l12.2-7.4a1 1 0 0 0 0-1.72L8.5 3.74A1 1 0 0 0 7 4.6z'),
  speed2: P('M2.5 5.5v13l9-6.5z') + P('M12.5 5.5v13l9-6.5z'),
  speed4: P('M1 7v10l6.6-5z') + P('M8.2 7v10l6.6-5z') + P('M15.4 7v10l6.6-5z'),
  menu: S('M4 7h16M4 12h16M4 17h16', 2.2),
  settings: EO(gear(12, 12, 8, 10, 7.4, 3.2)),
  save: EO('M5 3h11.2L21 7.8V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z' + rect(7, 5, 8, 4.6) + rrect(6.5, 13, 11, 6, 1)),
  load: P('M3 6.2A2.2 2.2 0 0 1 5.2 4h4.2l2.2 2.2h7.2A2.2 2.2 0 0 1 21 8.4V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z', S2) + P('M2.4 10.4h19.2l-1.5 8A2 2 0 0 1 18.1 20H5.9a2 2 0 0 1-2-1.6z'),
  import: S('M4 14.5v4A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-4', 2.2) + S('M12 3.5v11M7.2 10l4.8 4.8 4.8-4.8', 2.2),
  export: S('M4 14.5v4A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-4', 2.2) + S('M12 14.5v-11M7.2 8l4.8-4.8L16.8 8', 2.2),
  build: G('rotate(45 12 12)', R(10.6, 7.5, 2.8, 15, 1.2), R(5.5, 2, 13, 6.2, 1.4)),
  demolish: EO('M5.6 7.5h12.8l-1.1 12.6A2 2 0 0 1 15.3 22H8.7a2 2 0 0 1-2-1.9z' + rect(9.2, 10.5, 1.6, 8) + rect(13.2, 10.5, 1.6, 8)) + R(3.5, 4.4, 17, 2.3, 1.1) + R(9, 1.8, 6, 2.2, 1),
  upgrade: S('M6 12.5l6-6 6 6', 2.6) + S('M6 19l6-6 6 6', 2.6, S2),
  rotate: S('M19.5 12a7.5 7.5 0 1 1-2.2-5.3', 2.2) + P('M20.5 3.5v6.6h-6.6z'),
  info: C(12, 12, 10, S2) + R(10.8, 10.2, 2.4, 7.4, 1.2) + C(12, 7, 1.5),
  search: CS(10.5, 10.5, 6.5, 2.4) + S('M15.4 15.4l5.1 5.1', 2.8),
  lock: EO(rrect(4.5, 10, 15, 11.5, 2) + circ(12, 15, 1.7)) + S('M8 10V7.2a4 4 0 0 1 8 0V10', 2.4),
  unlock: EO(rrect(4.5, 10, 15, 11.5, 2) + circ(12, 15, 1.7)) + S('M8 10V7.2a4 4 0 0 1 7.6-1.8', 2.4),
  target: CS(12, 12, 7, 2) + S('M12 1.5v4.5M12 18v4.5M1.5 12H6M18 12h4.5', 2) + C(12, 12, 2.2),
  follow: CS(12, 12, 8.5, 1.8, S2) + C(12, 8.6, 2.6) + P('M7 17.5a5 5 0 0 1 10 0z'),
  power_toggle: S('M12 2.8v8.4', 2.6) + S('M6.9 6.2a8 8 0 1 0 10.2 0', 2.6),
  priority: R(3.5, 14, 4.2, 6.5, 1) + R(9.9, 9.5, 4.2, 11, 1) + R(16.3, 4, 4.2, 16.5, 1, S2),
  goals: S('M5 21.5V3.2', 2.2) + P('M6 3.5h13l-3.2 4.8 3.2 4.8H6z'),
  awards: MEDAL,
  medal: MEDAL,
  trophy: P('M7 2.5h10v6a5 5 0 0 1-10 0z') + S('M7 4.6H3.8a3.4 3.4 0 0 0 3.6 4.6M17 4.6h3.2a3.4 3.4 0 0 1-3.6 4.6', 1.8) + R(10.8, 13, 2.4, 4.5) + R(7.5, 17.5, 9, 3.6, 1.2),
  research: G('', `<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="#fff" stroke-width="1.7"/>`, `<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="#fff" stroke-width="1.7" transform="rotate(60 12 12)"/>`, `<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="#fff" stroke-width="1.7" transform="rotate(120 12 12)"/>`) + C(12, 12, 2.4),
  flask: P(FLASK_BODY, S2) + P(FLASK_LIQ),
  dashboard: RS(2.5, 2.5, 19, 19, 2.5, 1.8, S2) + S('M6 16.5l4-5 3.2 3 4.8-6.5', 2.2),
  inventory: R(2.5, 11.5, 8.6, 8.6, 1.2) + R(12.9, 11.5, 8.6, 8.6, 1.2) + R(7.7, 2.6, 8.6, 8.2, 1.2, S2),
  colonists: PEOPLE,
  people: PEOPLE,
  overlay: P('M12 3l9.5 5.2L12 13.4 2.5 8.2z') + S('M2.5 12.4 12 17.6l9.5-5.2', 2) + S('M2.5 16.4 12 21.6l9.5-5.2', 2, S2),
  corridor: R(2, 8.5, 20, 7, 3.5, S2) + S('M2.5 8.5h19M2.5 15.5h19', 2) + S('M7.5 7v10M16.5 7v10', 2.2),
  cable: R(11.5, 6.5, 7.5, 8, 2) + R(19, 8, 3, 1.8, 0.8) + R(19, 11.2, 3, 1.8, 0.8) + S('M11.5 10.5H8.2A4.2 4.2 0 0 0 4 14.7V21', 2.2),
  sun: C(12, 12, 4.6) + rays(12, 12, 7.4, 10.2, 8, 2.2),
  moon: P('M20.5 14.6A8.6 8.6 0 1 1 9.4 3.5a7 7 0 0 0 11.1 11.1z'),
  star: P(star(12, 12.6, 10, 4.3)),
  sparkle: P('M12 2l2.1 7.9L22 12l-7.9 2.1L12 22l-2.1-7.9L2 12l7.9-2.1z') + C(19, 5, 1.6, S2) + C(5, 19, 1.3, S2),
  ship: P(ROCKET, 1, 'evenodd') + P('M6.8 13l-3.1 4.2v3.3l4.2-2.2z', S2) + P('M17.2 13l3.1 4.2v3.3l-4.2-2.2z', S2) + P('M9.8 17.6h4.4L12 22.4z', S2),
  eye: EO('M12 5C6.6 5 2.8 9.3 1.5 12c1.3 2.7 5.1 7 10.5 7s9.2-4.3 10.5-7C21.2 9.3 17.4 5 12 5z' + circ(12, 12, 3.8)) + C(12, 12, 1.7),
  clock: CS(12, 12, 9, 2) + S('M12 7v5.2l3.6 2.2', 2.2),
  calendar: RS(3.5, 5, 17, 15.5, 2, 2) + R(3.5, 5, 17, 5, 2) + S('M8 2.8v4.4M16 2.8v4.4', 2) + R(7, 13, 3, 3, 0.6, S2) + R(11.5, 13, 3, 3, 0.6, S2),
  heart: P('M12 21.2s-8.7-5.4-8.7-11.4A4.9 4.9 0 0 1 12 7.1a4.9 4.9 0 0 1 8.7 2.7c0 6-8.7 11.4-8.7 11.4z'),
  health: P('M12 21.2s-8.7-5.4-8.7-11.4A4.9 4.9 0 0 1 12 7.1a4.9 4.9 0 0 1 8.7 2.7c0 6-8.7 11.4-8.7 11.4z', S2) + S('M5 12.6h3.4l1.6-3 2.6 5.6 1.8-2.6H19', 1.9),
  nutrition: P('M12 7.8c-1.6-1.3-4.7-1.6-6.3.5-2.1 2.7-1.4 7.8 1.6 11 1.5 1.6 3 2.1 4.7 1 1.7 1.1 3.2.6 4.7-1 3-3.2 3.7-8.3 1.6-11-1.6-2.1-4.7-1.8-6.3-.5z') + P('M12.2 7.3c0-2.6 1.5-4.6 4.2-5.2-.3 2.6-1.8 4.5-4.2 5.2z', S2),
  protein: P('M14.6 3.3a6.1 6.1 0 0 1 6.1 6.1c0 3.4-2.8 5.6-6.1 5.6-.9 0-1.8-.2-2.6-.6l-4 4a2.3 2.3 0 1 1-2.7 2.7 2.3 2.3 0 1 1-2.3-3.2 2.3 2.3 0 1 1 3.2-.7l4-4a6 6 0 0 1-.6-2.7 6.1 6.1 0 0 1 5-7.2z'),
  carbs: WHEAT,
  fat: EO(DROP + circ(9.6, 15.6, 1.6)),
  vitamins: C(12, 12, 9.6, S2) + CS(12, 12, 9.6, 1.8) + S('M12 3.5v17M3.5 12h17M6 6l12 12M18 6 6 18', 1.4),
  taste: P('M12 2l2.1 7.9L22 12l-7.9 2.1L12 22l-2.1-7.9L2 12l7.9-2.1z'),
  morale: C(12, 12, 10, S2) + C(8.7, 9.6, 1.5) + C(15.3, 9.6, 1.5) + S('M7.6 14.2a5 5 0 0 0 8.8 0', 2),
  o2: CS(8.6, 14.2, 6.2, 2.2) + CS(17.2, 6.6, 3.4, 2) + C(18.6, 16.4, 2.3),
  water: EO(DROP + 'M8.4 14.8a3.6 3.6 0 0 0 3.6 3.6v-1.6a2 2 0 0 1-2-2z'),
  power: P(BOLT),
  energy: RS(2.8, 7, 16.2, 10, 2, 2) + R(19.6, 10, 2, 4, 0.8) + R(5.4, 9.6, 8.4, 4.8, 0.8),
  food: S('M6.2 2.8v5.8a2.6 2.6 0 0 0 5.2 0V2.8M8.8 2.8V21.2', 1.9) + P('M16.2 2.8c2.6 1.6 3.6 4.8 3.6 8.4h-2.3V21a1.1 1.1 0 0 1-2.2 0V3.4z'),
  beds: R(2, 12, 20, 5.5, 1.4) + R(2, 6, 2.4, 15, 1) + R(19.6, 14, 2.4, 7, 1) + R(5, 8.6, 5.4, 3, 1.4, S2),
  pod: EO(rrect(3.5, 7, 17, 13.5, 2) + rect(3.5, 12, 17, 1.6)) + P('M12 1.8l3 3.6h-6z', S2) + R(10.5, 5, 3, 2),
  crate: P('M12 2.2l9.2 5v9.6L12 21.8l-9.2-5V7.2z', S2) + S('M2.8 7.2l9.2 5 9.2-5M12 12.2v9.6', 1.8),
  map: P('M2.5 5.5l6-2.5v15.5l-6 2.5z', S2) + P('M8.5 3l7 2.5V21l-7-2.5z') + P('M15.5 5.5l6-2.5v15.5l-6 2.5z', S2),
  camera: EO(rrect(2.5, 6.5, 19, 13.5, 2.2) + circ(12, 13.2, 3.8)) + P('M8 6.5l1.6-2.8h4.8L16 6.5z'),
  queue: C(4.6, 6, 1.7) + C(4.6, 12, 1.7) + C(4.6, 18, 1.7) + S('M9 6h11.5M9 12h11.5M9 18h11.5', 2.2),
  volume: P('M3 9h4l5-4.5v15L7 15H3z') + S('M15.5 8.5a5 5 0 0 1 0 7M18.3 5.8a9 9 0 0 1 0 12.4', 2),
  mute: P('M3 9h4l5-4.5v15L7 15H3z') + S('M15.5 9.5l5 5M20.5 9.5l-5 5', 2),
  music: P('M9 5.5l11-2.5v12.2', S2) + S('M9 17.5V5.5l11-2.5v12.2', 2) + C(6.5, 17.5, 2.8) + C(17.5, 15.2, 2.8),
  keyboard: EO(rrect(2, 6, 20, 12.5, 2) + rect(5, 9, 2, 2) + rect(8.5, 9, 2, 2) + rect(12, 9, 2, 2) + rect(15.5, 9, 2, 2) + rect(7, 13.5, 10, 2)),
  graphics: EO(rrect(2, 3.5, 20, 13.5, 1.8) + rect(4, 5.5, 16, 9.5)) + P('M6.5 14l3.5-4.5 2.5 3 2-2.2 3 3.7z', S2) + R(10.5, 17, 3, 2.6) + R(7, 19.4, 10, 1.8, 0.9),
  ui_scale: S('M4 9V4h5M20 15v5h-5M4 4l6 6M20 20l-6-6', 2.2) + R(12.5, 4, 7.5, 7.5, 1.4, S2),
  mouse: EO(rrect(6, 2.5, 12, 19, 6) + 'M11.2 5.5h1.6v4.2h-1.6z'),
  home: P('M12 3l9.5 8.2-1.3 1.5L19 11.6V20.5h-5v-6h-4v6H5v-8.9l-1.2 1.1-1.3-1.5z'),
  new_game: R(3, 3, 18, 18, 3, S2) + S('M12 7.5v9M7.5 12h9', 2.4),
  dice: EO(rrect(3, 3, 18, 18, 3.5) + circ(8, 8, 1.7) + circ(16, 8, 1.7) + circ(12, 12, 1.7) + circ(8, 16, 1.7) + circ(16, 16, 1.7)),
  planet: C(12, 12, 6.8) + `<ellipse cx="12" cy="12" rx="10.8" ry="3.6" fill="none" stroke="#fff" stroke-width="1.8" stroke-opacity="${S2}" transform="rotate(-20 12 12)"/>`,
  radiation: C(12, 12, 2.2) + P('M12 12 7.7 4.6A8.6 8.6 0 0 1 16.3 4.6z') + P('M12 12h8.6a8.6 8.6 0 0 1-4.3 7.4z') + P('M12 12l-4.3 7.4A8.6 8.6 0 0 1 3.4 12z'),
  wind: S('M3 8.5h11.5a3 3 0 1 0-3-3M3 12.5h15.5a3 3 0 1 1-3 3M3 16.5h7', 2.2),
  level: R(3, 15, 3.4, 5.5, 0.8) + R(7.7, 12, 3.4, 8.5, 0.8) + R(12.4, 9, 3.4, 11.5, 0.8) + R(17.1, 5, 3.4, 15.5, 0.8, S2),
  size: RS(3, 3, 18, 18, 1.5, 1.8, S2) + R(3, 11, 10, 10, 1.5),
  chapter: P('M4 3.5h11.5A3.5 3.5 0 0 1 19 7v14H7.5A3.5 3.5 0 0 1 4 17.5z', S2) + S('M4 17.5A3.5 3.5 0 0 1 7.5 14H19', 2) + S('M8 7.5h7', 2),
  door: EO('M5 2.5h14V21.5H5z' + rect(7, 4.5, 10, 17)) + C(14.5, 13, 1.2) + R(3, 20, 18, 1.8, 0.9),
  crosshair: CS(12, 12, 8, 1.8) + S('M12 2v6M12 16v6M2 12h6M16 12h6', 1.8),
  list: S('M8 6h12.5M8 12h12.5M8 18h12.5', 2.2) + R(3.2, 4.6, 2.8, 2.8, 0.6) + R(3.2, 10.6, 2.8, 2.8, 0.6) + R(3.2, 16.6, 2.8, 2.8, 0.6),
  grid: R(3, 3, 8, 8, 1.4) + R(13, 3, 8, 8, 1.4, S2) + R(3, 13, 8, 8, 1.4, S2) + R(13, 13, 8, 8, 1.4),
  history: S('M3.8 12a8.2 8.2 0 1 0 2.4-5.8', 2) + P('M3 3.4v6.2h6.2z') + S('M12 7.5v4.8l3.2 2', 2),
  exit: S('M14 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8', 2.2) + S('M10 12h11M17 8l4 4-4 4', 2.2),

  // ---------------------------------------------------------------- severity
  sev_info: C(12, 12, 10, S2) + R(10.8, 10.2, 2.4, 7.4, 1.2) + C(12, 7, 1.5),
  sev_warning: EO('M10.3 3.4a2 2 0 0 1 3.4 0l8.3 14.4a2 2 0 0 1-1.7 3H3.7a2 2 0 0 1-1.7-3z' + rrect(10.8, 8.2, 2.4, 6.6, 1.2) + circ(12, 17.3, 1.4)),
  sev_critical: EO(octagon(12, 12, 10.4) + rrect(10.7, 5.8, 2.6, 8, 1.3) + circ(12, 17.2, 1.5)),
  sev_ok: C(12, 12, 10, S2) + S('M7.2 12.4l3.2 3.2 6.4-6.8', 2.4),

  // ---------------------------------------------------------------- building categories
  cat_life_support: S('M3 8.5h11.5a3 3 0 1 0-3-3M3 12.5h15.5a3 3 0 1 1-3 3M3 16.5h7', 2.2),
  cat_food: P(LEAF) + S('M3.5 20.5 13 11', 1.8),
  cat_housing: EO('M2.5 19a9.5 9.5 0 0 1 19 0z' + rrect(10.2, 13.5, 3.6, 5.5, 1.6) + circ(6.8, 14.8, 1.2) + circ(17.2, 14.8, 1.2)) + R(1.5, 19, 21, 2.2, 1.1),
  cat_industry: EO('M2.5 21V11.5l5.5 3.3v-3.3l5.5 3.3V4.5h3.2v-2h2.6v2h2.2V21z' + rect(5.5, 16.5, 2.4, 2.4) + rect(10.5, 16.5, 2.4, 2.4) + rect(15.5, 16.5, 2.4, 2.4)),
  cat_logistics: P('M12 2.2l9.2 5v9.6L12 21.8l-9.2-5V7.2z', S2) + S('M2.8 7.2l9.2 5 9.2-5M12 12.2v9.6M7.4 4.7l9.2 5', 1.8),
  cat_utilities: P(BOLT),
  cat_medical: P(CROSS),
  cat_comfort: P('M4 10a2 2 0 0 1 2 2v2h12v-2a2 2 0 1 1 4 0v5.5a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V12a2 2 0 0 1 2-2z') + R(5.2, 4.5, 13.6, 6.5, 2.2, S2) + R(4.5, 19, 2, 2.5, 0.6) + R(17.5, 19, 2, 2.5, 0.6),
  cat_science: P(FLASK_BODY, S2) + P(FLASK_LIQ),
  cat_space: P(ROCKET, 1, 'evenodd') + P('M6.8 13l-3.1 4.2v3.3l4.2-2.2z', S2) + P('M17.2 13l3.1 4.2v3.3l-4.2-2.2z', S2) + P('M9.8 17.6h4.4L12 22.4z', S2),

  // ---------------------------------------------------------------- roles
  role_technician: P(WRENCH),
  role_grower: P('M6.8 14h10.4l-1.6 7.5H8.4z') + S('M12 14V8.5', 2) + P('M12 9.5c0-3.3 2.2-5.5 6.8-5.5 0 3.8-2.3 5.5-6.8 5.5z') + P('M12 11.5c0-2.7-1.9-4.8-5.8-4.8 0 3.2 1.9 4.8 5.8 4.8z', S2),
  role_operator: EO('M4.6 16.5a7.4 7.4 0 0 1 14.8 0z' + rect(11, 8.8, 2, 7.7)) + R(2.5, 16.5, 19, 3, 1.2),
  role_medic: C(12, 12, 10.2, S2) + P('M10 5.5h4v4.5h4.5v4H14v4.5h-4V14H5.5v-4H10z'),
  role_scientist: P(FLASK_BODY, S2) + P(FLASK_LIQ),

  // ---------------------------------------------------------------- items: raw and materials
  ore: P('M3.5 15.5 6 7.8l6.2-4.3 6.3 2.8 2.3 7.8-3.2 5.8-8.7 1.4z', S2) + S('M6 12.5l3.5 1.5 2-4 3.5 2.5 3-1', 2),
  silicate: P('M1.8 20.5c2-5.3 5.7-8.3 10.2-8.3s8.2 3 10.2 8.3z') + C(7.4, 7.2, 1.5, S2) + C(12, 4.8, 1.6) + C(16.6, 7.8, 1.4, S2) + C(10, 9.6, 1.1) + C(14.4, 10.2, 1.1),
  exotic: P('M12 1.8l3.2 4.2v12.2L12 22.2l-3.2-4V6z') + P('M5.4 7.8l2.3 2.6v8.8l-2.3 2.2-2.3-2.2v-8.8z', S2) + P('M18.6 7.8l2.3 2.6v8.8l-2.3 2.2-2.3-2.2v-8.8z', S2),
  metal: P('M2.5 20h8.8l-1.3-4.6H3.8z') + P('M12.7 20h8.8l-1.3-4.6h-6.2z') + P('M7.6 13.8h8.8L15.1 9.2H8.9z') + P('M5.5 7.6h13l-.6-2.2H6.1z', S2),
  glass: R(4.5, 2.5, 15, 19, 1.8, 0.3) + RS(4.5, 2.5, 15, 19, 1.8, 2) + S('M8 13.5l6-6M10.2 17.5l6.6-6.6', 1.7),
  polymer: S(hexagon(12, 12, 7.6, 30), 2) + C(12, 4.4, 2.3) + C(18.6, 15.8, 2.3) + C(5.4, 15.8, 2.3) + C(12, 12, 1.6, S2),
  biomass: P(LEAF, S2) + P('M3 21c0-6.5 3.8-10.2 11-10.8 0 7-3.8 10.8-11 10.8z') + S('M3 21l6-6', 1.6),
  spare_parts: EO(gear(12, 12, 9, 10, 7.6, 3)),
  electronics: EO(rrect(6, 6, 12, 12, 1.8) + rect(9.5, 9.5, 5, 5)) + S('M9 2.8v2.2M12 2.8v2.2M15 2.8v2.2M9 19v2.2M12 19v2.2M15 19v2.2M2.8 9h2.2M2.8 12h2.2M2.8 15h2.2M19 9h2.2M19 12h2.2M19 15h2.2', 1.6),
  hull_plate: EO(rrect(2.5, 4.5, 19, 15, 2) + circ(5.8, 7.8, 1.2) + circ(18.2, 7.8, 1.2) + circ(5.8, 16.2, 1.2) + circ(18.2, 16.2, 1.2)) + S('M9 12h6', 1.6, S2),
  composite: P('M2.5 8.2 12 3.8l9.5 4.4L12 12.6z') + S('M2.5 12.2l9.5 4.4 9.5-4.4', 2) + S('M2.5 16.2l9.5 4.4 9.5-4.4', 2, S2),
  rocket_fuel: EO('M7 4.5h8l3.5 3.5v12.2a1.6 1.6 0 0 1-1.6 1.6H7.1a1.6 1.6 0 0 1-1.6-1.6V6A1.5 1.5 0 0 1 7 4.5z' + 'M12 10c1.8 1.9 2.9 3.5 2.9 5.1a2.9 2.9 0 0 1-5.8 0c0-1.6 1.1-3.2 2.9-5.1z') + R(8.5, 1.8, 5.5, 2.2, 1),
  medicine: G('rotate(-45 12 12)', R(3.5, 8, 17, 8, 4, S2), P('M7.5 8H12v8H7.5a4 4 0 0 1 0-8z')),
  water_can: EO(DROP + 'M8.4 14.8a3.6 3.6 0 0 0 3.6 3.6v-1.6a2 2 0 0 1-2-2z'),

  // ---------------------------------------------------------------- items: crops
  potato: EO('M3.5 13.2c0-4.6 3.9-8.2 8.7-8.2S21 8 21 11.6s-4 7.9-9.3 7.9S3.5 17.8 3.5 13.2z' + circ(8.2, 11, 0.9) + circ(13.8, 9.2, 0.9) + circ(16.4, 13.6, 0.9) + circ(10.6, 15.4, 0.9)),
  wheat: WHEAT,
  soybean: P('M3.5 17.2C3.5 10.2 8.6 4.6 17 3.6c2.2 0 3.4 1.2 3.4 3.4-1 8.3-6.4 13.4-13.4 13.4-2.3 0-3.5-1.2-3.5-3.2z', S2) + C(8.3, 15.7, 2.2) + C(12, 12, 2.2) + C(15.7, 8.3, 2.2),
  tomato: C(12, 14, 7.8) + P('M12 6.8 9 4.6l1.1 2.6L6.6 7.8l3.6.8L12 10.5l1.8-1.9 3.6-.8-3.5-.6L15 4.6z', S2) + S('M12 5.2V2.5', 1.6),
  greens: P('M12 21.2c-5.1 0-8.7-3.6-8.7-8.2 0-2.6 1.2-4.1 3.1-4.9C7 5 9.3 3.2 12 3.2s5 1.8 5.6 4.9c1.9.8 3.1 2.3 3.1 4.9 0 4.6-3.6 8.2-8.7 8.2z', S2) + S('M12 21V9.5M12 14.2 8.4 11M12 17.4l3.6-3.6', 1.7),
  mushroom: EO('M2.8 12.4a9.2 7.6 0 0 1 18.4 0z' + circ(8, 8.6, 1.2) + circ(13.8, 6.8, 1.3) + circ(16.6, 10.2, 0.9)) + R(9.3, 12.4, 5.4, 8.8, 2.2, S2),
  algae: S('M6.5 21.5c-2.2-4 2.2-6.2 0-10.2s2.2-6.2 0-9', 2) + S('M11.8 21.5c-2.2-4 2.2-6.2 0-10.2s2.2-6.2 0-9', 2, S2) + C(17, 7.5, 1.9) + C(18.8, 13, 1.4, S2) + C(16.6, 17.8, 2.3),
  herbs: S('M12 22V7.5', 1.8) + E(8.7, 16.5, 1.9, 3.4, 1, -50) + E(15.3, 13.5, 1.9, 3.4, 1, 50) + E(8.7, 10.5, 1.8, 3.1, S2, -50) + E(15.3, 7.6, 1.8, 3.1, S2, 50) + E(12, 4.4, 1.6, 2.8),

  // ---------------------------------------------------------------- items: dishes
  meals: P('M5 3.5l1.4 1.2L7.8 3.5l1.4 1.2 1.4-1.2L12 4.7l1.4-1.2 1.4 1.2 1.4-1.2 1.4 1.2L19 3.5V21H5z', S2) + R(5, 10.5, 14, 4.5),
  mashed_potato: P(BOWL) + P('M6.2 11.5c0-3.2 2.6-5.4 5.8-5.4s5.8 2.2 5.8 5.4z', S2) + R(10.8, 4.2, 2.6, 2.4, 0.5),
  flatbread: C(12, 12.5, 9.2, S2) + S('M7 9.5l3 2M11.5 8l2.5 2.5M8.5 15l3 1.5M14 14.5l2.8-1.5', 1.8),
  garden_salad: P(BOWL) + P('M5 11c0-3.4 2-5.2 5-5.2 0 3-1.7 5.2-5 5.2z', S2) + P('M19 11c0-3.4-2-5.2-5-5.2 0 3 1.7 5.2 5 5.2z', S2) + C(12, 8.2, 2.3),
  algae_bar: R(2.5, 7.5, 19, 9, 2.2, S2) + S('M5.2 12c1.9-2.2 3.1 2.2 5 0s3.1-2.2 5 0 3.1 2.2 4.1 0', 1.9),
  herb_potatoes: E(12, 16, 10, 4.2, S2) + E(8, 12.6, 3, 2.3) + E(15.5, 12.4, 3, 2.3) + E(11.8, 9.4, 2.8, 2.1) + P('M17.5 6.5c0-2 1.3-3.5 3.8-3.7 0 2.2-1.4 3.6-3.8 3.7z'),
  tomato_pasta: E(12, 15.5, 10, 4.5, S2) + S('M12 13.5c-3.2 0-4.3-2.8-2.6-4.6 1.7-1.8 5-1.2 5.4 1.2.4 2.4-2.1 3.6-3.6 2.4', 1.9) + C(17.5, 9, 1.9),
  soy_stew: P('M4 10.5h16v5.5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5z') + S('M2 12h2M20 12h2', 2.2) + S('M8.5 7.5c-1-1.3 1-2 0-3.5M12 7.5c-1-1.3 1-2 0-3.5M15.5 7.5c-1-1.3 1-2 0-3.5', 1.6, S2),
  mushroom_risotto: P(BOWL) + P('M7 10.5a5 4 0 0 1 10 0z', S2) + R(10.8, 7.6, 2.4, 4, 1),
  tofu_stirfry: P('M2.5 11.5h16.5a8.2 7 0 0 1-16.5 0z') + S('M19 12.5h3.5', 2.2) + R(5, 6.5, 4, 4, 0.8, S2) + R(10, 5, 4, 4, 0.8) + R(14.5, 7, 3.6, 3.6, 0.8, S2),
  veggie_pizza: EO('M12 21.8 2.6 5.6C8.3 2.4 15.7 2.4 21.4 5.6z' + circ(9.6, 8.6, 1.5) + circ(14.6, 8.2, 1.4) + circ(12, 13.4, 1.5)) + P('M2.6 5.6C8.3 2.4 15.7 2.4 21.4 5.6l-1 1.7C15.1 4.6 8.9 4.6 3.6 7.3z', S2),
  colony_feast: R(2, 17.5, 20, 2.4, 1.2) + P('M4 16.5a8 8 0 0 1 16 0z') + C(12, 7, 1.6) + P('M18.2 3.2l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z', S2),

  // ---------------------------------------------------------------- item categories
  icat_raw: P('M3.5 15.5 6 7.8l6.2-4.3 6.3 2.8 2.3 7.8-3.2 5.8-8.7 1.4z', S2) + S('M6 12.5l3.5 1.5 2-4 3.5 2.5 3-1', 2),
  icat_material: P('M2.5 20h8.8l-1.3-4.6H3.8z') + P('M12.7 20h8.8l-1.3-4.6h-6.2z') + P('M7.6 13.8h8.8L15.1 9.2H8.9z'),
  icat_component: EO(gear(12, 12, 9, 10, 7.6, 3)),
  icat_medical: P(CROSS),
  icat_water: P(DROP),
  icat_crop: S('M12 21V11', 2) + P('M12 12c0-4 2.6-6.6 8-6.6 0 4.5-2.7 6.6-8 6.6z') + P('M12 14c0-3.3-2.2-5.6-6.8-5.6 0 3.9 2.3 5.6 6.8 5.6z', S2),
  icat_dish: P(BOWL) + S('M9 8c-1-1.3 1-2 0-3.5M13 8c-1-1.3 1-2 0-3.5', 1.6, S2),
};

// Aliases: KPI names that the interface uses.
const alias = { kpi_o2: 'o2', kpi_water: 'water', kpi_power: 'power', kpi_energy: 'energy', kpi_food: 'food', kpi_morale: 'morale', kpi_research: 'research', kpi_people: 'people' };
for (const [a, b] of Object.entries(alias)) icons[a] = icons[b];

fs.mkdirSync(OUT, { recursive: true });
const manifest = {};
for (const [name, body] of Object.entries(icons)) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24">${body}</svg>`;
  manifest[name] = svg;
  const file = path.join(OUT, name + '.svg');
  if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== svg) fs.writeFileSync(file, svg);
}
fs.writeFileSync(path.join(OUT, 'icons.json'), JSON.stringify(manifest));
console.log(`wrote ${Object.keys(manifest).length} icons to ${path.relative(ROOT, OUT)}`);
