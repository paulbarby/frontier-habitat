# Critic round 41 — v5 run 3: close interiors, HR office, planets, follow view, club robots, people

Date: 2026-10-02 · Critic · Rubric: `docs/critic/v5_rubrics.md`, V5_DESIGN §15 and §17, `docs/V5_RUN3.md`
· Pass ≥ 0.65. The full detail is in `round_41_v5_run3.json`.

**Evidence.**
- ART-HAB's Blender views: `art/interiors/*_eye0..2.png` (49 views), day cutaways, night samples, HR office S/M/L.
- RENDER's inputs: `art/critic_input/render/180-194`, `199_*`.
- 38 in-game shots of my own: `art/critic/r41_*.png`. Build `build/web_v5preview` (325d0af, exported 18:33),
  `tools/shoot.mjs --gpu`, HUD on. Saves used: showcase_v3_late (indoor, outdoor, planet looks, storm) and dome_v5
  (dome, club).

**Not seen.**
- The new ceilings and the HR office in the game: the preview build is older than those files.
- The robot dancers in my build: `robots open` returned "unknown command", and my 7 club shots show no robot.
- Indoor night in the game: `time 540` did not change the indoor light.
- The V-key follow path: I entered the follow view by a debug command.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| interiors_close | 0.64 | 0.58 | 0.70 | **0.64** | **FAIL** |
| hr_office | 0.72 | 0.60 | 0.72 | **0.68** | PASS, provisional (Blender only) |
| planets | 0.72 | 0.70 | 0.72 | **0.71** | PASS |
| follow_view | 0.58 | 0.52 | 0.66 | **0.59** | **FAIL** |
| club_robots | 0.62 | 0.55 | 0.66 | **0.61** | **FAIL**, provisional |
| people_in_game | 0.66 | 0.58 | 0.65 | **0.63** | **FAIL**, provisional (ART-NPC mid-rebuild) |

Mean 0.643. On this evidence, two definition-of-done items are not met: item 4 (interiors ≥ 0.65) and
item 1 (no body through the camera).

## 1. interiors_close — 0.64 FAIL

**What works.**
- The §15.3 satire is in every room I could see. The best lines read at eye height:

  | room | lines |
  |---|---|
  | kitchen | "SPECIALS: TOFU BYTES / LATENCY LATTE / DUST CAKE", "TODAY: ALGAE AGAIN" |
  | medical | "PLEASE WAIT: THE AI IS THINKING", "AI-POWERED FRIDGE V2.6" |
  | oxygen plant | "BREATHE IN. WE CHECKED.", whiteboard "SPRINT 12: MAKE IT AI" |
  | cantina | "LAST ORDERS: NEVER" |
  | lounge | "CHILL.EXE IS RUNNING", "TOUCH GRASS (FAKE)" |
  | academy | "THE CLOUD" planet mobile |
  | fabricator | the giant rubber duck |
  | habitat | "SHOES OFF / ROBOTS TOO" |

  The jokes are original, playful and never mean.
- Every dome room has a ceiling at eye height, so the follow view now feels enclosed.
- Role identity is clear in kitchen, cantina, lounge, greenhouse, research lab, academy, retail, park and
  distillery.
- In the game, the lounge and research lab look warm and lived-in (`r41_in_day_1`, `r41_in_night_0`).

**Faults.**
- **Broken evidence.** In these views the camera is inside geometry and shows only a wall or a tank:
  `airlock_m_eye*`, `junction_eye*`, `water_recycler_m_eye*`, `storehouse_m_eye2`, `cold_storage_m_eye0`.
  Three room types have no eye-height evidence. ART-HAB's log says "looked at".
- **Residence tube L, family and executive.** The ceiling liner fails under the vault: big grey triangular
  shards hang into the room (`residence_tube_l_eye1`).
- **Apartment block.** From floor 1 you can see the furniture of the upper floors through the slabs.
- **Residences look like cubicles.** The partitions are 1.30 m high, the units have no ceilings, and there is
  almost no satire in the units.
- **The 17 industry types are one room.** They share the same sunburst ceiling, console, bench, wall ring
  and band; only the centre machine changes.
- **Realism at 1.8 m is low.** Every surface is a flat colour with no texture, wear or decals. Every room
  has the same white light. Large tile floors are empty (HR L, medical, water recycler, park).
- **Security office.** It is white and grey; the rubric asks for black and red.

**The 5 weakest room types, with fixes (all ART-HAB).**

| # | room | fix |
|---|---|---|
| 1 | residence_tube L (family + executive) | Make the liner follow the vault or skip it there; reject liner triangles longer than 1.5 m. Raise the partitions to 2.1 m (needs RENDER's answer to the 17:50 request). Give each unit a 2.4 m ceiling and 2 satire pieces. |
| 2 | apartment_block_m | Put a down-facing slab underside under every upper floor (hidden with the floor cutaway). Add eye views that look up from F1 and F2. |
| 3 | water_recycler_m | Make the eye views work. Add a hero piece (a staged filter column, "TODAY'S WATER WAS YESTERDAY'S COFFEE"). Fill the bare floor with pipe runs, pumps and a sample bench. |
| 4 | cold_storage_m / storehouse_m | Make the aisles at least 1.6 m wide (the camera clips the racks today). Add aisle-end signs, floor numbers and 2–3 jokes. |
| 5 | airlock / junction | Make the eye views work. The junction is an empty drum: add benches, a wayfinding totem, a lost-and-found shelf and a notice board. |

## 2. hr_office — 0.68 PASS (provisional)

**What works.**
- Every §17.1 item is there:
  - the reception counter with stress balls;
  - two interview booths;
  - the WELLBEING.AI kiosk ("1 GREAT 2 GREAT 3 OTHER*");
  - the padlocked suggestion box, the ficus, filing banks and standing desks;
  - "YOUR FEELINGS ARE VALID (PENDING REVIEW)", "SYNERGY", and the emotional queue rings on the floor.
- The jokes read at eye height.
- The roof sign "WE ARE LISTENING*" reads from above.

**Faults.**
- The L floor is mostly empty: 8 benches stand at random angles on bare tiles.
- The interview rooms are 1.4 m booths, not rooms.
- Nothing funny is near the reception or the queue.
- From above, the roof badge reads as a "3".
- I have not seen it in the game.

## 3. planets — 0.71 PASS

**What works.**
- **Airless** is striking, also at eye height: a black sky with stars by day, a hard white sun, black
  shadows and grey regolith.
- **Cold** reads as cold: frost, a pale sky, ice haze and blue nights.

**Faults.**
- A yellow-green ground patch glows on airless and cold.
- The cold frost is a blotchy camouflage pattern over a pink base.
- **A wind turbine turns on the airless planet.** This is a SIM content fault (note to the orchestrator).
- There is no frost on structures at night.
- The minimap stays orange on every planet (UI).

## 4. follow_view — 0.59 FAIL

| check | result |
|---|---|
| roofs on | **PASS** (every indoor shot has a ceiling) |
| no weather inside | **PASS** (storm forced, 0 particles inside) |
| grainy occluder | **FAIL** (191: a screen-door stipple over a third of the frame) |
| camera framing | **FAIL** (see below) |
| ceiling | **PASS** |

**Framing.**
- In 5 of my 15 indoor shots, and in RENDER's 192 and 194, the camera faces a wall or a pillar.
- In `r41_in_day_5` and 194 the person is not in the frame at all.
- Indoors the person sits in the centre and fills 40–60 % of the frame, with no look room ahead.
- Outdoors the framing is good: the person is on the left third.

**A body through the camera.** `r41_in_storm_0`: another walker passes about 0.35 m in front of the lens and
fills 60 % of the frame.

**World markers stay on in the follow view.**
- status badges (190, 193, 194);
- "WORN 80%" labels inside rooms;
- outdoor POI labels ("METEORITE FIELD / RICH DEPOSIT needs anyone") drawn through the dome over the mall.

190 also has a white line across the whole screen.

**What works.** The glass bubbles are readable and never cover the face. The dome mall reads well at eye
height (`r41_dome_day_2`).

**HUD.** In my debug follow, the full HUD stays on and there is no follow card. UI must confirm the V path.

## 5. club_robots — 0.61 FAIL (provisional, RENDER's 199 only)

**What works.**
- The dancers are clearly machines and move differently from frame to frame.
- The poles are in the contract, and the framing is a performance.
- **Tone: PASS.**

**Faults.**
- The dancers are unlit black silhouettes. There is no spot and no rim light, so the chrome does not read.
- The floor is black, and the LED tiles blow out to white.
- The wall screen is a noise texture with black holes.
- The club has no people.
- The robots are missing from the preview build.

## 6. people_in_game — 0.63 FAIL (provisional)

**What works.**
- A crowd reads as different people: skin, hair and outfits differ.
- Faces at 0.5 m are plausible.
- The walk is smooth.

**Faults.**
- Arms hang straight and stiff in walk and idle.
- Each garment is one glossy colour: the black tee reads as latex. No folds show at 2 m.
- Idle people at a counter show only their backs for minutes.

## Gap to "stunning"

**Interiors (0.64 → 0.80):**
- a texture atlas and decals;
- light colour per role;
- variants for the industry family;
- filled floors;
- fixed residence geometry.

0.90 needs hand-dressed hero corners and animated screens.

**Follow view (0.59 → 0.80):**
- a framing rule (thirds, look room, no wall within 0.8 m of the lens);
- a smooth near fade;
- no world markers;
- the HUD dimmed;
- a soft background blur.

0.90 needs the §15.2 watch mode.

## Top fixes (owner)

1. RENDER — the follow framing rule: never a wall within 0.8 m across the centre, the person on a third,
   look room ahead. Proof: 30 indoor shots, 0 failures.
2. ART-HAB — the residence-tube ceiling shards.
3. ART-HAB — working eye views for every room type (airlock, junction, water recycler, storehouse, cold
   storage, medical).
4. RENDER — hide every world marker in the follow view; remove the white line.
5. ART-HAB — a texture, decal and per-role light pass.
6. RENDER — a smooth fade for bodies within 0.8 m of the lens; replace the stipple occluder fade.
7. ART-HAB — apartment slab undersides; residence partitions, unit ceilings and satire.
8. ART-HAB — variety in the industry family; fill the floors.
9. RENDER — light the club dancers and cap the LED tiles; ship the robots in the preview (wall screen:
   ART-B).
10. RENDER — remove the green patch on airless and cold; smooth cold frost; frost on structures. SIM: no
    turbine on airless.
11. UI — the V follow: dim the HUD, collapse the dock, show the card; the minimap palette per planet.
12. ART-HAB — the HR waiting area, interview rooms, and jokes at the reception.
13. ART-NPC — relaxed arms; a matte fabric shader with folds.
14. ART-HAB — a black-and-red security office.
