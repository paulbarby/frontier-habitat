# Frontier Habitat 3.0 — astronauts, interiors, hazards, research packs

Version 3.0 · 24 September 2026 · Owner: orchestrator

This file is the contract for version 3.0. It adds to `docs/AAA_DESIGN.md` (the v2 contract).
**Every agent reads `AAA_DESIGN.md` §0, §1, §10–§15 and all of this file before it starts.**
Where the two files disagree, this file wins. The numbers live in `content/*.json`.

Paul's request, in his words (voice note, lightly cleaned):
*"Do an upgrade on the NPC characters. Use the supplied tools and generate proper astronauts. Mesh
them and rig their animations properly. Make sure they have seamless transitions. Once they are
animated and rigged, check them for consistency. I need the habitats properly rendered in high
detail, and the NPCs need to interact with the beds, chairs, and machines appropriately. I need the
corridors to create doorways in the habitats so that they are rendered correctly with proper
doorways. I need the lighting done so that the interior of the habitats looks spacious and exciting
with nice lighting, looking modern. There was an issue with alerts that repeatedly pop up and
disappear when a regolith mining machine's output was blocked. The map needs to be 10 times bigger
and the build space a lot bigger. There need to be challenges that cause issues, scalable on the
map, such as meteor strikes, wind storms, other random events, and equipment breakdown that
requires repair. They need to be fully deterministic so they can be calculated and addressed. The
research should need something that is produced or bought in to increase research speed — research
packs, e.g. made from water and power — and the research system should be more complex. Use a
critic agent to judge the visual styles and outputs for the NPCs and habitat upgrades for
consistency, visual appeal and adherence to style, and give a rating 0–1. Any average below 0.65 is
a fail and needs to be critiqued and redone."*

"Supplied tools" = Blender 5.2 (background only) and Godot 4.4.1, plus the project's `tools/`.

---

## 0. Ground rules

All of `AAA_DESIGN.md` §0 still applies. In particular: **never open a window on Paul's desktop**;
Godot only through `node tools/godot.mjs`; Blender only with `--background`; export web builds to
`build/web_<you>/`; no downloads, no installs; keep `node tools/godot.mjs check` clean; the
simulation is authoritative and deterministic; the ledger stays `{}`; player text in plain STE
English; report honestly.

New:
1. **Visual gate.** Nothing visual is "done" until the CRITIC (§9) passes it. Pilot first: ART-NPC
   delivers one finished suit model + 3 clips, and ART-HAB delivers the habitat M interior + the
   doorway, to a **pilot critic round** before anyone mass-produces.
2. **Performance budget (web, `shoot.mjs --gpu`, this PC):** overview of the late-colony save with
   ~70 colonists ≥ 50 fps at quality "high"; draw calls ≤ 1,400; sim tick ≤ 2.0 ms mean at 70
   colonists. Report the numbers you measured.
3. **Old saves load.** v2 saves (256 m map) load and play on their old map size. Save schema 3.

---

## 1. Map and build space (SIM, RENDER, UI)

- **"10 times bigger" = 10× the area.** New games: `map_size` **810** (256 → 810 per side,
  10.0× area). 10× per side (2,560 m, 6.5 M nav cells) does not fit the web build; do not attempt it.
- `state.map_size` stores the size. Old saves keep 256. Reference layouts and tests place things
  **relative to the lander**, never at absolute map coordinates.
- `map_margin` 8. **Build space**: at least 70% of the map area is buildable for a room of radius 5
  (slope and rocks), measured by a test and reported. A flat **start plateau** of radius ≥ 120 m
  around the lander.
- World generation spreads interest over the whole map: ore fields near and far, silicate flats,
  **exotic fields ≥ 200 m from the lander**, crater fields, rock ridges, a canyon or two. The
  Meridian stays 55–75 m from the lander.
- **Hazard zones** (§4 "scalable on the map"): world gen writes three smooth fields —
  `meteor`, `wind`, `quake` — multipliers 0.5..2.0. `sim.world.hazard_at(pos) -> {meteor, wind,
  quake}`. Ridges and high ground are windy; an impact basin is meteor-prone; a fault line is
  quake-prone. RENDER draws them as an overlay `hazard`.
- **Reach**: suit air stays the base rule. New research `suit_1` (+50% suit air) and `suit_2`
  (+120%) let colonists work further from an airlock. Forward airlocks stay the main answer.
- Budgets: world gen ≤ 3 s in the web build; nav build ≤ 1 s; path cost must not break the tick
  budget (use `AStarGrid2D` jumping or a coarse graph for long trips — SIM decides).
- RENDER: terrain in chunks with LOD (whole map visible when zoomed out, full detail near the
  camera); camera can pan the whole map and zoom out to about 450 m. UI: minimap shows the whole
  map, with the camera frustum, the colony and the hazard markers.

---

## 2. Alerts — the flicker defect (SIM, UI)

**Defect** (Paul): an alert pops up and disappears again and again when a regolith harvester's
output is blocked. Cause: `blocked:<id>` is raised when the output buffer is full and cleared when a
carrier takes one unit; the buffer fills again seconds later. The toast shows every time.

**Rule for every alert** (SIM, `sim/alerts.gd`):
- **Raise** only after the condition is true for `raise_after` seconds: notice 20 s, warning 5 s,
  critical 0 s.
- **Clear** only after the condition is false for `clear_after` = 30 s.
- A kept alert keeps its first `since` tick.
- Per-machine "output blocked" alerts become **one** alert `output_blocked` that lists the machines.
- Numbers in the alert text must not change the alert identity (the key is stable).

**UI toasts** (`ui/**`): a toast shows only when a key is new. The same key does not toast again for
180 s after it cleared. Severity-1 notices never toast; they show only in the alert list.

**Test** (SIM): a harvester whose output is emptied by a carrier every few seconds for 300 s raises
`output_blocked` once and never clears it in between. UI test: one toast in the same 300 s.

---

## 3. NPCs — astronauts (ART-NPC builds, RENDER plays)

### 3.1 Look
Clean industrial frontier (AAA_DESIGN §1). A believable near-future astronaut, not a cartoon, not
a toy: readable at the game camera (colonist ≈ 30–80 px tall), detailed when zoomed in.

- **`assets/models/astronaut_suit.glb`** (outside): helmet with a gold-tinted reflective visor
  (`Visor`), helmet lamps, neck ring; hard upper torso; life-support backpack (`Pack`) with vents and
  two small status lights (`Light`); soft limbs with bellows rings at shoulders, elbows, knees;
  gloves with a wrist ring; boots with thick soles; chest control box; a role stripe on the upper
  arms and the helmet (`SuitAccent`, recoloured per role by the game); off-white `SuitMain`.
- **`assets/models/astronaut_indoor.glb`** (inside): the same body and skeleton in a fitted
  jumpsuit (`Jumpsuit`, dark navy #243247) with `SuitAccent` shoulder panels and collar; boots;
  a head with a simple, calm face (no uncanny detail), **4 hair variants** as objects `Head_0`…
  `Head_3` (the game shows one per colonist), skin material `Skin` (the game tints it from a palette
  of 6 tones per colonist).
- **One skinned mesh per variant** (not rigid parts), smooth weights, max 4 influences per vertex,
  weights normalised. Triangles: suit ≤ 7,000, indoor ≤ 6,000 (Godot makes LODs on import).
- Height: 1.80 m standing (helmet top ≤ 1.88 m). Origin on the ground between the feet. **Faces +X.**
  Metres, Blender Z up, glTF +Y up, transforms applied.
- Vertex-colour AO baked as COLOR_0, as for every model.

### 3.2 Skeleton (both variants — identical names, rest pose and lengths)
`root` → `hips` → `spine` → `chest` → `neck` → `head`;
`chest` → `shoulder.L/R` → `upper_arm.L/R` → `forearm.L/R` → `hand.L/R` → `prop.L/R`;
`hips` → `thigh.L/R` → `shin.L/R` → `foot.L/R` → `toe.L/R`.
`prop.R` is where a carried crate or a held tool attaches. No other deform bones. `root` never
moves in the clips (**no root motion**; the game moves the character).

### 3.3 Clips (exact names, 30 fps, embedded in **both** GLBs)
| clip | kind | pose | notes |
|---|---|---|---|
| idle | loop | stand | breathing, weight shift, 4 s |
| idle_look | loop | stand | looks around, 6 s |
| walk | loop | stand | `speed_mps` and stride in the metadata |
| run | loop | stand | hurry (emergencies) |
| carry_walk | loop | stand | arms forward holding a crate at `prop.R` |
| carry_idle | loop | stand | |
| work_console | loop | stand | types at a console 1.0 m high, 0.45 m ahead |
| work_bench | loop | stand | tool work at a bench 0.9 m high |
| talk | loop | stand | hand gestures |
| kneel_enter / repair_kneel / kneel_exit | enter / loop / exit | stand↔kneel | repair a panel 0.45 m ahead, 0.4 m high |
| sit_enter / sit_idle / sit_eat / sit_type / sit_exit | enter / loop / loop / loop / exit | stand↔sit | seat top 0.46 m, 0.30 m behind the stand point |
| lie_enter / sleep / lie_exit | enter / loop / exit | stand↔lie | mattress top 0.55 m, bed centre line 0.55 m behind the stand point, head to local +Y |
| injured_walk | loop | stand | limp |
| collapse / dead | oneshot / hold | stand→lie | |
| cheer | oneshot | stand | awards |

**Metadata** `assets/models/astronaut_anims.json`: `{fps, height, clips: {name: {frames, kind,
pose_from, pose_to, loop, speed_mps?, stride_m?}}, furniture: {seat_z, seat_back, bed_z, bed_back,
console_z, console_ahead, bench_z, panel_ahead, panel_z}}`. The furniture numbers are the ones in
the table above; ART-HAB builds furniture to them.

### 3.4 Seamless transitions (RENDER)
- A state machine per character (AnimationTree or equivalent): pose states **stand, sit, lie,
  kneel**. Changing pose always plays the enter/exit clip. Loops in the same pose cross-fade
  over **max(0.25 s, largest bone angle change ÷ 300°/s), at most 0.6 s** (decision 24 Sep),
  blending per-bone local rotations with **quaternion slerp** (never a matrix or basis lerp).
  Walk ↔ run blending keeps the two cycles **phase-synchronised** (normalised cycle time).
  Non-deform bones `prop.*` are not part of the pop test; a held crate eases in. Locomotion blends idle ↔ walk ↔ run by the real ground speed, and **playback speed =
  speed / stride** so feet do not slide. Carrying is an upper-body layer over the locomotion.
- A character must never snap: position and facing ease; the enter clip starts only when the
  character stands on the anchor, facing the anchor direction.
- Performance: RENDER chooses the method (skinned meshes near the camera, a cheaper form far away,
  throttled updates) inside the §0 budget.

### 3.5 Consistency checks (both sides — a failed check is a failed delivery)
ART-NPC, `tools/blender/npc_verify.py` → `art/npc/npc_report.json` + `.md`:
identical skeleton in both files; every clip present in both; **loop seam** (first vs last frame)
≤ 1° on every bone; enter/exit clips start or end exactly on the rest poses of their pose states
(stand pose = `idle` frame 0, sit = `sit_idle` frame 0, lie = `sleep` frame 0, kneel =
`repair_kneel` frame 0) within 1°; foot slide during ground contact in `walk`/`run` ≤ 2 cm; feet
never below z −0.01; no bone scale keys; weights ≤ 4 and normalised; triangle budgets; material
names. Render sheets: `art/npc/turnaround_suit.png`, `turnaround_indoor.png`, `clips_suit.png`,
`clips_indoor.png` (every clip at 4 frames), `transitions.png`.
RENDER, `tools/npc_check.gd` (run with `node tools/godot.mjs script`): loads both GLBs, finds every
clip, drives the state machine through **every pose-to-pose transition** and every loop-to-loop
change, and fails if, in a transition or cross-fade frame, a bone rotates more than 15° between
two 30 fps frames **and** more than 1.25 × the largest in-clip step of the source and target clips
(a pop), or if the character's root jumps more than 0.1 m in one frame. Locomotion loops at
speed-matched playback have no fixed per-frame limit (decision 24 Sep). **`run` is the normal
travel pace**: a light suited jog of about 3.4 m/s (the simulation moves colonists at 3.2–3.6 m/s);
`walk` (about 1.1 m/s) is for short moves inside rooms. Writes `art/npc/godot_check.json`.

---

## 4. Hazards — deterministic challenges (SIM owns; RENDER shows; UI forecasts)

### 4.1 Determinism
All hazards come from the `hazard` random stream and the state. The scheduler keeps a **queue** of
future events at least `horizon_days` (2) ahead. Draws happen only when the queue is extended, at
fixed ticks. Same seed + same commands = same events, same places, same results. A command can
change what an event **does** (a turret, a shelter order, a repair), never **whether or where** it
happens. So every event can be forecast, calculated and addressed.

`state.hazards = {next_id, queue: [ev…], active: [ev…], done_count: {kind: n}, wear: {}}`.
Event: `{id, kind, at, end, pos, radius, severity 1..3, path?, detected_tick, phase:
"scheduled"|"forecast"|"warning"|"active"|"done", countered, hits: [], result: {}}`.
The v2 `state.events.storm` migrates into this (kind `dust_storm`).

### 4.2 Scale ("scalable on the map")
Rate per kind = `base_per_day` × difficulty × ramp(day) × colony factor (√(structures / 20),
clamped 0.5..2.5). Severity rises with the chapter. Local events pick a place from the hazard zone
field (§1) weighted towards the colony (inside 150 m of a structure with probability `near_p`).
Nothing before the scenario's `no_disaster_days`; the first event of each kind is severity 1.
Hazard setting on the new-colony screen: off, mild, normal, hard (`options.hazards`).

### 4.3 Kinds
| kind | where | warning | effect | how to address it |
|---|---|---|---|---|
| meteor | point, radius 4–12 m | detection lead (below) | structures in the radius lose 40–100 health by distance; a room hit gets a **hull breach** (air leaks until repaired); outside colonists hurt; leaves a crater and a **fragment site** (exotic + ore) | **Meteor Defense turret** (new exterior, covers 70 m, charge per shot, intercepts while it has charge); build away from the impact basin; repair |
| meteor_shower | 3–8 strikes over 60 s in a 60 m zone | as meteor | as meteor | turrets; keep people inside |
| wind_storm | whole map, strength × zone `wind` | 90 s | exterior wear × strength; wind turbines ×1.8 output but take damage unless feathered; solar ×0.7; outdoor walking ×0.6 | research **Storm anchoring** (exterior damage −60%, turbines feather); repair |
| dust_storm | whole map | v2 rule | v2 rule (solar and walking) | batteries |
| quake | point, radius 60–150 m, × zone `quake` | 20 s (seismograph research: 90 s) | corridors in the radius may crack (breach); structures lose health | research **Seismic dampers** (−70%); repair |
| solar_flare | whole map | 120 s | colonists outside take radiation damage; electronics fab, research lab, comms tower and turrets trip off for the flare | order **Shelter** (everyone goes inside); research **Surge protection** |
| dust_devil | a moving path 80–200 m | 30 s | solar panels on the path lose 50% output (dust) until cleaned (cleaning job, anyone); light damage | clean; build away from flats |
| breakdown | one machine | forecast by wear (below) | the machine breaks (v2 "broken") with a **fault**: mechanical (spare_parts), electrical (electronics), seal (polymer) | **preventive maintenance** before the threshold; repair after |

**Breakdown is deterministic wear, not a dice roll at the moment.** Every machine has `wear` 0..100
(runs up with operating time × level `wear_mult` × zone × storm effects) and a failure threshold
`fail_at` drawn from the hazard stream when the machine is built or repaired (60..100). When
`wear ≥ fail_at` it breaks. The forecast shows machines above 75% of their threshold and the time
to failure at the current rate. **Maintenance** (technician, work 20, 1 part of the fault type's
item) resets wear to 0 and draws a new threshold. Command `maintain {id}` puts it first.

**Detection lead** for meteors: base 45 s; Comms Tower +90 s; research **Deep-space radar** +120 s.
Before detection an event is "scheduled" and hidden from the player (the UI does not show it; tests
can). **Countered** means the colony's current defences cover it (turret in range with charge, a
research, sheltered).

**Repairs**: hull breach (room or corridor) → repair job, technician, 1 hull_plate (or 2 metal),
work 30; air leaks at `breach_drain_per_day` until done. Damage → existing repair rule.

### 4.4 Interface (SIM implements; UI and RENDER call)
`sim.hazards.forecast() -> Array[{id, kind, name, eta_s, pos, radius, severity, countered,
advice}]` (detected events only) · `sim.hazards.active()` · `sim.hazards.zone_at(pos)` ·
`sim.hazards.at_risk() -> Array[{id, wear, fail_at, eta_s, fault}]` · `sim.hazards.info(id)`.
Commands: `shelter {on}`, `maintain {id}`, and for tests and screenshots only
`hazard_now {kind, pos, severity}` — accepted only when `state.options.debug` is true (boot param
`debug=1`); it is a recorded command, so replays stay deterministic.
Log events and alerts for: detected, warning, impact/start, end, breach, fault, repaired.

### 4.5 Visuals (RENDER)
Meteor: ground target ring with a countdown while forecast; a burning streak with a trail for the
last 3 s; flash, shockwave ring, debris, dust; a permanent crater decal and a fragment pile; a turret
tracer and an air burst when intercepted. Wind storm: fast dust sheets, turbines spin up, bending
antennas. Quake: camera shake (respect a settings toggle), dust puffs, crack decals. Solar flare:
aurora and a violet-green grade outside. Dust devil: a turning dust column that moves along its
path. Breakdown: sparks and smoke at the machine, a fault icon. Breach: a white air jet.

---

## 5. Research — packs and a deeper tree (SIM; UI; ART-HAB builds the new building)

### 5.1 Research packs (new item category `science`)
| item | name | made in | recipe | also from |
|---|---|---|---|---|
| pack_basic | Basic research pack | Research Assembler | water 1 + power, 40 s (M, L1) | supply runs, goal pods |
| pack_applied | Applied research pack | Research Assembler (`sci_packs_2`) | glass 1 + electronics 1 + water 1 | supply runs |
| pack_exotic | Exotic research pack | Research Assembler (`sci_packs_3`) | exotic 1 + composite 1 + electronics 1 | meteor fragment sites (rare) |

- **Research Assembler** (`research_assembler`): room, science, automatic machine (no worker),
  sizes S–XL, levels, research `sci_packs_1` (tier 1, cheap). The player chooses the recipe. Model:
  a clean-room hall with a robot arm over a conveyor, pack racks, a water line (ART-HAB).
- **Labs** take packs as input (hauled like any machine input, `input_cap`).
- **Research without packs** runs at the v2 base rate for tier 1 techs only. Every tech has
  `packs: {item: n}` as well as RP. A lab only advances a tech that needs packs while it holds them;
  the packs are used in proportion to the RP. **A lab that holds the tech's pack type works ×2**
  (`pack_boost`, content). Tier 1 costs no packs but still gets the ×2 boost from basic packs.
- Tier 2 needs basic packs; tier 3 basic + applied; tier 4 applied; tier 5 (special research)
  **exotic packs** (these replace the v2 exotic-crystal delivery; migrate paid progress).
- **Bought in**: the Meridian supply run gets a **cargo choice** — `ship {action: "supply_run",
  cargo: "science" | "medical" | "industrial"}`; science brings basic 12 + applied 4 packs. Goal
  reward pods include packs.

### 5.2 A deeper tree
- About 45 techs (29 now). New branches: **Hazards** (Deep-space radar, Meteor defense I/II, Storm
  anchoring, Seismic dampers, Surge protection, Predictive maintenance: breakdown forecast +50% lead
  and wear −20%), **Suits** (suit_1, suit_2), **Science** (sci_packs_1..3, Lab automation: a lab
  works at 30% with no scientist, Data network: +10% RP per extra connected lab, max +30%).
- **Lab focus**: each lab can set a focus branch (`set_focus {id, branch}`): +25% RP for techs of
  that branch, −10% for others.
- **Field samples**: a meteor fragment site can be surveyed (exterior job, scientist, work 30):
  it gives exotic crystal and ore and 40 RP, and sometimes one exotic pack.
- Tests: pack consumption conserves units (ledger `{}`); research without packs stops at tier 2;
  the ×2 boost; supply-run cargo; migration of v2 research state.

---

## 6. NPCs use the furniture (SIM, ART-HAB, RENDER)

**SIM** writes on every agent `use = {kind, b, i, pose, act}` or `{}`:
`kind` bed | seat | work | stand | service; `b` building id; `i` slot index (lowest free index,
deterministic); `pose` stand | sit | lie | kneel; `act` sleep | eat | relax | work | repair | heal |
talk | idle. Examples: sleeping in a habitat → bed; eating in a kitchen or cantina → seat, act eat;
lounge/cantina recreation → seat or stand (talk); staffed machine or lab → work (stand or sit per
building, content `work_pose`); patient in medical → bed, act heal; exterior repair or maintenance →
service, kneel. `sim.agents.use_of(id) -> Dictionary`. The simulation position stays as it is
(building centre); the view places the body.

**Content** (SIM): per building size arrays `beds`, `seats`, `work_slots`, `stands` (standing
spots for extra occupants) and `work_pose` ("stand" | "sit"). ART-HAB builds exactly that many
anchors for each size. **RENDER** walks the colonist from the doorway it entered by to the anchor
inside the room (simple path around furniture: via the room's `Anchor_Aisle_*` points if present),
turns it to the anchor direction, then plays the enter clip. If an anchor is missing it falls back
to a standing ring position — and logs it once (ART-HAB must fix it).

**Anchor convention** (empties in the room GLB, local +X = the direction the person faces, origin
on the floor = the **stand point**):
`Anchor_Bed_<i>`, `Anchor_Seat_<i>`, `Anchor_Work_<i>` (stand or sit per `work_pose`),
`Anchor_Stand_<i>`, `Anchor_Aisle_<i>` (optional walking waypoints), and on exteriors
`Anchor_Service` (kneel point for repair). The furniture sits relative to the stand point exactly as
§3.3 says (seat 0.30 m behind at 0.46 m; bed centre 0.55 m behind at 0.55 m, head to local +Y;
console 0.45 m ahead at 1.0 m; bench 0.9 m; panel 0.45 m ahead at 0.4 m). Floor top is the room's
`FLOOR_Z` (rooms_kit.py) — the view adds it.

---

## 7. Interiors, doorways and interior lighting (ART-HAB builds; RENDER lights and cuts)

### 7.1 Interiors — "properly rendered in high detail"
Every room type (all `kind: room` buildings, the new research assembler, airlock, junction) gets a
detailed `Interior` for every size: a floor with a panel pattern and a lit edge strip; furniture
that says what the room does; wall-side lockers, cabinets, screens, pipes, plants; the anchors of §6.
Examples: habitat — single beds with pillows and blankets (`Fabric`), bedside units with lamps,
lockers, a shared table; lounge — sofas, a big wall screen, plants, a rug; cantina — bar counter,
stools, tables with chairs, neon; kitchen — counters, cooktops, extractor hood, mess tables; medical
— treatment beds, scanner arch, med cabinets; research lab — desks with monitors, holo table,
sample racks; industrial rooms — the machine, a control console, cable trays, hazard floor
markings; storehouse — shelving with crates; greenhouse/farms — keep the tray contract, add walkways
and irrigation lines. No floating parts, no plain boxes: bevels, trims and inset panels.

Budgets (whole model, interior included): S 10k, M 15k, L 22k, XL 30k triangles; ≤ 14 materials.
Keep the v2 exteriors, silhouettes and level parts (L2..L5) — this round is the inside.

### 7.2 Doorways — "corridors create doorways"
- The round wall (today part of `Base`, up to `WALL_TOP` 1.40 m) becomes **32 separate objects**
  `Wall_00` … `Wall_31`. Segment k spans the angle [k × 11.25°, (k+1) × 11.25°), measured from +X
  towards +Y in the content plane (Blender X = content x, Blender Y = content y).
- **`assets/models/doorway.glb`**: the frame where a corridor meets a room wall. Origin on the
  floor at the wall line, +X pointing out along the corridor. Clear opening 1.5 m wide × 2.1 m high,
  frame 2.2 m wide. Objects `Frame` (with a lit status strip `Lights`), `DoorL`, `DoorR` (sliding
  leaves: they open along ∓Y by 0.75 m), `Sign`. It must meet the corridor tube (corridor radius
  1.2 m — ART-HAB owns `corridor` too, so match them) and look right from above in the cutaway.
- **RENDER**: for each link attached to a room, hide the wall segments inside the doorway width at
  the link's angle and place `doorway.glb` there. Doors slide open when a colonist is within 2 m and
  close after. A room with no links shows its full wall. The airlock keeps its outer door.
- Corridors: a floor with a centre light strip, ribs, handrails, and a cutaway like the rooms.

### 7.3 Interior lighting — "spacious, exciting, modern"
Light, bright interiors: warm-white composite floors, cool white LED cove strips (`LightStrip`
#EAF6FF, emissive 2.5) along the wall top and the floor edge, warm accent pools on furniture,
glowing screens (`Screen`, cyan UI pattern), the room's category accent on one feature element.
ART-HAB places empties `Anchor_Light_<i>` (ceiling lamp positions, 2–6 per room by size).
RENDER turns them into real lights **inside a light budget** (real OmniLight/SpotLight only for the
rooms nearest the camera focus; emissive + a fake light pool for the rest), adds interior light
pools on the floor, and keeps the interiors bright and readable by day and by night (interiors
glow at night through the cutaway and the windows). No dark, muddy rooms.

New materials (ART-HAB, ART-NPC): `LightStrip`, `Screen`, `Jumpsuit`, `Skin`, `Wood`
(#B08560, warm accents), `Cushion` (#3C4A5E), `Floor` (#D9D4CB), `FloorDark` (#6B6F76),
`Rubber` exists. The loader (RENDER) must know them.

---

## 8. Interface (UI)

- **Hazard panel** on the HUD: detected events with icon, name, ETA countdown, severity, place
  (click = camera goes there), "covered" or "not covered", one line of advice. A banner for any
  event under 30 s. **Shelter** button while a flare is warned or active.
- **Maintenance** view (dashboard tab or inspector): machines at risk (wear %, time to failure,
  fault type, "Maintain now").
- **Research screen**: pack cost per tech, pack stock and production, each lab's rate (base vs
  boosted) and focus selector, the new branches in the tree, lock reasons in plain words.
- **Inspector**: research assembler recipe; turret charge and coverage; building wear and fault;
  breach state. **Meridian panel**: supply-run cargo choice.
- **New colony**: hazard setting (off, mild, normal, hard). **Settings**: camera shake on/off.
- Minimap and camera for the 810 m map (§1). Alert toasts per §2.
- New `__fh.cmd` commands for screenshots: `hazard <kind> [x y] [sev]` (needs `debug=1`),
  `follow <agent id>`, `goto <x> <y>`, `interior <building id>` (camera to a room, roof open).

---

## 9. The CRITIC — visual rating gate

The CRITIC is a separate agent that did not build the thing it judges. It rates **subjects**:

| subject | evidence |
|---|---|
| npc_suit, npc_indoor | turnarounds, close in-game shots (day and night) |
| npc_animation | clip sheets, transition sheet, `godot_check.json`, an in-game sequence (walk → sit → eat → stand; walk → lie → sleep → get up; kneel repair) |
| interior_<family> for habitat, comfort (lounge, cantina), medical (medical, bio-lab), food (kitchen, greenhouse, fungus, algae), industry rooms, science (lab, assembler), life (oxygen, recycler, atmo), logistics (storehouse, cold storage), links (airlock, junction, corridor) | Blender renders `art/interiors/<id>_<size>.png` + in-game cutaway shots |
| doorways | in-game shots of rooms with 1–4 corridors at odd angles |
| interior_lighting | in-game cutaway shots by day and by night |
| npc_interaction | in-game shots of colonists in beds, on seats, at consoles, kneeling at a machine |

Three scores per subject, each 0.00–1.00: **consistency** (fits the other assets and the
contract; variants and sizes agree; proportions, palette, detail density), **visual appeal** (looks
good at the game camera and close up; would pass in a shipped game), **style adherence**
(AAA_DESIGN §1 + this file). Subject score = mean of the three. **Pass ≥ 0.65.** Calibration:
0.50 = placeholder quality, 0.65 = acceptable in a shipped indie game, 0.80 = good, 0.90 = excellent.

Output per round: `docs/critic/round_<n>.md` and `.json` — scores, and for every subject under
0.80 a numbered list of concrete fixes (what, where, how much). A failed subject goes back to its
owner, who fixes it and asks for a re-rating. The loop repeats until every subject passes. After
three failed rounds on one subject the orchestrator reports it to Paul with the critique.

---

## 10. Ownership (replaces AAA_DESIGN §15 for this round)

| path | owner |
|---|---|
| `sim/**`, `content/**`, `tests/**` | **SIM** |
| `tools/blender/npc_*.py`; `assets/models/astronaut_*`; `art/npc/**` | **ART-NPC** |
| `tools/blender/build_assets.py`, `rooms_*.py`, new `interior_*.py`, `ext_*.py`, `ext_common.py`; `assets/models/` + `assets/thumbs/` for everything that is not `astronaut_*`; `assets/textures/props/`; `art/interiors/**` | **ART-HAB** |
| `presentation/world_view.gd`, `models.gd`, `camera_rig.gd`, `presentation/fx_*.gd` (new ones allowed), `shaders/**`, `assets/textures/terrain|sky/`, `tools/npc_check.gd`, `tools/render_*.gd` | **RENDER** |
| `presentation/main.gd`, `presentation/boot.gd`, `main.tscn`, `ui/**`, `assets/ui/**`, `assets/fonts/**`, `assets/audio/**`, `project.godot` | **UI** |
| `docs/critic/**`, `art/critic/**` | **CRITIC** |
| `docs/V3_DESIGN.md`, `docs/AAA_DESIGN.md`, `export_presets.cfg`, `tools/godot.mjs`, `tools/shoot.mjs`, `tools/tour.mjs`, `tools/serve.mjs`, `build/web/` | **orchestrator** |

Requests between agents: `docs/requests/<FROM>-to-<TO>.md` (append; date each entry). Progress:
`docs/progress/<AGENT>.md` — append a dated v3 section: what landed, what is next, what you did not
test. Read the requests addressed to you at every milestone.

## 11. Order of work

1. **SIM**: alert fix (§2) → map 810 + zones + `use` slots + content arrays (so ART and RENDER can
   start on real data) → research packs + assembler → hazards → tests, saves, perf.
2. **ART-NPC**: suit model + skeleton + idle/walk/sit clips → **pilot critic** → indoor variant and
   all clips → `npc_verify.py` → sheets.
3. **ART-HAB**: doorway + wall segments + habitat M interior → **pilot critic** → every room, every
   size, anchors per content → research assembler, meteor turret, crater/fragment/meteor props →
   renders in `art/interiors/`.
4. **RENDER**: 810 m terrain + camera → character system with the pilot GLB → doorways → anchors
   and furniture use → interior lights → hazard visuals → `npc_check.gd` → perf.
5. **UI**: toast fix → hazard panel → research UI → maintenance → inspector parts → new-colony
   setting → minimap → `__fh` commands.
6. **CRITIC**: pilot round, then full rounds until every subject passes.
7. **Orchestrator**: integrate, build `build/web`, full tests, final critic round, report.
