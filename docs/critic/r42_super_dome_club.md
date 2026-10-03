# Critic round 42: super dome, club, residences, civic modules (in game)

Date: 2026-10-04 · Critic · Rubric: `docs/critic/v5_rubrics.md` §3.7, §3.8, §3.9; V5_DESIGN §8, §15, §16; `docs/V5_RUN3.md`.
Pass ≥ 0.65.

**Evidence.**
- Build `build/web_v5play3` (e9b1d35, pck 186.2 MB). `tools/shoot.mjs --gpu`, 1600×900, headless.
- Saves: showcase_v5 (134 people), dome_v5.
- 132 shots and crops of my own in `art/critic/r42/dome_civic/`. I looked at every shot that I cite.
- Probe: `art/critic/r42/dome_civic/probe/dome1.json`. Perf: `perf_follow_dome_out.json`, `perf_night250_out.json`.

**Not seen.**
- Build stages: both saves have a finished dome.
- Lift cabs moving: I have single frames only.
- A class with a teacher, and an officer at the security desk.
- The club open in normal play. It is closed in both saves. I saw the dancers only with `robots open`.

**fps: not valid.** I measured median 15 fps (dome follow) and 12 fps (night, 250 m). The CPU load from other processes
was 54 % and 85 %. That breaks the agreed method, so I apply no cap. RENDER must measure again on a quiet machine.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| super_dome | 0.66 | 0.56 | 0.70 | **0.64** | 0.81 (r39, overview) | **FAIL** |
| residences | 0.74 | 0.62 | 0.70 | **0.69** | 0.77 | PASS |
| civic_modules | 0.76 | 0.66 | 0.72 | **0.71** | 0.76 | PASS |

**super_dome.**
- The §15 close-view gate applies now. In the dome, bodies go through furniture (findings 1 and 2), so appeal is capped at 0.60.
- DoD item 3 fails in the dome.

## What works

- **Overview.** By day the dome reads as geodesic glass over a 5-storey ring (`A_day250`, `A_day110`). At night the windows
  are lit in several colours, with joint lights and a rim line (`A_night110`). I saw no z-fight on the glass.
- **Atrium (L1 cut, day).** The pool, slide, umbrellas, fountain, park strip, glass lifts, escalators, neon names and
  frame shadows read as a resort (`G_party_l1`, `B_stage_atrium`, `C_sel_f1`).
- **Hotel floor.** The L3 rooms are furnished (`A_floor3`). The floor cutaway works from L1 to L5.
- **Robot dancers.**
  - They are now lit: chrome, a visor light bar, a chest light and visible joints. They are clearly machines.
  - The 3 robots move out of step. Tone: PASS.
  - The LED tiles no longer blow out (`B_stage3_0`, `B_stage16`, `B_stage3_2`).
- **Prism Shift.** The cabinet screen runs the neon tunnel and the prism ship (`B_prism`).
- **Staff and seating.** The bartender wears `uniform_food` (`B_bar_work`). At an L1 table, two people sit correctly
  (`E_sleeper_side`).
- **Venues tab.** It shows 15 venues with staff, price, quality and state. The floor selector shows 5/4/3/2/G/All
  (`H_venues_a`).
- **Residences.**
  - At 110 m and 250 m, each tube reads as a half-tube with a home badge, and it differs from a dome (`D_civic110`, `D_civic250`).
  - The apartment floor cut hides the upper floors (`D_apt_f1`, `C_apt_sel_f1`).
  - In the staged fill, people lie on beds and sit at desks and sofas with no clip (`D_apt_fill_f1_crop`, `D_res0_fill_crop`).
  - The penthouse terrace reads as a reward (`D_apt`).
- **Civic modules.**
  - Each module is named by its colour and silhouette (`D_civic110`).
  - A prisoner sits inside a barred cell, and the bars are clear of the bunks (`D_jail_night_crop`).
  - Shoppers browse in the retail module, and the satire signs read: SALE 50%*, TOUCH GRASS (`D_follow_retail`, `D_follow_park`).

## Findings (most severe first)

| # | sev | owner | what and where | fix |
|---|---|---|---|---|
| 1 | blocker | RENDER | **L1 bar.** The guest sits at chair height in front of a high stool. The stool goes through her lap and forearms. Her back is to the counter, and the clip is `sit_idle` (`A_atrium_f2`, `A_atrium_f2_crop_stool`, `B_bar_seat`). | Use `sit_bar_stool` at `Seat_bar_*` with a 0.75 m seat. Turn the anchor yaw 180° to face the counter (ART-B, or in fx_npc). Add the dome anchors to `render_seat_check`. |
| 2 | blocker | RENDER | **Dome hotel beds.** The sleepers float 0.4–0.5 m above the bed and lie across it. One head is in the lamp, and the legs go through the armchair. 3 of 3 sleepers (`C_club_f0`, `C_arcade_f0`, `C_plaza_f1`, `G_follow_club0`). | Put the lie pose at mattress height, along the long axis of `Bed_3/4/5_*`. Add the dome beds to the seat and ground gates. |
| 3 | major | RENDER | **Floor cut.** With a floor cut, people on hidden floors still show. They hang in the sky or lie on the ring wall (`B_lift` 4, `B_lifeguard` 2, `B_bouncer` 3, `G_party_l2` 4, `C_sel_f2`). | Hide each body whose floor is above `dome_view_floor` (the apartment block too), as fx_robots does with `dome_k`. |
| 4 | major | SIM | **The Club never opens.** In showcase_v5 its only DJ (Otis) is in jail, and dome_v5 is closed too. At 22:48 the club is empty and the robots stand idle (`G_evening_l2`, `I_dome5_stage_night`). UI shows "No staff. Staff 1 of 1: Otis" (`H_club_row_crop`). | Rebuild both saves with a free DJ and a backup. Assign a new DJ when the DJ is jailed. UI: show "Otis is in jail". |
| 5 | major | RENDER | **Follow framing in units.** <br>– Dome hotel: the camera sees only a wall at 2 of 3 orbits (`C_club_f1`, `C_club_f2`). <br>– Apartment: wall only at 2 of 2 orbits (`E_apt_follow0/1`). <br>– Tube sleepers: the frame shows the shoe soles, 2 of 2 (`D_follow_res0`, `D_follow_academy`). <br>– Bar: the camera is behind the counter (`A_atrium_f0`). <br>– The worker is out of frame (`C_hotel_f0`). <br>Probe dome1: head 1.40 px, camera 3.48 mm (target 0.5 px, 2 mm), at 34 fps. | For a person who lies or sits, put the camera at the head side, 1.6–2.2 m away, 30–40° down. In a small room, keep the camera inside the room box and use the orbit with the most clearance. Never more than 50 % wall in the frame. |
| 6 | major | ART-B | **Atrium floor holes.** Terracotta triangles show through the plaza by the pool. Slivers show at every ring seam (`A_pool_lounger_b`, `A_pool_lounger_b_crop_floor`, `E_sleeper2_side`, `B_plaza_night`). | Weld the plaza rings. Add a solid base disc 2 cm below the floor. |
| 7 | major | ART-B | **Lamp post in the pool.** A lamp post stands in the pool water (`B_lifeguard_crop_post`, `C_sel_f1`, `C_sel_f2`). | Move it to the deck, at least 0.5 m from the coping. |
| 8 | major | RENDER | **Night interior is cold and dark.** <br>– Atrium: the plaza is navy-black, the pool blows out to white, and there are no warm lamp pools (`G_evening_l1`, `B_pool_night`). <br>– Rooms: hotel and executive rooms have no light (`B_hotel_desk`, `G_evening_hud`). | Make `Light_Lamp_*` warm lights (2700 K, 6–8 m) at night. Cap the pool emission at about 0.6. Turn on the lamps in occupied rooms. |
| 9 | major | ART-B | **Club at close range.** <br>– The floor between the tiles is black at night. <br>– The DJ booth is a brown box, and the booths are black. <br>– The wall screen is still noise with 3 black blocks (open since r41). <br>– The camera at the club bar sees black. <br>– There is no bouncer or ADULTS ONLY sign at the bouncer anchor. <br>Shots: `I_dome5_stage_night`, `B_dj`, `B_booth`, `B_clubbar`, `B_bouncer`. | Floor palette cell: grey 0.10 with sheen. Give the wall screen a UV and a visualiser shader (with RENDER). Build a DJ booth with decks, mixer and a neon front. Add upholstered booths. Fix the bar view. |
| 10 | major | SIM | **The dome is not busy.** By day there are about 12 people in the atrium. At dusk there are 0 (`C_sel_f1`), and at night about 4. The colony has 134 people and 14 visitors. | In the evening (18–24 h), send off-duty adults and tourists to the atrium and the venues. |
| 11 | major | ART-B | **Dome props are boxes at follow distance.** <br>– Venue: plain cubes (`C_hotel_f0`). <br>– Grocery: produce slabs (`B_grocery`). <br>– Arcade: 8 plain cubes as prizes (`B_arcade`). <br>– Loungers: slabs with a loose board (`A_pool_lounger_b`). <br>– Rooms: bare hotel and family rooms, and a TV inside the window (`B_family_seat`, `B_exec_desk`). <br>– Outer promenade: a blank wall (`A_gallery_f0`). <br>– Gates: no door kit (`A_gallery_f1`). <br>– No §15.3 satire anywhere in the dome. | Real lounger, prize and produce props. Art, a rug and clutter in each unit type. Move the TV off the glass. Windows and signs on the outer ring. The v3.1 door kit at the gates. About 10 satire pieces (menus, venue signs, a "SMART POOL" sign). |
| 12 | major | ART-B | **Bare trees.** The promenade and park-strip trees are bare twigs (`A_floor1`, `C_sel_f1`, `G_party_l2`). | Use leaf-crown trees from the greenhouse family. |
| 13 | major | ART-HAB | **Units look like cells.** <br>– The apartment unit is a dorm cell: grey walls and two box beds, with no window, rug, art or lamp (`D_follow_apt`). <br>– From above, the partitions read as a cubicle maze (`C_apt_sel_f1/f2`). <br>– 3 of the 4 tubes have the same layout (`D_res0/1/2`). | Per unit: a floor and wall palette (4 of them), a rug, art, a lamp, 2 satire props and a window. Make 2–3 layout variants, picked by building id. |
| 14 | major | RENDER | **Homes are cold at night.** The units are cool white and violet. The storehouse is warmer than the homes (`D_res0_night`, `C_apt_sel_f1`). | Housing light at 2700–3000 K (V3 §7.3). |
| 15 | major | ART-HAB | **Park.** All about 25 trees have the same lollipop shape. The flowers are tiny gems. The pond is a flat disc with no glint, and the trunks are plain cylinders (`D_park`, `D_follow_park`). | Use 3 species with scale jitter, blossom cards in 4 colours, and the water shader on the pond. |
| 16 | minor | RENDER | **Markers in the shoulder view.** In the shoulder camera used for evidence (`viewanchor`), 6–8 markers draw through the walls in one pile: WORN, OUT OF REACH, FULL, HULL BREACH (`B_lifeguard`, `B_restaurant`, `B_family_seat`). | Hide the markers whenever the rig is in shoulder mode. This is needed for the §15.2 watch mode. |
| 17 | minor | SIM | **Venue floors.** Content gives floor 1 to barber, credit_office and post_office (the UI shows "floor 2"). The model has these shop fronts on L1. | Set floor 0 for these three in `content/buildings.json`. |
| 18 | minor | RENDER | **Tube glare.** One residence tube blooms to a white-yellow blob at night (`D_civic110_night`, x1060–1210). | Cap the window emission. |
| 19 | minor | ART-HAB | **Retail at 1.8 m.** The goods are flat boxes, and 3 emissive boxes blow out. The "GET 1 … FREE" sign is clipped. About 35 % of the floor is bare (`D_follow_retail`, `D_retail`). | Use shaped goods and no emission on the stock. Move the sign clear of the band. |
| 20 | minor | ART-HAB | **Security office.** The inside is still mostly white and grey (`D_security_crop`). | Black panels with red accents. |
| 21 | minor | ART-HAB | **Jail.** 3 stacks of grey cubes stand in the middle and look like placeholders. The cells have no numbers (`D_jail_night_crop`). | Exercise kit or tables. Cell numbers and door frames. |
| 22 | minor | ART-B | **RESTAURANT sign.** A palm trunk cuts the sign, so it reads "RESTAURP T" (`A_pool_lounger_b`). | Shift the sign or the palm. |
| 23 | minor | RENDER | **Evidence tools.** `stageview 6` puts the camera in a wall, and the `Work_club_0` view is black (`B_stage6`, `B_clubbar`). | Clamp the stage view to the room. |

## Gap to 0.80 (super_dome)

- Fix findings 1–3 and 5: no bodies through furniture or in the sky.
- An open, busy club at night.
- A warm night atrium.
- Close-range props and satire in the dome.

0.90 needs the night 250 m shot to glitter with colour. Today the windows are mostly white, and the signs are about 8 px.
