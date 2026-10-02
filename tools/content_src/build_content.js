// Builds content/celebrations.json and content/hr.json from the text sources in this folder.
//   node tools/content_src/build_content.js
// (V5_DESIGN sections 16 and 17.) Counts are checked: innuendo >= 120, flirt >= 80, praise >= 40, gossip >= 60.
const fs = require("fs");
const path = require("path");
const here = __dirname;
const root = path.resolve(here, "..", "..");
function lines(f) {
  return fs.readFileSync(path.join(here, f), "utf8").split(/\r?\n/).map(s => s.trim()).filter(s => s.length > 0);
}
const c = require("./celebrations_data.js");
const h = require("./hr_data.js");
const innuendo = [];
for (const t of lines("innuendo_h2.txt")) innuendo.push({ text: t, heat: 2 });
for (const t of lines("innuendo_h3.txt")) innuendo.push({ text: t, heat: 3 });
const flirt = lines("flirt_h1.txt").map(t => ({ text: t, heat: 1 }));
// Reject any line with an explicit word or a child word (a guard for later edits).
const banned = /\b(child|children|kid|kids|boy|girl|minor|school|teen|baby)\b/i;
for (const l of [...innuendo, ...flirt]) {
  if (banned.test(l.text)) throw new Error("banned word in: " + l.text);
}
const dupes = new Set();
for (const l of [...innuendo, ...flirt]) {
  if (dupes.has(l.text)) throw new Error("duplicate: " + l.text);
  dupes.add(l.text);
}
if (innuendo.length < 120) throw new Error("innuendo lines: " + innuendo.length);
if (flirt.length < 80) throw new Error("flirt lines: " + flirt.length);
if (h.praise.length < 40) throw new Error("praise lines: " + h.praise.length);
if (h.gossip.length < 60) throw new Error("gossip lines: " + h.gossip.length);
const cel = {
  _note: "V5_DESIGN section 16. innuendo and flirt lines carry a heat level (1 flirt, 2 cheeky, 3 very cheeky); never explicit, never with or about a child. Other topics are plain strings. Slots: {other} {name} {a} {b} {place} {reason}. Built by tools/content_src/build_content.js; edit the sources there.",
  innuendo, flirt,
  topics: { joke: c.joke, rivalry: c.rivalry, awkward: c.awkward, decline: c.decline, flirt_reply: c.flirt_reply, innuendo_reply: c.innuendo_reply, party_talk: c.party_talk, toast: c.toast, sing: c.sing },
  offers: c.offers, auto_small: c.auto_small, drama_small: c.drama_small, drama_big: c.drama_big
};
const hr = {
  _note: "V5_DESIGN section 17. praise: said in public (an HR officer present). gossip: said behind their back. Slots: {officer} {other} {dept} {a} {b} {reason}. Built by tools/content_src/build_content.js.",
  praise: h.praise, gossip: h.gossip, complaint: h.complaint, transfer: h.transfer, reasons: h.reasons,
  survey_text: h.survey_text, heard: h.heard, complaint_lines: h.complaint_lines
};
fs.writeFileSync(path.join(root, "content", "celebrations.json"), JSON.stringify(cel, null, 1) + "\n");
fs.writeFileSync(path.join(root, "content", "hr.json"), JSON.stringify(hr, null, 1) + "\n");
console.log("celebrations.json: innuendo " + innuendo.length + ", flirt " + flirt.length + ", toasts " + c.toast.length + ", party_talk " + c.party_talk.length);
console.log("hr.json: praise " + h.praise.length + ", gossip " + h.gossip.length);
