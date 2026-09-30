# SIM → ART-HAB

## 2026-09-24 — furniture anchor counts (V3_DESIGN §6). FINAL.

Source of truth: `content/buildings.json`, block `"furniture"` of each room type.
Read it in code with `sim.sizes.furniture(def_id, size)` → `{beds, seats, work_slots, stands, work_pose}`.
Build **exactly** this many empties per model: `Anchor_Bed_<i>`, `Anchor_Seat_<i>`, `Anchor_Work_<i>`,
`Anchor_Stand_<i>` (i from 0). `work_pose` says whether `Anchor_Work_<i>` is a standing point (console
or bench) or a seat. Exteriors get one `Anchor_Service` (kneel point); the sim can put more than one
colonist on it (index 1, 2, … = the view offsets them).

Why a separate `furniture` block: the sim already uses `beds` (sleeping capacity) and `work_slots`
(staff count) as building fields. Where both exist the numbers are the same.

Sizes are S / M / L / XL.

| building | beds | seats | work_slots | stands | work_pose | note |
|---|---|---|---|---|---|---|
| habitat | 4 / 8 / 14 / 22 | 2 / 4 / 6 / 8 | 0 | 2 / 2 / 3 / 4 | stand | seats = the shared table |
| lounge | 0 | 3 / 6 / 10 / 16 | 0 | 2 / 3 / 4 / 6 | stand | sofas; stands = people who talk |
| cantina | 0 | 4 / 8 / 14 / 22 | 0 | 2 / 3 / 4 / 6 | stand | stools + chairs; stands at the bar |
| kitchen | 0 | 4 / 6 / 10 / 16 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | work = cooktop; seats = mess tables |
| medical | 1 / 2 / 4 / 6 | 1 / 1 / 2 / 2 | 0 | 1 / 2 / 2 / 3 | stand | beds = treatment beds |
| bio_lab | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | lab bench |
| research_lab | 0 | 0 | 1 / 2 / 3 / 4 | 1 / 2 / 2 / 3 | **sit** | desks with monitors |
| greenhouse | 0 | 0 | 2 / 4 / 8 / 12 | 1 / 2 / 2 / 3 | stand | **Anchor_Work_i = tray i** (next to `tray_offsets[i]`) |
| fungus_farm | 0 | 0 | 2 / 4 / 6 / 8 | 1 / 2 / 2 / 3 | stand | **Anchor_Work_i = tray i** |
| algae_bioreactor | 0 | 0 | 0 | 1 / 2 / 2 / 3 | stand | automatic |
| storehouse | 0 | 0 | 0 | 1 / 2 / 3 / 4 | stand | |
| cold_storage | 0 | 0 | 0 | 1 / 2 / 3 / 4 | stand | |
| mine | 0 | 0 | 1 / 2 / 3 / 4 | 1 / 2 / 2 / 3 | stand | |
| refinery | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | |
| polymer_plant | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | |
| workshop | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | bench |
| glassworks | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | |
| electronics_fab | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | **sit** | clean-room consoles |
| fabricator | 0 | 0 | 1 / 1 / 2 / 3 | 1 / 2 / 2 / 3 | stand | |
| oxygen_plant | 0 | 0 | 0 | 1 / 2 / 2 / 3 | stand | automatic |
| water_recycler | 0 | 0 | 0 | 1 / 2 / 2 / 3 | stand | automatic |
| atmo_processor | 0 | 0 | 0 | 1 / 2 / 2 / 3 | stand | automatic |
| research_assembler (new) | 0 | 0 | 0 | 1 / 2 / 2 / 3 | stand | automatic, no staff |
| airlock (one size) | 0 | 0 | 0 | 2 | stand | |
| junction (one size) | 0 | 0 | 0 | 1 | stand | |
| lander (special, one size) | 8 | 0 | 0 | 4 | stand | only if you model its inside |

Standing spots (`Anchor_Stand_i`) are used for: drinking at the tap, idling, repairs and upgrades
inside a room, and as the fallback when every seat is taken (people then eat or talk standing).

### New buildings you model (content is in `content/buildings.json`)

- **`research_assembler`**: room, category `science` (accent #7C8CFF), family `science`, sizes S–XL,
  radius **3.6 / 4.6 / 5.8 / 7.2 m**, levels L2–L5. Automatic (no worker). Brief: clean-room hall on the
  round base, a robot arm over a conveyor, pack racks, a water line. Silhouette text is in the def.
- **`meteor_turret`**: exterior, one size, radius **2.2 m**, category `utilities`. Brief: armoured
  pedestal, turning twin-barrel turret (name the turning part `Turret`, pivot at its base; RENDER aims
  it), a small radar dish, a status light. Needs `Anchor_Service`.

### Hazard props (RENDER draws them; data from the sim)

- Crater decal and fragment pile: `sim.hazards.craters()` → `[{x, y, r, tick}]` (r 4–12 m); fragment
  piles are ground piles with `inv.fragment == true` (ore + exotic crystal). A small pile model of
  dark rock with violet crystals reads well.
- Meteor: a burning rock (RENDER can use a primitive + trail if you do not model one).

## 2026-09-25 — answers to round 4 (junction, trays, crater, door clearance)

1. **Junction: minimum 55° between corridors, radius unchanged (2.5 m).** Decided by the coordinator
   from the CRITIC measure (two 2.36 m tubes stop overlapping 2.7 m from the centre at 60°, 3.3 m at
   45°). `content/buildings.json` junction: `"link_min_angle_deg": 55`, `"max_links": 6` (6 × 55° fits).
   Other rooms keep the general 28° (`balance.link_min_angle_deg`). The rule applies to NEW links only:
   saves with junction corridors closer than 55° load and keep them, so your kit must still draw them.
   Sim read: `sim.place.link_min_angle(room)`. Test: `v3_junction_min_link_angle_55`.

2. **Trays moved inward (done).** Tray count per size is unchanged (saves stay valid). New
   `tray_offsets` (x, y in the content plane, metres):
   - greenhouse L:  x ±2.2, y ±1.6 and ±4.8 (was ±1.7 / ±5.1)
   - greenhouse XL: x ±4.1 and 0, y ±1.6 and ±4.8 (was x ±4.4, y ±1.7 / ±5.1)
   - greenhouse S and M: unchanged
   - fungus S:  (0, ±1.0) (was ±1.2)
   - fungus M:  (±1.8, ±1.2) (was ±1.9, ±1.5) — also the top-level `tray_offsets` (size M default)
   - fungus L:  x ±1.8, y 0 and ±3.3 (was ±1.9, ±3.6)
   - fungus XL: x ±1.8, y ±1.6 and ±4.8 (was ±1.9, ±1.7 / ±5.1)
   Trays stay 3.0 × 1.4 m (length along x); the smallest gap between two trays is now 0.6 m (fungus M,
   along x). `Anchor_Work_i` stays next to `tray_offsets[i]`.

3. **Crater radius = the rim.** The sim's crater `r` (`sim.hazards.craters()[k].r`, 4–12 m, the same as
   the meteor's damage radius) is the rim crest. Scale `crater.glb` (rim at 1.0) by `r`; the rays and
   ejecta out to 1.5–2.4 r are decoration. The terrain's own crater bowls (`sim.world.craters`) use the
   same meaning: the rim crest is at `r`.

4. **Door clearance** (`ART-HAB-door_blocked.json`): no change in the sim. Placement does not refuse or
   nudge link angles for door clearance; a narrow clearance on S rooms is accepted.

## 2026-09-25 — v3.1 airlock sizes and the landing pad (your two radius requests; live in content)

Coordinator decision applied as you proposed:

| size | index | radius | `airlock_slots` | stands (`furniture.stands`) | file |
|---|---|---|---|---|---|
| M | 1 | **3.4 m** | 2 | 2 | `airlock_m.glb` |
| L | 2 | **4.0 m** | 4 | 4 | `airlock_l.glb` |

- `content/buildings.json` airlock: `"size_list": [1, 2]` (no S, no XL), `"sizes": {"radius": [3.4, 3.4, 4.0, 4.0],
  "airlock_slots": [2, 2, 4, 4], "occupants": [2, 2, 4, 4], "slots": [2, 2, 4, 4]}`, furniture `stands`
  [2, 2, 4, 4]. Read the riders per size from `sizes.airlock_slots` (index = size), not from
  `balance.airlock_slots` (that stays 2: the lander hatch and old airlocks).
- Build `Anchor_Chamber_0..3`, `Anchor_Suit_0..3`, `Anchor_Porch_0..3` for L (4 of each).
- **Old saves:** airlocks placed before 3.1 keep radius 2.8 m in their record (`b.radius`) and size M.
  The sim never resizes them. RENDER keeps `airlock.glb` for a record with radius 2.8.
- Size L needs the research Engineering 1 (`eng_1`, the general size-L gate). M is open from the start.
- **Landing pad:** 11.5 m for new pads (`buildings.json` `radius` 11.5). A pad record keeps the radius it
  was built with.
- **Ramp lanes** (pad +X ±25°, +Y ±40°): not done in the sim. Placement does not keep them free; bodies
  never walk on the pad (the walking grid blocks the whole pad disc) — visitors appear at the pad edge
  (`sim.nav.best_access(pad, colony centre)`, radius + 1.6 m) and RENDER walks them from the ship.
  Tell the coordinator if the lanes must be kept free by placement.

## 2026-09-25 — door clearance is a placement rule now; trays moved inward (please regenerate)

- The sim reads your blocked angles from `content/door_blocked.json`, a copy of
  `docs/requests/ART-HAB-door_blocked.json` (only `rooms.<key>.blocked` is used; key `<def>_<s|m|l|xl>`,
  plain `<def>` for rooms with one size and for size M). A NEW corridor may not leave a room at a blocked model
  angle (code `door_blocked`). World → model: `beta = rot − world angle` (degrees), the same as your P3 rule
  with the view's `Basis(UP, −rot)` and sim y on Godot z. Old corridors stay.
- **When you regenerate the file, tell me** (SIM-to-ART-HAB / ART-HAB-to-SIM): I copy it into content.
  Until then the copy has today's numbers.
- **Trays moved inward** (counts unchanged) so that every tray corner lies inside your lane end
  (`door_lane_ring`: rr − 0.45) and the lanes clear, by my arithmetic with trays 3.0 × 1.4 m:

  | room | old offsets | new offsets | outer corner radius | lane end |
  |---|---|---|---|---|
  | greenhouse M (also top-level `tray_offsets`) | x ±2.2, y ±1.7 | x ±1.85, y ±1.45 | 4.01 | 4.13 |
  | greenhouse L | x ±2.2, y ±1.6 / ±4.8 | x ±2.0, y ±1.5 / ±3.9 | 5.78 | 5.88 |
  | greenhouse XL | x ±4.1 / 0, y ±1.6 / ±4.8 | x ±3.9 / 0, y ±1.6 / ±4.6 | 7.57 | 7.68 |
  | fungus L | x ±1.8, y 0 / ±3.3 | x ±1.8, y 0 / ±2.2 | 4.39 | 4.48 |
  | fungus XL | x ±1.8, y ±1.6 / ±4.8 | x ±1.8, y ±1.6 / ±4.0 | 5.74 | 5.88 |

  Smallest gap between two trays: 0.6 m (fungus, along x, unchanged), 0.7 m (greenhouse M, along x).
  **Fungus M cannot be freed** with 4 racks of 3.0 × 1.4 m in a 5.0 m room (a corner stays outside 3.13 m
  unless the racks overlap); its four 44° sectors stay blocked. Please rebuild greenhouse M/L/XL and
  fungus L/XL (the tray contract check will ask for it) and regenerate the door file.
- Data questions for your models: `oxygen_plant_s` is blocked at every angle (0° free), so no corridor
  can join an oxygen plant S at all; `oxygen_plant` M has 78° free (59.5–120.5 and 261.5–278.5). Can you
  open a lane in both?

## 2026-09-27 — V4: room scale and the outpost core (requests)

- **Scale:** on the v4 map every new room is 1.5 × the v3 radius for its size (content radii × 1.5,
  rounded to 0.05 m; e.g. habitat M 8.25 m, airlock M 5.1 m, airlock L 6.0 m, junction 3.75 m). Corridors are
  1.25 × wider: tube radius 1.5 m. Old saves keep their radii. Furniture counts per size are unchanged in
  `buildings.json` for now; tell me the new counts you want at 1.5 × and I put them in content.
- **New model `outpost_core`** (`assets/models/outpost_core.glb`): a small lander (radius 4.5 m), three legs,
  a ramp and hatch on +X, a beacon mast, a folded solar wing. Inside: 4 beds (`Anchor_Bed_0..3`),
  `Anchor_Stand_0..1`. Kind "special" like the lander: no corridor ports.

## 2026-09-27 — V4: the 1.5 × radii are in content; content ids for your new buildings; the industry list

**1.5 × rooms are live** (`content/buildings.json`, every map): the 23 room types of your table at your
radii (S–XL), greenhouse and fungus `tray_offsets` × 1.5 (top level and per size). Airlock (3.4 / 4.0 m) and
junction (2.5 m) are unchanged (coordinator). Old saves keep their record radius. Corridors stay 1.2 m radius
until the wider tubes go live with you and RENDER (`content/terrain_v4.json` `corridor_scale`, now 1.0).
Your `content/door_blocked.json` (1.5 × rooms) is the file the sim reads.

**Content ids for the buildings you exported** (radius = your footprint):

| id | file | kind | radius | notes |
|---|---|---|---|---|
| `rover_depot` | `rover_depot_m.glb` / `rover_depot_l.glb` | exterior | M 9.0, L 12.0 | sizes M and L only (`size_list` [1, 2]); bays: M 2 small, L 2 small + 1 medium |
| `launch_pad` | ART-B's `launch_pad*` | exterior | 6.5 | satellite launch |
| `fission_reactor` | `fission_reactor.glb` | exterior | 12.0 | |
| `crystal_refinery` | `crystal_refinery.glb` | exterior | 8.0 | not placeable yet (crafting milestone) |
| `chemical_plant` | `chemical_plant.glb` | exterior | 9.0 | not placeable yet (crafting milestone) |
| `crevice_bridge` | `crevice_bridge_s.glb` (size S) / `crevice_bridge_l.glb` (size L) | special | S 5.0, L 9.0 | span 8 / 15 m, length 10 / 18 m, deck 4.4 m; not placeable yet |
| `outpost_core` | `outpost_core.glb` | special | 4.5 | live (milestone 2) |

**The new industry buildings (please model; each is a room (corridors, work places)
unless marked exterior; sizes S–XL with the room radii 6 / 7.5 / 9.6 / 11.7 unless given):**

| id | tier | kind | makes | look |
|---|---|---|---|---|
| `steel_mill` | mid | room | steel alloy from steel + titanium | a squat furnace hall with a tall stack and ladle rails; glowing pour window |
| `titanium_smelter` | mid | room | titanium from titanium ore | an electric arc furnace dome with thick cables to a transformer yard |
| `ceramics_kiln` | mid | room | ceramics from silicate + titanium | a long low tunnel kiln with vents along the roof |
| `carbon_works` | mid | room | carbon fibre from carbon | spinning towers, fibre spools stacked outside |
| `battery_plant` | mid | room | battery cells from electronics + steel alloy + carbon | clean hall with racks of cells, blue status lights |
| `parts_works` | mid | room | rover parts from steel alloy + electronics + composite | assembly bay with a gantry and a wheel rack |
| `fuel_rod_plant` | high | exterior, radius 8.0 | fuel rods from uranium ore (enrich → pellets → rods) | fenced bunker, centrifuge cascade hall, radiation trefoil, a hot cell window |
| `he3_separator` | high | exterior, radius 7.0 | helium-3 canisters from helium-3 regolith | cold-trap tanks with frost, cryo pipes, a vacuum chamber |
| `magnet_works` | high | room | rare-earth magnets from rare earths + steel alloy | furnace + press line, a large ring magnet on a stand |
| `superconductor_lab` | high | room | superconductor from magnets + ceramics | cryostat drums, a white clean room, frost vents |
| `graphene_reactor` | high | exterior, radius 6.0 | graphene from carbon + electronics | a vapour-deposition tower with a glowing quartz column |
| `metamaterial_foundry` | high | room | metamaterial from exotic crystal + graphene | a dark hall with a violet field chamber (links to the crystal refinery) |

Plus the two you built: `crystal_refinery` (exotic crystal → refined crystal, unstable) and `chemical_plant`
(chemicals from ice + carbon, toxic). The recipes and numbers come with the crafting milestone; the ids and
kinds above are fixed now. Furniture: 1–3 work places per size like the v3 industry rooms.

## 2026-09-27 — Corridor links per room (Paul's rule, live for new links)

- A room takes at most **S 4, M 6, L 7, XL 8** corridors. Airlocks and junctions keep their own rules.
- New links on one room are at least `max(28°, door angle)` apart. Door angle = the chord of the door
  housing (3.44 m + 0.3 m gap) at the wall radius (`radius − 0.32`).
- API: `sim.place.max_links(room)`, `sim.place.link_min_angle(room)`, `sim.place.door_angle(radius)`.
- New refusal code **`links_full`**: "This room has all the corridors it can take (S 4, M 6, L 7, XL 8)."
  It comes before `door_blocked` and `ports_full`.
- Old saves keep every link they have. Balance keys: `room_max_links` [4,6,7,8], `door_housing_m` 3.44,
  `door_gap_m` 0.3.
- For your door sectors: an XL room must hold 8 door slots at least `door_angle(radius)` apart, an L room
  7, an M room 6, an S room 4. `content/door_blocked.json` stays the source for blocked angles.

## 2026-09-27 — your 12 industry buildings are in content (V4 milestone 5)

- Rooms with your counts unchanged (S–XL radius 6 / 7.5 / 9.6 / 11.7, work places 1 / 1 / 2 / 3, stands
  1 / 2 / 2 / 3): `steel_mill`, `titanium_smelter`, `ceramics_kiln`, `carbon_works`, `battery_plant`,
  `parts_works`, `magnet_works`, `superconductor_lab`, `metamaterial_foundry`. Remove `PROVISIONAL_DEF`
  when you like: content matches it.
- Exteriors (automatic, no staff): `fuel_rod_plant` 8.0, `he3_separator` 7.0, `graphene_reactor` 6.0; and
  `chemical_plant` 9.0 and `crystal_refinery` 8.0 are placeable now (stage 0, automatic).
- No new furniture or door needs.

# ============================== VERSION 5 ==============================

## 2026-09-29 — V5 structures in content (milestone 1): ids, sizes, radii, floors, door slots, anchors

The defs are in `content/buildings.json` (look for `"v5": true`). Footprints are circles for placement; the model
fits inside. Please build to these numbers, or tell me yours and I change content.

| id | owner | sizes | radius (m) | floors | door slots | anchors (`anchors_spec`) |
|---|---|---|---|---|---|---|
| `residence_tube` | ART-HAB | M, L, XL | 9 / 11 / 13 | 1 | 4 / 5 / 6 | half-tube; `Anchor_Unit_<i>`, `Anchor_Bed_<i>` (family 6/9/12 beds, executive 2/4/6), `Anchor_Seat_<i>`, `Anchor_Door_<i>` (ends + sides). Variants Family and Executive (same shell, different fit-out) |
| `apartment_block` | ART-HAB | XXL | 20 | 3 × 3.6 m | 6 | `Anchor_Unit_<floor>_<i>` (floors 0, 1: 5 each; floor 2: 2 penthouses), `Anchor_Lift_<floor>`, `Anchor_Door_<i>`; every anchor carries its floor index |
| `retail` | ART-HAB | S, M, L | 6 / 7.5 / 9.6 | 1 | 4/6/7 | `Anchor_Counter`, `Anchor_Browse_<i>` |
| `park` | ART-HAB | M, L, XL | 9 / 12 / 15 | 1 | 6/7/8 | `Anchor_Seat_<i>` (benches), `Anchor_Jog_<i>` (a loop), `Anchor_Wedding` (L, XL); pond from L |
| `academy` | ART-HAB | S, M, L | 6 / 7.5 / 9.6 | 1 | 4/6/7 | `Anchor_Class_<i>` (4/8/14), `Anchor_Teach`, `Anchor_Console_<i>` |
| `security_office` | ART-HAB | S, M | 6 / 7.5 | 1 | 4/6 | `Anchor_Desk_<i>`, `Anchor_Locker_<i>` |
| `jail` | ART-HAB | S, M, L | 6 / 7.5 / 9.6 | 1 | 4/6/7 | `Anchor_Cell_<i>` (2/4/8), `Anchor_Guard`, `Anchor_Yard_<i>` (L) |
| `super_dome` | ART-B | XXXXL | 48 | 5 × 6 m | 12 gates | atrium radius 20, ring depth 14, height 38; `Anchor_Venue_<id>_<i>` (venue ids in the def, with floors), `Anchor_Unit_<floor>_<i>` (30 on floors 2-4), `Anchor_Lift_<i>_<floor>`, `Anchor_Door_<i>` (12), `Anchor_Pool_<i>`, `Anchor_Stage`; build stages: foundation_ring, level_1..5, dome_glass, fit_out |

Furniture counts (`furniture` blocks) are in the defs as for v3 rooms. Door blocked angles: none yet; send them
in `content/door_blocked.json` as before when the models exist.

## 2026-09-30 - children's beds (orchestrator decision) and the anchor names I need

Decision: bed counts follow your models. `content/buildings.json` changes (effective now):

| structure | unit | adult beds | child beds | total bed anchors |
|---|---|---|---|---|
| `residence_tube` Family | per unit | 2 (the parents' beds) | 2 (the bunk: lower + upper) | 4 per unit: M/L/XL 8 / 12 / 16 |
| `residence_tube` Executive | per unit | 2 | 0 | 2 per unit (no change) |
| `apartment_block` floors 0 and 1 | per family unit | 2 | 2 (the bunk) | 4 per unit, 40 |
| `apartment_block` penthouse | per unit | 4 (all 3 bedrooms: master 2, bedroom 2 and bedroom 3 one each) | 0 | 8 |

New fields: `child_beds` (sizes and top level), `child_beds_per_unit` (tube variants), `units[].child_beds` (block);
`furniture.beds` is the total anchor count (adults + children) and `furniture.child_beds` how many of them are
child beds. Adults never take a child bed; children only take child beds.

Please add the anchors (upper bunk at z = floor + 1.81 as you proposed; the third penthouse bedroom) and **tell me
the exact names in ART-HAB-to-SIM.md**. My proposal, so that SIM can tell a child bed by its name:
- tube Family unit i: `Anchor_Bed_<n>` for the two parents' beds as now, and `Anchor_ChildBed_<2i>` (lower bunk),
  `Anchor_ChildBed_<2i+1>` (upper bunk);
- block family unit on floor f, unit i: `Anchor_ChildBed_<f>_<2i>`, `Anchor_ChildBed_<f>_<2i+1>`;
- penthouse p: `Bed_20+4p .. Bed_23+4p` (a running number that includes bedroom 3) or your names.
If you keep one running `Bed_<n>` list, give me the index ranges that are child beds instead.

Noted from your round-33 note: the security office command desk `Work_0` (`Desk_0`) is on the 0.30 m dais; the jail
S/M first standing anchor `Stand_0` (`Yard_0`) is on the yard strip. SIM uses `Work_0` for the officer on duty and
`Stand_0` for the prisoners' yard time; no content change is needed.

## 2026-09-30 - civic colour settled

The `civic` category colour is settled: RENDER uses **#34569c** for the category (your proposal). The security
office and the jail keep their own materials. No change on your side.

## 2026-10-01 - a new room: the distillery; jail cells are bed anchors

- New def `distillery` (content/buildings.json; research civic_1; category food; radius S/M/L/XL 6/7.5/9.6/11.7 like
  the polymer plant; furniture work 1/1/2/3, stands 1/2/2/3; recipes drinks and snacks; silhouette "copper stills and
  tanks under a low roof, pipe racks"). Until you build it, RENDER draws the polymer plant (`model_hint`). Please
  build `distillery_{s,m,l,xl}.glb` when you can and list its door angles in `content/door_blocked.json`.
- Jail: the furniture `beds` are now the cells (2/4/8): SIM puts a prisoner on bed anchor i = your `Anchor_Cell_<i>`.
  The jail has a tap now (`tap: true`) - prisoners drink in the cell block; no model change needed.