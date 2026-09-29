# CRITIC rubrics for version 5.0

Date: 2026-09-29 · Critic · Contract: `docs/V5_DESIGN.md` (commit b4033f9), §0, §1, §3, §4.3–4.4, §6.2–6.4, §7, §8, §12.

## 1. Method (unchanged)

- There are 3 scores per subject, each 0.00–1.00:
  - **consistency:** it fits the contract and the other game assets, and variants and sizes agree.
  - **appeal:** it looks good at the game camera and close up, and would pass in a shipped game.
  - **style:** it matches "clean industrial frontier on a dusty orange world", the V4 glass-and-metal
    UI, and the V5 direction.
- The subject score is the mean of the three. **Pass ≥ 0.65.** The mean over all subjects must not
  drop. The v4.0 baseline is **0.761 over 32 subjects** (`round_23.json`).
- **Calibration:**

  | score | meaning |
  |---|---|
  | 0.50 | placeholder |
  | 0.65 | acceptable in a shipped indie game |
  | 0.80 | good |
  | 0.90 | excellent |

- **"Stunningly modelled"** is Paul's aim, not the pass mark. I report the gap to it on every people
  subject: what must change to reach 0.80 and 0.90.
- **Evidence.**
  - I judge only evidence I have looked at.
  - I take my own unstaged shots with `tools/shoot.mjs --gpu` (headless; never a window). I render
    my own views with Blender `--background` when a model is supplied.
  - Blender-only evidence gives a **provisional** score. The final score needs in-game evidence.
  - Missing evidence that the contract asks for is written as a gap, and the axis it affects is
    capped (see the caps below).
- **Output.** For every subject under 0.80, a numbered fix list: most important first, with what,
  where, how much, and the owner.
- **Hard caps.** They apply to any subject, whatever the other axes score.

  | condition | score cap |
  |---|---|
  | Content that breaks the §0 tone rule (nudity, explicit content, a child in a romance, fight, bar or club) | subject 0.40, and a stop report to the orchestrator |
  | A body visibly through clothing, furniture or a wall in the evidence | appeal 0.60 |
  | Text a player must read that is unreadable at 1600×900, 100% scale | appeal 0.60 |
  | A draw or size budget of §0 broken, as measured and reported | consistency 0.60 |

## 2. Distances and cameras I test at

| name | how | people height on screen |
|---|---|---|
| **close-up** | follow view, 1.5 m from the face, front and ¾ | head about 300–450 px at 1600×900 |
| **follow** | follow view default (0.55 m right, 1.9 m back) | person about 500–700 px |
| **room** | cutaway at 12–20 m | 60–120 px |
| **game camera** | v4 overview at 40–110 m | 12–40 px |
| **dome overview** | 250 m and 110 m, day and night | — |

---

## 3. Subjects

### 3.1 `people_closeup` — 6 adult variants + 2 children (pilot: m1 + f1)

**Evidence I need:**
- Front and ¾ views at 1.5 m in uniform and casual, by day and in an interior light.
- One shot outside in the suit, with the visor showing the face.
- The same person at room and game-camera distance.
- My own Blender render of each GLB: neutral light, a 50 mm camera at 1.5 m.
- Triangle counts (LOD0 ≤ 14 k body+outfit, LOD1 ≤ 3 k) and the pck size effect (ART-NPC ≤ +6 MB).

**Consistency:**
- Each adult is 1.62–1.92 m tall.
- The 6 variants differ in build, height, face shape, skin tone, hair style and hair colour; a
  line-up is not "one mesh, six colours".
- Tint parameters make a crowd of 20 read as 20 people.
- The children have child proportions (head-to-body ratio about 1:6), not shrunk adults.
- Palette and detail density match the v3 suit and the rooms.
- LOD1 keeps the silhouette and hair colour.

**Appeal:** at 1.5 m, face, hands and cloth decide the score.

| score | what I expect at 1.5 m |
|---|---|
| 0.50 | faceted head, painted-on or missing eyes, mitten hands, flat cloth |
| 0.65 | a smooth head of correct proportions; eyes with an iris and a highlight; brows, nose, lips and ears modelled; separated fingers; some folds at elbows and knees; no visible facets on the silhouette |
| 0.80 | a believable, appealing face with variety between variants; eyelids and a lip line; hair with volume and strands or cards that read as hair; cloth with seams, pockets and folds at waist, elbows and knees; clean shading, no AO blotches; it holds at ¾ as well as front |
| 0.90 | faces that carry expression; a shipped stylised-realistic look (a "Planet Coaster / The Sims 4" level of finish at this camera) |

**Style:** stylised-realistic, not cartoon, not uncanny. The frontier work-wear language holds:
coveralls, department stripes, practical casual. The glass/metal colony palette holds.

**Hard checks:**
- No poke-through at the test poses (§1). This is the appeal cap.
- No uncanny eyes: dead flat, misaligned, or too white.
- Hair does not clip the collar or the helmet ring.
- A skin tone or hair colour does not change with the outfit.

---

### 3.2 `people_outfits` — every outfit on 2 variants, stripes, insignia

**Evidence I need:**
- A line-up of the 13 outfits on one male and one female variant: 6 uniforms, 3 casual, swimwear,
  prison and suit, plus school on a child.
- Close-ups of the department stripe and the rank insignia on each uniform.
- The outfit switch in game (on shift → off shift).

**Consistency:**
- Each role reads at the room camera by colour and silhouette, without a label: engineering amber
  coverall, science blue jacket, food apron and green, medical white and red scrubs, security black
  armoured vest, command tailored jacket.
- The stripe colours equal the v4 family accents.
- Rank reads at the follow distance.
- The outfit rule from §1 is obeyed in game.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | distinct garments with modelled collars, cuffs and hems, and no poke-through |
| 0.80 | material variety (canvas, knit, denim, fabric sheen), belts and pockets with real depth, casual wear that looks off-duty and personal |
| 0.90 | outfits that make a crowd scene look designed |

**Style:**
- The uniforms belong to one colony: one cut family with department colour.
- Casual wear is plausible for a frontier colony, not modern fashion catalogue.
- Swimwear is modest (§1). Prison is orange.

**Hard checks:**
- A child never wears club or swim adult outfits.
- No outfit shows skin through gaps at the test poses.
- The suit visor face matches the variant.

---

### 3.3 `people_animation` — ≥ 30 new clips and paired clips

**Evidence I need:**
- Contact sheets of every new clip: 4 frames each, both sexes, one child.
- `npc_verify` and `npc_check` reports: loop seams, foot slide, transitions, pops.
- In game, from **my own** frame strips at 30 fps (10 consecutive frames):
  - hug, argue, punch → hit_react → fall_down → get_up;
  - kiss_brief, handshake, escort_walk + handcuffed_walk;
  - dance, sit_bar_stool, swim.
- The paired-clip offsets (`npc_pairs.json`).

**Consistency:**
- One skeleton, and all v3 clips still pass.
- Paired clips meet: hands on backs in a hug, hands meet in a handshake, a punch lands at the
  partner's head in the same frame as hit_react. Partners do not interpenetrate by more than 2 cm and
  do not float apart.
- Seams ≤ 1°, transitions without pops (the v3 `npc_check` rule).
- Children use their own proportions without foot slide.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | readable poses at the room camera, with weight shifts |
| 0.80 | anticipation and follow-through, secondary motion (head, hands, hair), emotions that read from the body alone (argue vs laugh vs sulk) |
| 0.90 | gestures with personality per variant |

**Style:** PG-13 (§0).
- kiss_brief is short: faces meet, no more.
- Fights are clumsy and short, not gore.
- Club and robot dances are a performance style, not sexual.

**Hard checks:**
- A child is never in a paired romance, fight or club clip in game.
- No partner body passes through the other.
- No clip pops in a blend (from `npc_check`).

---

### 3.4 `follow_view` — over-the-shoulder camera, bubbles, follow HUD

**Evidence I need:**
- **My own in-game strips:** indoors in a habitat, outdoors on foot, through a doorway, in a dome
  gallery with 30 people, turning a corner beside a wall.
- Bubbles in a conversation of 3–4 people.
- Night indoors and outdoors.
- The measured fps (≥ 45 with 30 people) and the frame-time spikes.

**Consistency:**
- Offsets as §3 (0.55 m right, 1.9 m back, eye + 0.15 m).
- Orbit ±70°, zoom 1.2–4 m, Q/E swap the shoulder.
- The camera never passes through a wall; it pulls in when blocked.
- The cutaway hides the roof, the walls between camera and person, and the floors above.
- Bubbles show only within 14 m and in line of sight, never overlap, at most 6.
- Emotes use the §3 set.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | smooth follow without jitter, readable bubbles, the person clear of clutter |
| 0.80 | cinematic framing (the person on a third, look room ahead), gentle springs, a depth cue behind (dim or blur), bubbles that feel like the glass UI and never cover the face |
| 0.90 | a view a player chooses to stay in |

**Style:**
- Bubbles and the HUD card use the V4 glass-and-metal theme.
- The rest of the HUD dims.
- Close lights and interiors hold up at this camera: the v3 interiors were made for 12–20 m, so
  close-range texture, bevel and prop quality are judged here.

**Hard checks:**
- The camera never passes through a wall or a prop.
- No bubble text is under 12 px or covers the followed person's face.
- No person is shown in the wrong outfit for the place.

---

### 3.5 `regolith_rag` — the tabloid window with photos

**Evidence I need:**
- 3 issues (a quiet day, a scandal day, a riot day), the back-issue list, and a story click →
  follow.
- The `photo()` output for 5 poses (argue, kiss_brief, hug, punch, handcuffed_walk).
- The tabloid text in `content/tabloid.json`: I read a sample of 40 headlines.

**Consistency:**
- The layout of §4.3: red masthead THE REGOLITH RAG, issue number and date, a lead story with a huge
  headline and a photo, 3–6 smaller stories, gossip column, Couple Watch, Feud Watch, approval poll,
  small ads, and the "Serious news" strip.
- The stories match the social log: the right names, places and outfits in the photo.
- It sits in the V4 glass-and-metal frame.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | it reads as a newspaper at a glance; the photos show who and what |
| 0.80 | real tabloid energy (condensed bold headlines, kicker lines, rules, a halftone or grain photo with a caption), fun puns, a layout that varies with the stories |
| 0.90 | a page a player screenshots to share |

**Style:**
- Tabloid voice is the one exception to STE (§0). It must be funny, never explicit, never cruel to
  children, and never about children in scandals.
- The "Serious news" strip is plain STE.

**Hard checks:**
- No explicit headline.
- No child in a scandal, fight or romance story or photo.
- Photos show the named people, not random bodies.

---

### 3.6 `social_ui` — personnel file, org chart, unrest banner (+ social, housing, academy windows)

**Evidence I need:**
- A personnel file with a portrait, and a review and a discipline flow with the predicted effect and
  the confirm.
- The org chart for one base, with a drag.
- The unrest meter tooltip, and protest, strike and riot banners with their response buttons.
- The social tab graph, the housing tab, the academy window, the floor selector.
- Scale 80% and 125%, and 1280×720.

**Consistency:**
- Every panel follows the V4 theme and the round-15 rollout rules: rim buttons, metal tabs, wells,
  seam lists.
- The window manager rules hold (V4 §7).
- Each number shows its reason (the design aim, (b)).
- Discipline shows its expected effect before confirm (§6.3).

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | clear, dense, readable |
| 0.80 | a relationship graph that reads at a glance, an org chart that feels like a command board, banners that feel urgent without shouting |
| 0.90 | the player understands *why* someone is angry in two clicks |

**Style:** plain STE text; calm palette with the family accents; red only for real danger.

**Hard checks:**
- Text ≥ 12 px.
- No window covers the HUD essentials.
- Every discipline action asks to confirm.

---

### 3.7 `residences` — residence tube (Family, Executive; M/L/XL) and apartment block (XXL)

**Evidence I need:**
- Blender beauty cutaways of every size and variant, day and night.
- Doorway compositions.
- In-game at 110 m and 250 m, the cutaway, and the floor cutaway of the apartment block at each
  floor.
- The follow view inside one family unit and one penthouse.
- The pck size effect (ART-HAB ≤ +4 MB).

**Consistency:**
- The **half-tube** silhouette (a vault lying on the ground, ribs, end walls with windows, porch doors
  at each end, side links).
- Unit counts equal §7.
- Anchors for beds, bunks, tables and desks are on free floor.
- Floors have a lift or stair core, and the floor cutaway hides the upper floors.
- The v3.1 door kit is used, and the decals hide at doorways.
- The room-identity test: a residence is named at 250 m without a label, and the tube differs from a
  habitat dome.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | furnished units that read as homes |
| 0.80 | Family and Executive clearly different in quality (bunks and a family table vs office, lounge and private bath); a penthouse terrace under glass that looks like a reward |
| 0.90 | a unit you would want to live in |

**Style:** the colony hull, frame and accent language; warm interior light (the V3 §7.3 rule); housing
yellow accent.

**Hard checks:**
- No floor or furniture visible through an upper floor in the floor cutaway.
- No person on the wrong floor in game.

---

### 3.8 `civic_modules` — retail, park, academy, security office, jail (all sizes)

**Evidence I need:** the same as `residences`, for each module and size, plus in-game use: shoppers,
park walkers, a class with a teacher, officers at the desk, a prisoner in a cell.

**Consistency:**
- Each module is named without a label at 110 m (the room-identity test):
  - retail: shop fronts and signs;
  - park: a glass dome over green, trees, a pond at L+;
  - academy: a classroom;
  - security: a desk and monitors, black and red;
  - jail: cells with bars and a guard desk, a yard at L.
- Anchors match the SIM tables.
- The park needs water and gives air; the look shows green under glass.

**Appeal:**

| score | what I expect |
|---|---|
| 0.65 | furnished and readable |
| 0.80 | the park feels alive (varied trees, flower colour, a water glint); retail shelves carry varied goods; the jail reads as serious but not grim-dark |
| 0.90 | modules that become the heart of a colony screenshot |

**Style:** the same colony language; the park is the one green place and must stay believable (plants
from the v3 greenhouse family).

**Hard checks:**
- No child in the jail.
- Cells have bars that do not clip the bunks.

---

### 3.9 `super_dome` — XXXXL end game

**Evidence I need:**
- Build stages (foundation → per level → glass → fit-out).
- Overview at 250 m and 110 m, day and night.
- The atrium with the pool, loungers, slide, park strip, fountain and stage.
- A shop gallery on L1–L2 in the follow view.
- The Club with robot dancers (in game, performance loops).
- The gaming lounge with the Prism Shift cabinet (the screen shader running).
- Accommodation L3–L5, the floor cutaway, glass lifts moving.
- The measured fps and draw calls (showcase ≥ 45 fps, ≤ 1,700 draws), and the pck effect
  (ART-B ≤ +4 MB).

**Consistency:**
- Radius 48 m, about 38 m high, a 5-storey ring 14 m deep, a 40 m open atrium open to the dome sky.
- L1–L2 shops, L3–L5 homes.
- All §8 venues present and signed.
- One geodesic glass language, matching the v4 greenhouse and park glass.
- Staff and customers in casual wear, lifeguards and bartenders in `uniform_food`.

**Appeal:** Paul's test: *a glittering city under glass*.

| view | what I expect |
|---|---|
| **night overview, 250 m** | hundreds of lit windows in the ring, signs and neon on the galleries, the pool glowing cyan in the atrium, the glass catching light; the brightest and most alive object on the planet |
| **day, 250 m** | the geodesic pattern reads; the atrium and the pool read through the glass |
| **inside** | a mall and a resort: shop signs, warm light, plants, people everywhere, depth through the galleries |

| score | what I expect |
|---|---|
| 0.65 | it reads as a domed city |
| 0.80 | it glitters at night and feels busy inside |
| 0.90 | the game's key-art shot |

**Style:**
- The frontier colony grown rich: the same hull, frame and accent language, now with retail neon.
- The Club is adult nightlife with a light show; the robot dancers are clearly machines (chrome,
  visible joints, a light-bar face) in a performance style, never sexual.
- The Prism Shift screen is recognisably Paul's game (a neon tunnel and a prism ship).

**Hard checks:**
- Robot dancers show no human anatomy and no sexualised framing.
- No child in the Club, the bar or the gaming-lounge bar area.
- The glass does not z-fight with the ring building.
- The fps budget from §0 holds, as measured.

---

## 4. Earlier subjects touched by v5

These are re-checked so that none drops:

| subject | why it is touched |
|---|---|
| `npc_ingame` | new bodies replace the v3 indoor variant |
| `npc_interaction` | new anchors; bunks, bar stools, benches |
| `npc_paths` | floors, lifts, the dome atrium |
| `room_identity` | new families at 110 m / 250 m |
| `interior_lighting` | the dome and the residences |
| `ui_theme` | the new windows |
| `doors` / `doorway_decals` | the new buildings use the kit |
| `terrain_v4` | the dome footprint on the plateau |

## 5. What I will ask for with each pilot

- **ART-NPC pilot (m1 + f1):**
  - GLBs;
  - front and ¾ at 1.5 m in `uniform_engineering` and `casual_a`, neutral and interior light;
  - 6 new clips as sheets;
  - triangle counts and the MB effect.

  I render my own views and I take the in-game shots when RENDER has them in the follow view.
- **ART-HAB pilot (residence tube L, Family and Executive):** beauty cutaway, night, doorways,
  anchors, and 110 m and 250 m renders.
- **ART-B pilot (dome shell + one gallery level + the atrium pool):** 250 m and 110 m day and night,
  the atrium close up, the gallery at the follow height.
- **UI pilot (the Rag with stub data):** the window at 1600×900 and 1280×720, 3 issues, and the
  photos when RENDER supplies them.
- **RENDER pilot (follow camera + bubbles with the v3 models):** a build where I can enter the follow
  view by command (`follow_view <id>` or equivalent `__fh.cmd`), so that I take my own strips.
