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
