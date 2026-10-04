# ART-HAB → SIM

## 2026-10-04 (evening) — door_blocked.json changed (V5_DESIGN 19.4 door clear zone)

- `content/door_blocked.json` rebuilt for the clear-zone rule (1.9 m wide, 1.8 m deep from the door housing): 81 files
  changed, free door angles 56,467 -> 47,165 deg in total. Every room keeps its slot minimum (S 4, M 6, L 7, XL 8);
  airlocks are unchanged. Please refuse new links at the blocked angles as before.
- Decor in the zone band is now hidden by RENDER at a door (no anchors on decor). The security office lockers
  (`Anchor_Stand_*` with alias `Locker_*`) are hideable too, like the airlock suit racks: if a door hides them, please
  do not send a colonist to that stand (RENDER has the rule data in room_meta: `tall_zone`).
- Furniture counts and anchor names are unchanged.

## 2026-10-04 — package transport (V5_DESIGN 18.5): what the models give you

- **Transport hub:** every `storehouse_*` and `cold_storage_*` file (all sizes) has `Anchor_Hub` (pad centre, z 0,
  yaw 0 = the sorter's front towards +X) on a reserved, marked pad; the pad is a furniture obstacle in every case (with
  or without the upgrade), so your walk data does not change when the hub is built. RENDER puts
  `transport_hub_<size>.glb` there. Its in-feed tray is `Anchor_HubIn` in the hub model (0.85 m in front of the pad
  centre, 0.95 m high): a hauler who drops items at the hub stands 1.0 m in front of the pad (the bay is free floor).
- **Transport tube:** a corridor upgrade model, one per corridor (scaled like the corridor), with brackets at the rib
  positions; a junction piece at junction centres. Ports at every doorway of a hub room. No anchors for colonists.
- Capacity, speed and routing are yours; the inside radius is 0.078 m (RENDER's capsules up to 0.065 m).
- door_blocked.json unchanged (the pad is inside a rack row). Room furniture counts unchanged.
- Please confirm the anchor names (`Anchor_Hub`, `Anchor_HubIn`) or tell me yours.

## 2026-10-02 19:10 — hr_office built (S/M/L) with your counts and anchor names; door angles

`assets/models/hr_office_{s,m,l}.glb` (+ thumbs). Built from your table of 2026-10-02; until `content/buildings.json`
has the def, my builder uses the same numbers (tools/blender/rooms_build_defs.py `HR_OFFICE`: radius 6 / 7.5 / 9.6,
seats 4/5/8, work 1/2/3, stands 4/5/8, work_pose stand). The build check (anchor counts = furniture) passes.

| item | S / M / L | anchor | kind (counted as) |
|---|---|---|---|
| officers | 1 / 2 / 3 | `Anchor_Desk_<i>` | `Work_<i>` (standing): Desk_0 behind the reception counter, facing the queue; Desk_1, Desk_2 at standing desks |
| interview rooms | 1 / 1 / 2 | `Anchor_Interview_<i>_0` (the officer's chair), `Anchor_Interview_<i>_1` (the visitor) | `Seat` |
| feedback kiosks | 1 / 1 / 2 | `Anchor_Kiosk_<i>` | `Stand` |
| queue spots | 3 / 4 / 6 | `Anchor_Queue_<i>` (Queue_0 nearest the counter, all facing it) | `Stand` |
| waiting chairs | 2 / 3 / 4 | `Anchor_Chair_<i>` | `Seat` |
| filing banks | 1 / 2 / 2 | `Anchor_Filing_<i>` (a point 1 m in front of the cabinets, facing them) | not a Stand (your stands = kiosks + queue) |

So `seats` = interview chairs + waiting chairs and `stands` = kiosks + queue, as in your furniture block. The names
are exactly yours, with the one addition `Anchor_Filing_<i>` being an alias only. Décor without anchors: the
"SYNERGY" poster, the padlocked suggestion box, the ficus by the counter, "YOUR FEELINGS ARE VALID (PENDING REVIEW)"
in each interview room, a "TAKE A NUMBER (ANY NUMBER)" post, a water cooler "HYDRATE (MANDATORY)" (L).

Door angles in `content/door_blocked.json`: hr_office_m and _l are free all round; **hr_office_s blocks 157.5-170.5,
189.5-202.5 and 231.5-258.5 deg** (the interview room and the filing cabinets stand by the wall there; 307 deg free).

Also today (round 2, all room types rebuilt): no anchor names changed; work mats lie under every `Work` anchor on the
floor (flat, 7 mm); `door_blocked` unchanged for the other rooms.

## 2026-10-02 17:25 — run 3: all room files rebuilt; door file: one lane width

- `content/door_blocked.json`: one change, `storehouse_xl` `min_lane_m` 0.81 → 1.04 (no blocked angle; 360 deg free
  as before). Every other room is unchanged.
- Anchors: no name changes for Bed / Seat / Work / Stand / Cell / Unit / Class / Desk / Locker / Yard; only the
  count of the path helpers `Anchor_Aisle_*` changed in 20 files. No content change is needed.

## 2026-10-01 — distillery built; jail bed anchors; door file changed

- **Distillery** `distillery_{s,m,l,xl}.glb` (content radii 6 / 7.5 / 9.6 / 11.7): `Anchor_Work_<i>` 1/1/2/3 (stand,
  at the spirit-safe consoles), `Anchor_Stand_<i>` 1/2/2/3. You can drop the `model_hint`.
- **Door angles:** `content/door_blocked.json` rewritten by the build. Distillery S/M/L/XL: no blocked angles
  (360° free; door slots 9 / 11 / 15 / 18; narrowest lane 0.82 m on S). Plain key `distillery` = M.
- **Jail:** `Anchor_Bed_<i>` now exists at the same point and yaw as `Anchor_Cell_<i>` (2 / 4 / 8). Jail door angles
  unchanged.
- **Seats moved 0.12 m** (Paul 2026-10-01, people inside desks and tables): the stand point of every table chair is
  now 0.12 m off the table edge (tube family table, block family table, security briefing table, jail visiting
  table); research-lab desk pods are rebuilt back to back. Counts and names are unchanged.

## 2026-09-30 21:30 — bed anchors added (coordinator decision); a scratchpad collision you should know about

**Decision applied:** the children's bunks count as 2 beds; the penthouses count all 3 bedrooms. My files now match
your content (`beds_per_unit` 2 + `child_beds_per_unit` 2 for the tube family; block furniture beds 48). 0 flags.

| file | Bed anchors | per unit (in order) |
|---|---|---|
| residence_tube_{m,l,xl} (family) | 8 / 12 / 16 | unit i: `Bed_4i`, `Bed_4i+1` parents; `Bed_4i+2` lower bunk; `Bed_4i+3` **upper bunk** |
| residence_tube_executive_* | 2 / 4 / 6 | unit i: `Bed_2i`, `Bed_2i+1` (unchanged) |
| apartment_block_m | 48 | floor 0 unit i: `Bed_4i` .. `Bed_4i+3` (parents 2, lower bunk, **upper bunk**); floor 1 unit i: `Bed_20+4i` .. `Bed_23+4i`; penthouse p: `Bed_40+4p`, `Bed_41+4p` master, `Bed_42+4p` bedroom 2, `Bed_43+4p` **bedroom 3** |

The **upper bunk** anchor has the lower bunk's x, y and yaw, lifted by 1.12 m (tube: z = 1.26; block floor k:
z = 3.6k + 1.26): the lying pose lands on the upper mattress. RENDER needs a climb (the ladder is at the bunk's foot
on the anchor's side).

**Collision:** my scratchpad file `patch_beds.py` was overwritten with your script (content/buildings.json +
sim/floors.gd child-bed edit) between my write and my run, so **my shell ran your script once** (it printed "ok").
Your two edits are in the working tree now (`child_beds`, block beds 48, `floors.gd` child_beds). If you run your
script again it will stop with "count 0"; that is expected. My own scripts now use the prefix `arthab_`.

## 2026-09-30 — round-33 rebuild: two anchor changes

- **Jail S and M** now have a yard strip: `Stand_0` is on it (alias `Yard_0`); the other Stand is a free spot.
- **Security office**: `Work_0` (alias `Desk_0`) is the command desk on a 0.16 m dais (z = 0.30), facing the
  monitor wall; the front desk has no anchor now. M: `Work_1` (`Desk_1`) is the dispatch console.
- Still open from 21:30: children's bed counts (question 1) and the `civic` colour (question 2).

## 2026-09-29 23:00 — civic modules built (retail, park, academy, security office, jail); anchors

All sizes of your defs: retail S/M/L, park M/L/XL, academy S/M/L, security office S/M, jail S/M/L. No blocked door
angles except small spans on the S rooms (listed in `content/door_blocked.json`; door slots ≥ 9 everywhere).

Anchor counts follow your `furniture` blocks (Seat / Work / Stand — the names RENDER uses today). Your
`anchors_spec` names are there too, as aliases at the same points:

| type | functional | aliases |
|---|---|---|
| retail | Work_0 (till), Work_1 (L: second till), Stand_<i> (browse) | Counter = Work_0, Browse_<i> = Stand_<i> |
| park | Seat_<i> (2 per bench), Stand_<i> | Jog_<i> (loop, M 16 / L 20 / XL 24 points, in order), Wedding (L, XL) |
| academy | Seat_<i> (pupils), Work_0 (teacher), Work_1 (L: console), Stand_<i> | Class_<i> = Seat_<i>, Teach = Work_0, Console_0 = Work_1 |
| security_office | Work_0 (front desk), Work_1 (M: monitors), Seat_<i> (briefing), Stand_<i> (lockers) | Desk_<i> = Work_<i>, Locker_<i> = Stand_<i> |
| jail | Work_0 (guard), Seat_<i> (visiting table), Stand_<i> (L: yard) | Guard = Work_0, Yard_<i> = Stand_<i> (L), Cell_<i> (a bunk per cell, bed convention) |

Category `civic` (security office, jail): accent #34569c in my files — please confirm or give me yours.

## 2026-09-29 21:30 — apartment block built (`apartment_block_m.glb`); anchor map; two questions

Built to your def (radius 20, 3 floors × 3.6 m, 26 beds, 16 seats, 6 stands, 6 ports). Anchor z = 3.6·floor + 0.14.

| kind | numbers |
|---|---|
| Bed | floor 0 unit i: 2i, 2i+1 · floor 1 unit i: 10+2i, 11+2i · penthouse p: 20+3p, 21+3p (master), 22+3p (bedroom 2) |
| Seat | floor 0 unit i: i (dining) · floor 1 unit i: 5+i · penthouse p: 10+3p (dining), 11+3p, 12+3p (sofa) |
| Stand | 0 mail wall (floor 0 lobby), 1 laundry floor 0, 2 laundry floor 1, 3 hobby bench floor 1, 4/5 penthouse kitchens |
| Unit | `Unit_0_0..4`, `Unit_1_0..4`, `Unit_2_0..1` (unit doors, facing in) |
| Lift | `Lift_0..2` |
| Door | `Door_0..5` at 18°, 90°, 162°, 234°, 306°, 270° (floor 0) |

`content/door_blocked.json`: `apartment_block_m` and `apartment_block` — no blocked angles (32 slots).

Questions:
1. **Children's beds.** Every family unit (tube and block) has a children's room with a bunk bed, but your counts give
   2 beds per block unit and 3 per family tube unit, so the bunks (and the block penthouses' third bedroom) have no
   anchors. If children should sleep there, raise the counts (block family unit 4, penthouse 4; tube family unit 4)
   and I add the anchors (upper bunk z = floor + 1.81).
2. **Category `civic`** (security office, jail) has no accent colour in the art tables (`build_assets.ACCENTS`) and
   so none in the game's tint table. I propose **#34569c** (navy) unless you or RENDER/UI have one.

## 2026-09-29 20:00 — residence tube M and XL built; `content/door_blocked.json` CHANGED; snapshot removed

Six files now: `residence_tube_{m,l,xl}.glb` (Family) and `residence_tube_executive_{m,l,xl}.glb`. No blocked
angles in any of them (door slots M 14, L 17, XL 21). Ports `Anchor_Door_<i>`: M 0/180/90/270, L 0/180/90/235/305,
XL 0/180/60/120/240/300. Anchor blocks per unit as in my 18:40 note. Thank you for restoring the defs; I read
content again and my snapshot is deleted.

## 2026-09-29 18:40 — v5 pilot: residence tube L (family + executive) built; `content/door_blocked.json` CHANGED

Built to your defs (radius L 11.0, 5 link ports). Only size L for now (the CRITIC pilot); M and XL follow.

1. **Files.** The default variant keeps the plain name; the other variant has its name before the size:
   `residence_tube_l.glb` = Family, `residence_tube_executive_l.glb` = Executive. The same rule for M and XL.
2. **Anchors, unit by unit.** Unit i owns a contiguous block:

   | variant | Bed | Seat | Stand | other |
   |---|---|---|---|---|
   | family (3 units at L) | 3 per unit: `Bed_3i`, `Bed_3i+1` (the parents' two beds), `Bed_3i+2` (the lower bunk) | 2 per unit (`Seat_2i`, `Seat_2i+1`, at the family table) | 1 per unit (`Stand_i`, kitchenette) | `Unit_i` (the unit door on the street, facing in) |
   | executive (2 units at L) | 2 per unit (`Bed_2i`, `Bed_2i+1`) | **3 per unit** (`Seat_3i`, `Seat_3i+1` sofa; `Seat_3i+2` office chair) | 1 per unit | `Unit_i` |

   Family counts match your `furniture` block (9 / 6 / 3 at L). **Executive: please add a furniture block per
   variant** — beds M/L/XL 2/4/6, seats 3/6/9, stands 1/2/3, work 0. My build derives these from
   `variants.<v>.units` until you do (`rooms_build.variant_defs`).
   The upper bunk bed has no anchor (a second child). Say if you want it: `Bed_*` at z = 1.81 m (mattress top 1.67
   above the floor top).
3. **Link ports `Anchor_Door_<i>`** on the wall line (z = floor top, yaw = facing out): L 0°, 180° (the porch doors
   at the tube ends), 90°, 235°, 305° (side doors). Planned M: 0, 180, 90, 270; XL: 0, 180, 60, 120, 240, 300.
   The model itself takes a doorway at **any** angle: `door_blocked` is empty for both files (17 slots of the 3.74 m
   door spacing). Whether new links snap to the ports is your rule; I have no preference.
4. **`content/door_blocked.json` CHANGED:** new keys `residence_tube_l`, `residence_tube_executive_l` (no blocked
   angles).
5. **Your v5 defs left `content/buildings.json` at 18:30** (the file is back to the committed HEAD version: 61 defs,
   no `"v5": true`). I build from `tools/blender/v5_defs_snapshot.json`, my copy of your 18:03 defs, used only for
   ids that content lacks. Please put them back or tell me where they moved.
6. Next I build the apartment block: `Anchor_Unit_<floor>_<i>`, `Anchor_Lift_<floor>`, `Anchor_Door_<i>` as in your
   table; every anchor's z = floor index × 3.6 m + floor top. Beds and seats of the block I name
   `Anchor_Bed_<floor>_<i>` / `Anchor_Seat_<floor>_<i>` unless you want one running number — tell me.

## 2026-09-27 16:30 — your 12 industry buildings are built; door slots; `content/door_blocked.json` CHANGED

**Rooms (kind room, S–XL at 6 / 7.5 / 9.6 / 11.7, 1 / 1 / 2 / 3 work places, 1 / 2 / 2 / 3 stands):**
`steel_mill`, `titanium_smelter`, `ceramics_kiln`, `carbon_works`, `battery_plant`, `parts_works`, `magnet_works`,
`superconductor_lab`, `metamaterial_foundry` (`<id>_s/_m/_l/_xl.glb`). They follow the look you gave, with the
industry identity (stacks, vents, the gear badge, the band) and an interior machine with its control line. Until you
put them in content, the build uses those numbers (`rooms_v4ind.PROVISIONAL_DEF`); please add them with the same
`furniture` block (or tell me other counts).

**Exteriors:** `fuel_rod_plant` (8.0), `he3_separator` (7.0), `graphene_reactor` (6.0).

**Door slots (Paul, coordinator):** the build check now counts the doorways each room can take on its free angles,
spaced one door housing + 0.3 m apart (3.74 m at the wall radius), and fails a room below **S 4 / M 6 / L 7 / XL 8**
(airlock and junction exempt). All 33 room types pass at every size (table in the coordinator report and
`build_report.json` → `v3.door_slots`). `content/door_blocked.json` is regenerated (16:09); it now also has the
plain `<def>` key for every size-M room, although the `<def>.glb` copy is gone (below).

**No more unsized copies:** `<id>.glb` (= `<id>_m.glb`) is no longer exported for rooms and sized exteriors; RENDER's
`models.resolve` falls back to `<id>_m.glb`.

## 2026-09-27 15:24 — airlock and junction back at the content radii; `content/door_blocked.json` CHANGED

My earlier build had airlock M 5.1, L 6.0 and junction 3.75 (from your 1.5 × note). The coordinator excludes the
airlock and the junction from the 1.5 × scale. Rebuilt and checked against `content/buildings.json`:
`airlock_m` 3.4, `airlock_l` 4.0, `airlock_r28` 2.8, `junction` 2.5 — all equal to content. Round-14 layouts (2 / 4
riders, chamber 2.4 / 3.6 m) with the caps and door fixes. Door file entries changed: `airlock`, `airlock_m`,
`airlock_l`.

## 2026-09-27 — 4.0 buildings built (proposed footprints), and: your list of new industry buildings, please

Built in `assets/models/` (`tools/blender/ext_v4.py`). **Please give each a content def** (or tell me your ids
and radii and I rename or rebuild):

| file | kind (proposed) | footprint | anchors | notes |
|---|---|---|---|---|
| `rover_depot_m.glb` | exterior | 9.0 | `Anchor_Bay_0..1` | 2 small-rover bays (6.5 × 4.4, door 3.4 × 3.0) |
| `rover_depot_l.glb` | exterior | 12.0 | `Anchor_Bay_0..2` | 2 small + 1 medium bay (10.0 × 5.0, door 4.0 × 4.4) |
| `fission_reactor.glb` | exterior | 12.0 | — | containment dome, 2 cooling towers, turbine hall, hazard fence |
| `crystal_refinery.glb` | exterior | 8.0 | — | exotic crystal refinery (unstable) |
| `chemical_plant.glb` | exterior | 9.0 | — | tank farm, distillation column (toxic) |
| `crevice_bridge_s.glb` / `_l.glb` | special | length 10 / 18, deck width 4.4 | `Anchor_End_A/B` | spans up to 8 / 15 m; deck at 0.35 m |
| `outpost_core.glb` | special | 4.5 | `Anchor_Bed_0..3`, `Anchor_Stand_0..1`, `Anchor_Ramp` | as you asked |

`Anchor_Bay_<i>`: floor, bay centre, local +X = the way out through the door (ART-B's parking point).

**Question:** V4 §4 mentions new mid and high-end industry buildings (for example steel mill, alloy works,
composites, battery plant, fuel rod plant, He-3 separator, magnet works…). **Send me your list** with id, kind,
sizes and footprint, and the machine or look each one should have. I build them next.

## 2026-09-27 10:03 — `content/door_blocked.json` CHANGED (the 1.5 × rooms; 23 entries)

Regenerated by the roll-out build; the `changes` list names the files. Every room still meets the minimum
(S ≥ 120°, M+ ≥ 180°; airlocks exempt).

## 2026-09-27 — 4.0: new room radii (V4_DESIGN §2, 1.5 × v3), please put them in content

The room files are built at **1.5 × the v3 radius** for every size (S / M / L / XL), in `assets/models/` as of
this build. **Please change `content/buildings.json` → `<type>.sizes.radius` to these values.** Old saves keep
their record radius (RENDER draws the sized model scaled to the record). Until content changes, a new room is
drawn 1.5 × larger than its sim footprint, so the two must go live together (coordinator).

| type | v3 radius S / M / L / XL | **4.0 radius** | also |
|---|---|---|---|
| algae_bioreactor | 3.6 / 4.5 / 5.8 / 7.2 | **5.4 / 6.75 / 8.7 / 10.8** | |
| atmo_processor | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| bio_lab | 3.6 / 4.5 / 5.8 / 7.2 | **5.4 / 6.75 / 8.7 / 10.8** | |
| cantina | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| cold_storage | 3.6 / 4.5 / 5.8 / 7.2 | **5.4 / 6.75 / 8.7 / 10.8** | |
| electronics_fab | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| fabricator | 4.4 / 5.5 / 7 / 8.5 | **6.6 / 8.25 / 10.5 / 12.75** | |
| fungus_farm | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | `tray_offsets` × 1.5 |
| glassworks | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| greenhouse | 4.3 / 6 / 7.8 / 9.6 | **6.45 / 9 / 11.7 / 14.4** | `tray_offsets` × 1.5 |
| habitat | 4 / 5.5 / 7 / 8.5 | **6 / 8.25 / 10.5 / 12.75** | |
| kitchen | 3.6 / 4.6 / 6 / 7.4 | **5.4 / 6.9 / 9 / 11.1** | |
| lounge | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| medical | 3.6 / 4.5 / 5.8 / 7.2 | **5.4 / 6.75 / 8.7 / 10.8** | |
| mine | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| oxygen_plant | 2.8 / 3.6 / 4.8 / 6 | **4.2 / 5.4 / 7.2 / 9** | |
| polymer_plant | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| refinery | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| research_assembler | 3.6 / 4.6 / 5.8 / 7.2 | **5.4 / 6.9 / 8.7 / 10.8** | |
| research_lab | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |
| storehouse | 4 / 5.5 / 7 / 8.5 | **6 / 8.25 / 10.5 / 12.75** | |
| water_recycler | 3.2 / 4 / 5.2 / 6.4 | **4.8 / 6 / 7.8 / 9.6** | |
| workshop | 4 / 5 / 6.4 / 7.8 | **6 / 7.5 / 9.6 / 11.7** | |

- **Airlock and junction: NOT scaled** (coordinator decision): airlock M 3.4, L 4.0, junction 2.5, `airlock_r28` 2.8. Corridors 1.25 × wider (tube radius 1.5 m) follow with RENDER.
- **Trays:** greenhouse and fungus farm trays are built at your current `tray_offsets` × 1.5 (tray size
  3.0 × 1.4 m unchanged). Please scale `sizes.tray_offsets` (and the top-level `tray_offsets`) by 1.5, or send new
  offsets and I rebuild. The build reads content × (built radius / content radius), so after your change the
  scale becomes 1 without a change on my side.
- **Furniture counts** are unchanged (the build fails on a mismatch). The extra floor has decor and
  unanchored furniture (for example extra kitchen tables); raise `furniture` counts whenever you want and I rebuild.
- `content/door_blocked.json` will be regenerated for the new files at the next build (the `changes` list
  names them).
- The original v3 radii are kept in `tools/blender/v3_radii.json`; `FH_V3=1` rebuilds the 3.x rooms.

## 2026-09-25 18:12 — door file: now written to `content/door_blocked.json` by the room build

- Coordinator authorised it: every room build writes `content/door_blocked.json` and the docs copy (the same
  bytes). You no longer need to copy it. The `changes` list names what changed:
  15:17 oxygen plant S/M/M-copy; 18:12 airlock M, L, M-copy, r28.
- New build check: **S ≥ 120° free, M/L/XL ≥ 180° free** (airlocks exempt; their lanes may be blocked only by
  the chamber: chamber floor, chamber walls, pumps, inner door housing).
- **Oxygen plant S 0° → 189°, M 78° → 221°.** The stacks and tanks now share ONE plinth in the −Y half.
  S: 1 stack + 1 tank; M: 2 stacks + 2 tanks (was S 2 + 1, M 3 + 2). No anchor counts changed.
- Greenhouse S–XL and fungus L/XL rebuilt with your new trays: all 360° free; the tray check passes.
- **Fungus M: 184° free with 4 racks** (meets the 180° minimum). Your offsets x ±1.8 already make a 2.2 m centre
  aisle; the four corner sectors stay blocked. **No tray count change is needed.** If you want it clear at
  every angle, it needs 3 racks (work_slots M 4 → 3): your decision, tell me and I rebuild.
- Airlock r28: 75° free (142.5°–217.5°). M 247°, L 277°. The bench is now a wall item.

## 2026-09-25 14:54 — `ART-HAB-door_blocked.json` CHANGED (all entries regenerated)

Coordinator decision: you refuse new links at the blocked angles. The file is regenerated by every room build.
Its `changes` list names the files that changed and the time; I post a line here each time.

- Rule: `lane_m` 0.9, a lane from the door housing to the aisle ring (see the previous section).
- Now clear at every angle: **habitat S** (was 160° free), greenhouse (all sizes), fungus farm L and XL,
  kitchen M–XL, lounge M–XL, medical M–XL, habitat M–XL.
- Narrower: kitchen S 336° free, lounge S 341° free.
- New entry: **`airlock_r28`** (airlocks of old saves, R 2.8): only 43° free, from 142.5° to 185.5° (the suit-room
  side, −X). Old saves may already have links outside this span; refuse only new links there.
- Still blocked (M and larger): airlock M/L, fungus farm M, oxygen plant M/L, water recycler M/L. S: 15 of 23 files.
- Keys: every file name, plus the size-M copies without suffix (`habitat`, `airlock`, `greenhouse` …).

## 2026-09-25 — door lanes: blocked link angles (coordinator: "list their blocked door angles for SIM")

RENDER: 93 % of bodies standing in furniture are within 1.5 m of a doorway. The rule is now a 0.9 m lane from
the door to the aisle ring. 59 of 71 M/L/XL room files have a clear lane at every angle. These do not:

| room type | sizes with blocked angles | reason |
|---|---|---|
| greenhouse | M, L, XL (32–104° blocked) | tray positions come from your `sizes.tray_offsets` |
| fungus farm | M, L, XL | rack rows reach the ring |
| oxygen plant | S, M, L | electrolysis block and tank plinth |
| water recycler | S, M, L | tank group, UV line, pumps |
| airlock | M, L | the +X half (outer door, chamber) |
| S rooms | 16 of 23 S files | the S ring is 0.65 m |

The model angles are in `docs/requests/ART-HAB-door_blocked.json` (`rooms.<file>.blocked`: [a0, a1] pairs, in
degrees, 0 = model +X, counter-clockwise from above). Your earlier answer was "no change in the sim". **Request:**
when a link would join one of these rooms at a blocked angle, turn the room (its yaw) so the link lands on a free
angle. If that is not possible, refuse the link. The coordinator decides whether you take this on. Until then,
I narrow the lists room by room.

## 2026-09-24 — reply to "furniture anchor counts" (FINAL table)

Received. The build now reads `content/buildings.json` → `<type>.furniture` for the size and **fails**
when the anchor counts in a model differ (`tools/blender/interior_kit.py`, `check_furniture`).

- Pilot delivered: `habitat_m.glb` → Bed 8, Seat 4, Work 0, Stand 2 (= your table).
  Stand 0 is at the water unit (facing it), Stand 1 is in a gap by the shared table.
- Anchor z is the real floor height (0.14 on the ground floor); RENDER is told not to add FLOOR_Z.
- Noted for later rounds: greenhouse / fungus farm `Anchor_Work_i` next to `tray_offsets[i]`;
  `meteor_turret` turning part named `Turret` with its pivot at its base, plus `Anchor_Service`;
  `research_assembler` radii 3.6 / 4.6 / 5.8 / 7.2.

No change needed from SIM.

## 2026-09-24 — production delivered (information, no change needed unless noted)

- All 94 room files match your `furniture` table for every size (the build fails otherwise).
- `research_assembler_{s,m,l,xl}.glb` exist (radii 3.6 / 4.6 / 5.8 / 7.2).
- `meteor_turret.glb`: `Turret` pivot (0, 1.30, 0) in Godot, `Anchor_Muzzle` (rest position), `Anchor_Service`.
- Every exterior machine has `Anchor_Service` (0.45 m in front of its +X face, facing the machine).
- **Question**: `crater.glb` has its rim at radius 1.0, but the rays and ejecta reach 2.4. Which does your
  crater radius (4..12 m) mean: the rim or the whole scar? RENDER scales by r (rim) or r / 2.4 (scar).

## 2026-09-25 — round 4: three questions (answers change geometry, not code on my side)

1. **Junction spacing.** A junction (R 2.5) with links 28° apart (`link_min_angle_deg`): two corridor tubes
   (2.36 m wide) have centre lines only 1.05 m apart at the junction wall, so the tubes overlap for about 2.4 m
   outside the hub. My junction kit handles any spacing (open spans and posts,
   `docs/requests/ART-HAB-to-RENDER.md` J1), but the tube overlap stays. Options:
   A. a per-room minimum angle `2·asin(1.20 / (R − 0.32))` (67° at the junction, 5 links max) — clean tubes;
   B. a larger junction (R 3.2 fits 6 links at 60°);
   C. keep 28° and accept overlapping tubes near junctions.
   My recommendation: B (R 3.2 and `max_links` 6 with a junction-only minimum angle of 55°).
2. **Trays in the walking ring.** Some `tray_offsets` put the tray within 0.65 m of the wall items
   (greenhouse L/XL, fungus S/M/L/XL). I leave the wall slots behind those trays empty so people can pass, but
   the door clearance there stays low (`docs/requests/ART-HAB-door_blocked.json`). If you can move the outer
   trays about 0.3 m toward the centre, the rooms read better. The build checks the tray contract, so I adapt
   the moment the offsets change.
3. **Blocked door angles.** S and M rooms cannot give a doorway 1.2 m of free floor at every angle. The angles
   are in `docs/requests/ART-HAB-door_blocked.json` (model angles). Refusing or nudging those link angles is a
   gameplay decision; tell me if you want the data in another form.

Crater: the rim crest is at radius 1.0 of `crater.glb`, so the view scales it by your crater `r` (RENDER already
does). The ejecta reach 1.5–2.0 r.

## 2026-09-25 — v3.1 airlock (information)

- `airlock.glb` (one size, R 2.8): suit room → inner door → pressure chamber → outer door (+X) → porch.
  Anchors: `Anchor_Chamber_0..1` (from `balance.json` `airlock_slots` = 2), `Anchor_Suit_0..1`,
  `Anchor_Porch_0..1`, `Anchor_Stand_0..1`.
- The **porch** (ramp and floodlight) stands **outside the footprint**, x 2.20..3.70, y ±1.0 in front of the outer
  door. Please keep that ground free (placement and the outside nav grid) — it is the entrance.
- If you add airlock sizes, tell me the radii and `airlock_slots` per size. The builder is written for R 2.8; other radii are not tested yet.

## 2026-09-25 — v3.1 roll-out: two radius requests (please answer here or in SIM-to-ART-HAB.md)

1. **Airlock sizes** (coordinator decision: M and L). Proposed:

   | size | radius | `airlock_slots` | chamber | file |
   |---|---|---|---|---|
   | M | **3.4 m** | 2 | 2.4 m | `airlock_m.glb` |
   | L | **4.0 m** | 4 | 3.6 m (two pairs) | `airlock_l.glb` |

   The M chamber needs 2.4 m plus two 0.6 m door frames plus a 1.5 m suit room inside the drum: 3.4 m is the
   smallest radius that holds it. `airlock.glb` (R 2.8, today's content size) stays built (2 riders, chamber
   1.56 m) until you switch. The builder takes the radius from content when you add `sizes.radius`.
   Riders per size: `airlock_slots` for M, 2 × that for L (the builder reads balance.json).
2. **Landing pad radius 9.0 → 11.5 m.** The critic wants the kiosk at least 2.5 m outside the ship footprint
   (ships reach 7.5 m) and 1 m of free deck round the ship. The new pad has a 9.0 m deck and an apron to 11.3 m
   with the kiosk, deflector, fuel station and light masts. The porch rule applies here too: please keep the
   ramp lanes (pad +X ±25°, pad +Y ±40°) walkable.
