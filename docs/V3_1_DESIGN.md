# Frontier Habitat 3.1 — doors, paths, airlocks, ships and visitors, sound and music

Version 3.1 · 25 September 2026 · Owner: orchestrator

This file is the contract for version 3.1. It adds to `docs/V3_DESIGN.md` and `docs/AAA_DESIGN.md`.
**Every agent reads V3_DESIGN §0, §9, §10 and all of this file before it starts.** Where the files
disagree, this file wins. The numbers live in `content/*.json`.

Paul's request (25 September 2026, lightly cleaned):
*"Do more to the doors and passageways. The decals on the habitats' outer walls need to hide where
a doorway intersects, so they do not cover the doorways. The paths need to be smoother and dodge the
furniture in habitats. The NPCs still travel through walls and habitats. Entering and exiting the
airlocks needs to be smoothed out, and the airlock models need more work and a better layout, with a
middle chamber to pressurise and depressurise. The doors need to look solid — they are half done as
it stands. We also need ships landing and different visitors. And make the sound work and add some
mood music."*

---

## 0. Ground rules

All of V3_DESIGN §0 applies: never open a window on Paul's desktop; Godot only through
`node tools/godot.mjs`; Blender only with `--background`; export to `build/web_<you>/`; keep
`check` clean; the simulation is authoritative and deterministic; the ledger stays `{}`; player
text in plain STE English; report honestly, including what you did not test.

Budgets (unchanged): late-colony overview ≥ 50 fps, draw calls ≤ 1,400, tick ≤ 2.0 ms at 70
colonists. Web pck growth ≤ 25 MB for this version (music included). Save schema 4; v3 and v2
saves load.

**Visual gate.** Every visual subject in §8 goes through the CRITIC (V3_DESIGN §9, pass ≥ 0.65).
Pilots first (§9).

---

## 1. Sound — the defect (fixed by the orchestrator) and what UI finishes

**Defect (measured).** The released v3.0 web build outputs no sound. An instrumented copy
(`AnalyserNode` on the audio destination, headless Chrome at 60 fps) read peak 0.000 in play. Cause:
Godot 4.4 web "sample" playback. The buses were made at runtime by `ui/audio.gd`, and a fade on
`volume_db` of a playing sample does not reach Web Audio, so the ambience loops stayed at −60 dB.

**Fix (in the tree now):** `project.godot` `[audio] general/default_playback_type.web=0` (Stream: the
engine mixes, as on desktop) and `default_bus_layout.tres` (Master, Music, SFX, UI, Ambience, all
send to Master). Measured after the fix: in-game ambience peak −31 dBFS.

**Gate:** `node tools/audio_probe.mjs <build dir>` (orchestrator tool) must report an in-game peak
above −45 dBFS with music on, and above −60 dBFS with music at 0 (ambience only). Any agent that
touches audio runs it on its own export.

UI also sets `audio/driver/output_latency.web` so that the stream mixer does not crackle when the
frame rate drops to 40 fps (measure; report the value).

## 2. Mood music and world sounds (UI owns audio; RENDER sends world events)

### 2.1 Music
Generate with Eleven Music (`node ~/.claude/skills/audio-gen/generate.mjs`, `type: music`; key in
`~/.claude/elevenlabs.json`, never copy it into the repo). Add the entries to
`tools/ui/audio-events.json`. MP3 96–128 kbps. Total music ≤ 15 MB.

| id | use | length | brief |
|---|---|---|---|
| `mus_title` | title screen | 90–120 s, loops | wide, hopeful, slow synth pads + soft piano, distant planet, 70 BPM |
| `mus_day_1`, `mus_day_2` | normal play, day | 150–180 s each | calm ambient electronic, warm pads, light pulse, curious, 80–90 BPM |
| `mus_night` | normal play, night | 150 s | sparse, cool, low drones, gentle bells, 60 BPM |
| `mus_tension` | active hazard, critical alert, breach | 90–120 s | low pulse, rising strings/synth ostinato, tense but not horror, 100 BPM |
| `mus_arrival` | a ship lands (short cue) | 20–30 s | bright brass-synth swell |

Music director (`ui/music.gd` or inside `ui/audio.gd`): state from the sim — title / day / night /
tension. Crossfade 4 s. Do not restart a track when the state does not change. Day tracks
alternate. Tension holds for at least 30 s after its cause clears. Silence gap 5–20 s between
tracks (deterministic from a local counter, not the sim RNG). Music bus default 0.5 (exists).

### 2.2 World sounds (positional)
**Changed 26 Sep (Paul):** local sounds (doors, airlock, machines, construction, ramp, turret, ship engines) play only when the camera is zoomed in: zoom factor full at ≤ 20 m camera distance, silent at 35 m; source factor full within 8 m of the focus, silent at 25 m. Meteor impact, quake and storm stay audible at every zoom, quieter when zoomed out.

RENDER calls `main.audio.world(name: String, pos: Vector3)` for events it shows; UI plays them with
distance fall-off from the camera focus (inaudible beyond 120 m) and a limit of 3 of one name at a
time. New SFX (Eleven SFX): `door_slide`, `airlock_seal`, `airlock_pump` (loop 3–4 s),
`airlock_vent`, `ship_descent` (loop), `ship_touchdown`, `ship_takeoff`, `ramp`, `meteor_impact`,
`turret_fire`, `quake_rumble`, `storm_loop`, `trade_chime`. Existing: `airlock`, `construct`.

---

## 3. Doors and doorways — solid, full height (ART-HAB builds; RENDER shows)

Paul: the doors "are half done". Today the upper door leaves are hidden while a door is open
(V3 J2 hood rule), and in the cutaway the door is cut with the wall. Both read as unfinished.

1. **Door kit (replaces `doorway.glb` leaves and the hood rule).** A door is a frame (posts,
   header, threshold plate), two leaves and two pockets. Leaves: full clear height (2.1 m), ≥ 6 cm
   thick, opaque, with a narrow window strip and a seal line. Each leaf slides into a **pocket that
   is part of the frame**, so an open leaf is never outside the model and **nothing is ever
   hidden**. Header carries a status light: green (free), amber (cycling or busy), red (locked:
   breach, hazard shelter).
2. **Cutaway.** When the roof lifts and the wall is cut down, the door frame and leaves are cut at
   the same height with a **solid cap** (no hollow shells, no back faces seen). Roof on: full door.
3. **Decals hide at doorways.** Every outer-wall decal — colour stripe, window band, sign, room
   name, number, light strip, vent — is split per wall segment (the 32 segments of V3 §7.2) and named
   `Decal_<seg>_*`. RENDER hides every decal whose angular span meets the doorway opening plus a
   0.4 m margin on each side. The room-name sign moves to the free segment nearest its default
   angle. **Acceptance:** zero decal pixels inside any door opening, in game, on every room type.
4. **Corridor side.** The corridor tube meets the frame with a collar; no gap, no overlap
   > 1 cm, no z-fighting. Door opens when a body is within 1.6 m of its centre line and closes 0.8 s
   after the last body leaves; animation 0.6 s ease-in-out; `door_slide` sound.

## 4. Colonist paths — smooth, around furniture, never through walls (RENDER; SIM for outside)

Paul: "the NPCs still travel through walls and habitats"; "paths need to be smoother and dodge
furniture".

1. **Inside.** A body moves between two rooms only by: its point → the room's aisle graph → the
   doorway centre line → the corridor centre line → the next doorway → aisle graph → target. Inside
   a room the path is string-pulled in free floor (furniture footprints + 0.30 m clearance are
   blocked) and the corners are rounded (minimum turn radius 0.4 m). Speed ramps up and down
   (≤ 1.5 m/s²); heading turns at ≤ 300°/s; the walk/run clip rate follows the real speed (V3 §3.4).
2. **Outside.** Suited bodies never cross a structure footprint, a corridor tube, a cable pylon or
   a landing pad in use. SIM: the nav grid blocks every footprint + 0.6 m and every corridor strip;
   a test proves no outside path cell is blocked (`v31_outside_paths_clear`). RENDER smooths the
   polyline the same way as inside, without cutting a blocked cell.
3. **No teleports.** When the sim moves a body between two places that are not adjacent on its path
   (airlock cycle end, load, a job change), RENDER walks the body along a real path, or, if the gap
   is > 25 m, fades it out and in (0.3 s). Never a straight slide through geometry.
4. **Check tool (RENDER), a delivery gate:** `tools/render_path_check.gd` runs `showcase_v3_late`
   and `scene_final` for 10 game minutes at speed 4, samples every visible body every frame and
   counts: (a) body inside a wall band (±0.25 m of the wall radius) outside a door opening;
   (b) body inside a furniture footprint it does not use; (c) outside body inside a structure,
   tube or pad; (d) speed > 2 × the clip speed (a slide). **Target: (a) (c) (d) = 0; (b) ≤ 0.2 %
   of samples.** Results to `art/npc/path_check.json`.

## 5. Airlocks — a real cycle with a middle chamber (SIM, ART-HAB, RENDER, ART-NPC)

1. **Model (ART-HAB), every airlock size.** Three zones in a line: **suit room** (inside the base:
   lockers, suit racks, bench, air refill ports) → **inner door** → **pressure chamber** (floor
   grating, vent grilles, pump housings, pressure gauge panel, warning beacon, window to the suit
   room) → **outer door** → **porch** outside (ramp, floodlight, dust mat). Chamber capacity is
   `airlock_slots` for that size; mark each standing place with an anchor `Anchor_Chamber_<i>`, and
   suit places with `Anchor_Suit_<i>`. The exterior reads as an airlock at game distance (bulky
   chamber, hazard stripes around the outer door, beacon).
2. **Cycle phases (SIM).** Keep the current cycle length and throughput unless a test needs a
   change. Add phase data to `lock.cyc`: `phase` ∈ `enter`, `seal`, `pump`, `open`, `exit` and `pt`
   (seconds left in the phase), deterministic. Outbound `pump` = depressurise, inbound = pressurise.
   Expose them in the view snapshot for RENDER and UI.
3. **What the player sees (RENDER).** Riders walk from the suit room (or the porch) to the chamber
   anchors; the inner or outer door closes; the chamber light goes amber, then red (outbound) or
   green (inbound); vent particles and `airlock_pump` / `airlock_vent` sounds; the far door opens;
   riders walk out. The body swaps suit ↔ indoor variant at a suit anchor, never in the chamber and
   never outside.
4. **Suit up / suit off (ART-NPC).** One clip `suit_swap` (2.0 s, standing, both variants, hands to
   chest and helmet) so RENDER can cut between variants at its middle frame.
5. **Queue.** Waiting bodies stand at free suit-room anchors or on the porch, 0.8 m apart (V3
   round 8 rule), never in the chamber while it cycles.

## 6. Ships and visitors (SIM owns rules; ART-B builds ships; ART-NPC dresses visitors; RENDER shows; UI trades)

### 6.1 Rules (SIM, `content/ships.json`, `content/trade.json`)
- **Landing pad** (exists) takes one ship. More pads → more ships at once.
- **Traffic schedule.** Deterministic from the seed, like hazards (V3 §4.1): a queue of arrivals,
  each shown to the player one in-game day ahead with kind, time, stay and what it wants. First
  arrival not before day 4 and only when a powered pad exists. No landing during a storm, meteor
  shower or quake: the ship holds in orbit (up to 6 h), then leaves.
- **Player choice.** Grant or deny each landing (command `traffic_answer {id, grant}`). Default
  grant. A denied ship leaves; no penalty except the lost offer.
- **Credits.** New colony counter `credits` (not an item, not carried). Earned by selling, by
  visitors' fees; spent at traders. Shown in the top bar.
- **Ship kinds** (all content data):

| kind | brings | wants | stay |
|---|---|---|---|
| `trader` | stock of 6–10 item types at prices | buys 4–6 item types | 6 h |
| `shuttle` (immigrants) | 2–6 colonists with roles; player accepts 0..n | beds and air for those it leaves | 1 h |
| `liner` (tourists) | 3–8 tourists; each pays a fee by comfort (cantina, lounge, food, beds, morale) | beds, meals | 1 day |
| `medical` | 1–4 injured or ill visitors | a medical bay; pays credits or medicine per treated visitor | until treated, max 1 day |
| `science` | 2–3 visiting scientists work in labs (+research) | buys research packs, exotic crystals | 1 day |
| `inspector` | one inspector tours 4–6 rooms | a score from goals and room health → credits | 4 h |

- **Visitors are agents** with `kind: visitor`, `vkind`, a ship id and a leave time. They walk (suited)
  from the pad to an airlock, use the airlock, rooms and furniture like colonists, never take jobs,
  eat paid meals, sleep in free beds. They count for air and food. If the colony cannot hold them
  (no air, no free bed), they stay on the ship and the fee drops. They leave on time; a visitor
  who is not back at the pad at take-off time is left behind as a colonist only if the player
  accepts (shuttle) — otherwise the ship waits up to 1 h, then leaves and the visitor boards the
  next ship of its kind (keep it simple and deterministic; SIM chooses and documents).
- **Trade (SIM + UI).** Items move between the pad's ship and storage by carriers (real carrying,
  like cargo pods). Prices in `content/trade.json` per item: base, ± a seeded spread per ship.
- **Tests:** schedule determinism and save mid-visit; ledger stays `{}` with trade (credits are
  outside the item ledger but have their own ledger check); v3 saves load (no traffic until a pad
  exists); tourists never block colonists' beds when colonists need them.

### 6.2 Ship models (ART-B) — `assets/models/ship_<kind>.glb`
Six ships, one style family (same panel language, palette and decals as the Meridian and the
lander), different silhouettes: `trader` (boxy freighter, cargo pods, crane arm), `shuttle`
(passenger shuttle, window row), `liner` (sleek tourist liner, large windows, colour band),
`medical` (white, red markings, cross), `science` (sensor dish, antenna mast, blue), `courier`
(small, used by the inspector). Footprint fits the pad (radius 9 m); height ≤ 18 m. Each has named
nodes for animation: `Leg_*` (fold 0 → 1), `Ramp` (closed → open), `Thruster_*` (empty points for
flames and dust), `Door_*`. ≤ 12,000 triangles, ≤ 8 materials, baked AO as for other exteriors.
Upgrade the **landing pad**: markings, edge lights, fuel line, control kiosk, blast deflector.

### 6.3 Landing and take-off (RENDER)
Descent 20 s from 150 m on a curved approach, braking thrust, dust ring at < 20 m, legs unfold at
40 m, touchdown bump, ramp opens, engine glow fades; take-off reverse, 15 s. `ship_descent`,
`ship_touchdown`, `ramp`, `ship_takeoff` sounds; `mus_arrival` cue. Night: landing lights and pad
lights. The ship casts a shadow.

### 6.4 Visitors' looks (ART-NPC)
Variants on the existing rig and meshes (material/texture changes, small attachments allowed within
the triangle budget): suit and indoor clothing for `trader` (orange and grey), `tourist` (white with
bright accents, three colour sets), `medical` (white and red), `science` (blue and white), `inspector`
(black and gold). Colonists keep their current looks. A visitor is recognisable at game distance.

### 6.5 Interface (UI)
- **Every window stays inside the view** (Paul, 25 Sep): panels, dialogs, popups, tooltips, cards, toasts and menus are clamped into the viewport (8 px margin) on open, resize, content growth and drag; larger than the view means shrink + scroll. Test `tools/ui/test_window_bounds.gd` at 1920×1080, 1280×720, 800×600.
- **Traffic panel** (like the hazard panel): arrivals with countdown, kind, what they bring and want,
  Grant / Deny.
- **Trade screen** at a landed trader or science ship: buy and sell lists, prices, quantities,
  credits after the trade, what storage can hold.
- **Shuttle screen**: pick which immigrants to accept (role, needs); warns when beds or air fall
  short.
- **Visitors** tab in the colonist list; visitor inspector card (kind, ship, leaves in, paid).
- Credits in the top bar; events in the log; `__fh` commands `traffic`, `ship <kind>` (debug:
  schedule a ship in 60 s), `trade`.

---

## 7. Content and save (SIM)

Save schema 4: `traffic` queue, `credits`, visitor agents, `lock.cyc.phase/pt`. v3 and v2 saves load
(migrate: empty traffic, credits 0). New showcase save `showcase_v31.fhsave`: late colony with two
pads, a trader landed, a liner's tourists in the cantina, an airlock mid-cycle.

## 8. CRITIC subjects for 3.1

| subject | evidence |
|---|---|
| `doors` | Blender renders of the door kit closed / half / open, roof on and cutaway; in-game shots |
| `doorway_decals` | in-game shots of every room type with 1–4 doorways; no decal on an opening |
| `airlock` | Blender renders all sizes (outside, cutaway); in-game cycle strip, outbound and inbound |
| `npc_paths` | in-game frame strips (10 frames at 30 fps) of bodies crossing rooms around furniture, through doorways, outside around structures; `path_check.json` |
| `ships` | turnarounds of the six ships and the pad; in-game landing and take-off strips, day and night |
| `visitors` | visitor lineup; in-game shots of tourists in the cantina, a trader carrying cargo, scientists at a lab |

Plus the V3 subjects that these changes touch must not drop below their last score.

## 9. Order of work and pilots

1. **SIM**: airlock phases (so RENDER can start) → outside path clearance + test → traffic schedule,
   ship kinds, visitors, credits, trade → saves, showcase save, tests, perf.
2. **ART-HAB**: door kit + decal split on habitat M + airlock M → **pilot critic** → all rooms, all
   airlock sizes, landing pad upgrade.
3. **ART-B**: `ship_trader` + pad → **pilot critic** → the other five ships.
4. **ART-NPC**: `suit_swap` clip → visitor variants → sheets → `npc_verify.py`.
5. **RENDER**: path system + `render_path_check.gd` first (the defect) → doors/decals → airlock cycle
   → ships, landing, visitors → world sound calls → perf.
6. **UI**: music + SFX + audio director + latency (with `audio_probe.mjs`) → traffic panel → trade
   and shuttle screens → visitors → `__fh`.
7. **CRITIC**: pilot rounds, then full rounds until every subject passes.
8. **Orchestrator**: integrate, `build/web`, full tests, audio probe, final critic round, report.

## 10. Ownership

As V3_DESIGN §10, plus:

| path | owner |
|---|---|
| `tools/blender/ship_*.py`, `assets/models/ship_*`, `art/ships/**` | **ART-B** |
| `content/ships.json`, `content/trade.json` | **SIM** |
| `ui/music.gd`, `assets/audio/**`, `tools/ui/audio-events.json`, `default_bus_layout.tres` | **UI** |
| `tools/render_path_check.gd` | **RENDER** |
| `docs/V3_1_DESIGN.md`, `tools/audio_probe.mjs` | **orchestrator** |

Requests: `docs/requests/<FROM>-to-<TO>.md`. Progress: append a dated "v3.1" section to
`docs/progress/<AGENT>.md`.
