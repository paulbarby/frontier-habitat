# Critic round 33 — `residences` re-check (with the apartment block) and `civic_modules`

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.7, §3.8 ·
Pass ≥ 0.65. Blender and game-camera identity shots; provisional. The full detail is in
`round_33_residences_civic.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| residences | 0.80 | 0.74 | 0.78 | **0.77** | 0.73 | PASS, provisional |
| civic_modules | 0.62 | 0.64 | 0.70 | **0.65** | new | PASS, marginal, provisional |

## residences

**Round-27 fixes.**

| fix | result |
|---|---|
| Empty drum ring | **Landed.** A lawn with private patios, tables and play corners. |
| Executive richer | **Partly.** Wood floors, a lounge, a desk, but the same furniture family as Family. |
| Night | **Partly.** Lamp pools, but the rooms are still dim grey away from the lamps. |
| Vault seams and porch lamps | **Landed.** |
| Family vs Executive at 250 m | **Landed.** The terrace reads. |
| Children's rooms | **Landed.** |

**Apartment block.**
- **Identity.** At 110 and 250 m, day and night, it reads as the big housing building: a stepped
  three-tier drum with the house badge.
- **Floors.** The floor renders show a ring of furnished units round a lift and stair core. The
  penthouse floor has a terrace and two pools.
- **Faults.**
  - Floor 1's outer ring is a wide empty grey band.
  - The exterior upper floors are plain.
  - Few windows are lit at night.

**Fixes (ART-HAB).**
1. **Floor 1 ring.** Balconies per unit (table, chairs, planters, screens), or a band of 1.5 m.
2. **Block exterior.** Unit windows lit at night, balconies, and a penthouse terrace visible from
   110 m.
3. **Executive furniture.** A second set: upholstered bed, armchairs, bookcase, art.
4. **Night fill.** A soft ceiling fill: no dark rooms.
5. **RENDER / ART-HAB: evidence for the final.** The in-game cutaway, the floor selector, and the
   follow view in a unit and in a penthouse.

## civic_modules

**Identity without labels.**

| view | result |
|---|---|
| 110 m day | **3 of 5.** Park, jail, academy. Retail carries the comfort heart like the lounge. Security carries the same blue shield as the jail. |
| 250 m day | **2 of 5.** Park, and the jail by its fence. The academy's atom reads as the research lab. |
| 250 m night | **2 of 5.** Only the park glows. |

**ART-HAB's question: security office vs jail — not distinct enough.**
- Both are the same grey drum, with the same blue shield and the same band.
- The tower and the thin fence rail vanish at 250 m.
- V5 §1 gives security black and red. Use it, and give the jail its own badge and silhouette.

**What works.**
- **Park:** a green glass dome with lawns, trees, a pond and benches. It glows at night.
- **Jail L:** barred cells round a guard post; serious, not grim.
- **Academy:** desks, a board, consoles.
- **Retail:** racks, mannequins, a counter.

**Fixes (ART-HAB), most important first.**
1. **Own badges.**
   - Retail: a shopping bag.
   - Academy: a book or mortarboard.
   - Security: a black-and-red shield.
   - Jail: a barred window or a lock.

   Never reuse the heart or the atom.
2. **Silhouettes.** Each must read at 250 m without its badge.
   - **Security:** a comms mast, a beacon and a black-and-red band.
   - **Jail:** a raised perimeter wall with corner towers and floodlights, and an orange band.
3. **Retail.** Awnings and lit signage round the drum, and a bigger billboard.
4. **Empty floors.** Retail, security office, academy and jail S leave 40–60% of the floor empty.
   - **Retail:** shelf rows and a fitting room.
   - **Security:** a briefing table, lockers, a monitor wall, a holding cell.
   - **Academy:** a second class, a library corner, a lab bench.
   - **Jail S:** a yard strip and a visitor table.
5. **Security interior.** It reads as a storeroom. Make it a command post: a raised desk facing a
   monitor wall, a dispatch console, lockers.
6. **Night.** Lit windows and a lit badge on every module.

**Tone check:** no child in the jail, and nothing inappropriate.
