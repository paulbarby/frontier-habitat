# Critic round 42 — interiors_close (follow camera, 1.8 m, roofs on)

Date: 2026-10-04 · Critic · Rubric: `docs/critic/v5_rubrics.md` · Contract: V5_DESIGN §15.3, §15.5, §17.1 · Pass ≥ 0.65.

## Evidence

- Build `build/web_v5play3` (e9b1d35, pck 186.2 MB), save `showcase_v5.fhsave`, `tools/shoot.mjs --gpu`, 1600×900, HUD on.
- 282 in-game frames + 60 look-up frames, all in `art/critic/r42/interiors_close/`. Contact sheets: `sheet_game_g1..g9.png`,
  `sheet_more.png`, `sheet_apt.png`, `sheet_night.png`, `sheet_doors_a/b.png`, `sheet_ring_all.png`, `sheet_ring_lounge.png`.
- Method: a person staged at a room anchor (`use nth`), then `follow <id>`, game paused, `shoulder 1.9 <orbit> ±1 0 0 0` at
  0/90/180/270°, plus a 40° look-up. Doorways: a walker driven through a door (`runto`). Night: `time 480`.
- ART-HAB evidence: all 144 `art/interiors/*_eye*.png` and 12 `*_doorview_*.png` (sheets `sheet_eye_0..8.png`,
  `sheet_eye_r41fails.png`, `sheet_doorview.png`).
- Room types seen in game (23): habitat, cantina, kitchen, research lab, medical, greenhouse, lounge, refinery, mine, polymer
  plant, atmo processor, research assembler, water recycler, storehouse, residence tube, apartment block, HR office, jail,
  academy, security office, retail, park, distillery, airlock (24 with the airlock). Not seen in game: oxygen plant (staging
  failed), the other 13 industry types (Blender only).

## Score

| consistency | appeal | style | score | result |
|---|---|---|---|---|
| 0.68 | 0.62 | 0.74 | **0.68** | PASS (narrow). Round 41: 0.64. |

## What works

- **Roofs on.** Every room has a ceiling at eye height in game (23 types).
- **Doorways.** No beam across an opening: 8 in-game door walks, 12 ART-HAB doorview renders.
- **§15.3 satire reads at follow distance in game:** "AI-POWERED FRIDGE V2.6", FRIDGE.AI "OAT MILK: 0 / ORDERED: 40" and "I SAW
  THAT MIDNIGHT SNACK", "DO NOT EAT THE SAMPLES", "BREATHE IN. WE CHECKED.", "TO THE KALE", "PLANTS LIKE COMPLIMENTS",
  "HOME SWEET POD", "QUIET HOURS 22:00", "SHOES OFF / ROBOTS TOO", WELLBEING.AI "1 GREAT 2 GREAT 3 OTHER*", "SYNERGY",
  "YOUR FEELINGS ARE VALID (PENDING REVIEW)", "ASK ME ANYTHING / I WILL TRY", "SALE* / *TERMS APPLY", "TOKENS ARE LOVE",
  "DJ LATENCY", "AI-ENABLED*", jail tally marks with "WIFI: LOL". Original, playful, never mean.
- **Role identity** reads without a label: kitchen, cantina, academy, medical (scanner ring, red crosses), retail (mannequins),
  park (pond, trees), jail (bars, bunks), security (black and red), distillery (copper stills, barrels), water recycler (lit
  filter column), HR office.
- **Density:** kitchen, academy and HR are full of props and people; tables carry clutter.
- **Night:** the cantina neon reads well (`n_cantina_a.png`).
- **Round 41 fixes landed:** working eye views for junction, water recycler, storehouse, cold storage; junction totem
  ("NOT THE CANTINA"); security black/red band; industry ceiling variants and hero machines; HR office in game.

## Faults (most important first)

| # | sev. | owner | fault | where | fix |
|---|---|---|---|---|---|
| 1 | major | RENDER | The upper wall is missing above some door segments. The desert and the next building show through inside the room; signs float in the air. | Habitat id 3809: `ring_lounge_60.png`, `ring_lounge_120.png` (HR roof sign "WE ARE LISTENING*" seen through the wall). Distillery: `distillery_c.png`, `ring_distillery_0.png`. | `fx_doors.gd` patch loop (about line 375): add the upper patch for the raised drum (`Upper_<seg>`, 1.40–2.65 m) on every masked segment, also near doors (ART-HAB ask 2026-10-03). Proof: 6-orbit look-up ring per room type, 0 sky pixels. |
| 2 | major | RENDER | No light colour per role. Every ceiling light is the same `WARM` constant; ART-HAB's `v3.ceiling.light` is not read. | `fx_interior.gd` lines 16, 228–237. Same white in `kitchen_a`, `research_lab_b`, `r_medical_c`, `refinery_b`. | Read the role colour per room. Medical and labs cool (6000–6500 K), kitchen, cantina, homes warm (3000–3500 K), industry neutral with amber, jail cold grey. |
| 3 | major | ART-HAB (RENDER material) | Every surface is one flat colour. No texture, wear or grime. At 1.8 m it reads as a blockout. | `hr_office_b`, `kitchen_b`, `residence_c_c`, `airlock_a`. | Build the proposed shared atlas (painted panel with edge wear, brushed metal, fabric, wood, rubber floor). RENDER adds the material. Start with floors, wall panels, table tops. |
| 4 | major | ART-HAB | Residence and apartment units look like office cubicles. Partitions are bare white boards. The only satire is one FRIDGE.AI. | `residence_c_c`, `r_residence_b2_c`, `r_apt_s2_d`; Blender `residence_tube_executive_l_unit_eye0/1`, `apartment_block_m_unit_eye0/1` (50–70 % white board). | Finish the partition faces (shelves, pictures, wall lamp, coat strip, door frame). Lanes ≥ 1.4 m. Two more satire pieces per unit. Make Executive visibly richer than Family. |
| 5 | major | RENDER | The follow camera sits inside partitions and racks. | Flat wall fills the frame: `residence_a_c`, `residence_b_c`, `apartment_a`, `r_apt_s2_b` (4 of 282 frames, all units). Shelf across the face: `storehouse_c`. Doorways: 5 of 32 frames > 70 % wall (`door_habitat_2in_door`, `door_habitat_4enter`, `door_lounge_2in_door/3beyond/4enter`). | Add partitions (`PartTop`), unit walls and `Tall` racks to the camera solid set; pull in, never sit in a board. At a door, keep the camera on the door axis behind the body. |
| 6 | major | ART-HAB | The apartment top floor (penthouse) ceiling is a flat dark slab with no light or detail. | `r_apt_s4_up`, `r_apt_s5_up` (body y 17.9 m). | Unit ceiling 2.4–2.6 m with a cove light and pendants; a skylight for the penthouse. |
| 7 | major | ART-HAB | Greenhouse crops are flat green slabs and striped boxes. | `greenhouse_a`, `greenhouse_b`, `n_greenhouse_a`. | Instanced low-poly plants in the beds (rosettes, vines on the trellis, herbs), 2–3 heights. |
| 8 | minor | ART-HAB | Storehouse aisles are still too narrow for the camera (round 41 fix 4). | `storehouse_b`, `storehouse_c`. | Aisles ≥ 1.6 m; aisle-end signs as in cold storage. |
| 9 | minor | ART-HAB | Joke props repeat: the same AI fridge in lab and medical; FRIDGE.AI with the same 2 lines in every unit of 5 buildings; "AI-ENABLED*" on every industry console. | `research_lab_b`, `medical2_d`; `residence_a_a`, `r_residence_d2_a`, `r_apt_s4_a`; `refinery_b`, `distillery_c`. | 4–6 text variants per prop, chosen by room id; one new prop per role. |
| 10 | minor | ART-HAB | Signs are cut off. | Jail "TIME ZO" (`r_jail_a`, also Blender `jail_m_eye0`); HR "YOUR MATTE" (`hr_office_b`); distillery "T? ? DOME" (`distillery_c`). | Builder check: text inside its board, board inside one wall segment, below the liner. |
| 11 | minor | ART-HAB | Industry rooms still share one wall kit (console, plate, lockers, bookcase). Ceilings and hero machines now differ. | `sheet_game_g5.png`, `sheet_more.png` (polymer). | 2–3 type props per industry and one type joke near the console. |
| 12 | minor | ART-HAB | 2026 pop-culture parody is thin next to the AI satire. | Seen only "DJ LATENCY", "TOUCH GRASS", "HOME SWEET POD", "WIFI: LOL". | 8–10 original parody posters (a reality show, a band, a battle-royale game, a baking show, a short-video app), original names and art. |
| 13 | minor | ART-HAB | Airlock eye renders still show a wall. The 2026-10-03 log says "no view inside geometry". | `airlock_m_eye1` (80 % wall), `airlock_m_eye2` (100 % wall). | Eye spots at the chamber centre facing the doors; re-render; look. |
| 14 | minor | ART-HAB | Bare ceilings and upper walls. | Medical plain dome (`ring_medical2_*`); lab flat lavender triangles (`ring_research_lab_180`); cantina blank 1.5 m grey band (`ring_cantina_120`). | Liner panels back in these rooms; neon or signs on the cantina band. |
| 15 | minor | RENDER | A residence unit at night is almost black. | `n_residence_c_a`, `n_residence_c_c`. | Lamp pools and one omni in the followed unit. |
| 16 | minor | ART-NPC | (Cross-reference, people area.) Sleepers lie on top of the covers, crouched, shoes on the sheet. | `habitat_a`, `ring_lounge_60`. | For the people critic. |

## The 5 weakest room types

| # | room | why | first fix |
|---|---|---|---|
| 1 | apartment_block | cubicle units, camera trapped by boards, dark bare penthouse ceiling, one joke prop | faults 4, 5, 6 |
| 2 | residence_tube (Family, Executive) | cubicle units, bare white boards, one joke prop, Executive not richer | faults 4, 5 |
| 3 | storehouse | camera inside racks, narrow aisles, few jokes | faults 5, 8 |
| 4 | mine (industry family) | shared wall kit, black boxes and orange posts, no joke at eye height | fault 11 |
| 5 | greenhouse | crops are boxes; sunlight and signs are good | fault 7 |

## Gap to 0.80

Textures (fault 3), light colour per role (2), no sky through walls (1), units redesigned (4–6), real plants (7).
0.90 needs hand-dressed hero corners per room and animated screens.
