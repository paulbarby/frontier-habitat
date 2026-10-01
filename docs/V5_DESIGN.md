# Frontier Habitat 5.0 — people, society, drama and the city dome

Version 5.0 · 29 September 2026 · Owner: orchestrator

This file is the contract for version 5.0. It adds to `docs/V4_DESIGN.md`, `docs/V3_1_DESIGN.md`,
`docs/V3_DESIGN.md` and `docs/AAA_DESIGN.md`. **Every agent reads V3_DESIGN §0, §9, §10,
V3_1_DESIGN §0, V4_DESIGN §0 and §11, and all of this file before it starts.** Where the files
disagree, this file wins. Numbers live in `content/*.json`. Paul's request, cleaned: `docs/V5_REQUEST.md`
(items 1–26; every item maps to a section below — see §14).

**The design aim ("be wise").** The colony becomes a society. Management stays the core; the people
add depth, stories and trade-offs. Every social system must (a) come from state, deterministically,
(b) be visible and explained (the player can always find out *why* someone is angry, in love or in
jail), (c) be a trade-off, not a chore (discipline works short-term and costs long-term), and
(d) be optional to micro-manage: a player who ignores it gets a working colony with some gossip.
Tone: PG-13 drama — flirting, dates, a kiss, embraces, jealousy, affairs, break-ups, fist fights,
arrests. No nudity, no explicit content, no sexual acts shown. Children never enter the club or the
bars and are never part of any romance, scandal or fight.

---

## 0. Ground rules

All earlier ground rules apply: never open a window on Paul's desktop; Godot only through
`node tools/godot.mjs`; Blender only with `--background`; export to `build/web_<you>/`; keep `check`
clean (no `static var` in scripts that extend project scripts — Godot 4.4.1 exit crash); simulation
authoritative and deterministic; ledgers stay `{}`; player text in plain STE English (the tabloid is
the one exception: it is written in a tabloid voice); report honestly, including what you did not test.

**Budgets (web, `shoot.mjs --gpu`, this PC):**
- v5 showcase overview (2 bases, ~110 people incl. children, a finished super dome) ≥ 45 fps at
  quality high; draw calls ≤ 1,700; no frame over 50 ms in 120 s after load.
- **Follow view** (§3) inside the dome with 30 people in view ≥ 45 fps.
- Sim tick ≤ 3.0 ms median at 110 people + social systems; no single tick over 12 ms.
- **`index.pck` ≤ 200 MB (soft), 300 MB (hard).** Changed by Paul, 29 September 2026: v5 does not
  have to go on GitHub, so the 100 MB GitHub file limit no longer applies. The hard limit is browser
  memory: the web build holds the whole pck in RAM. It is 78.7 MB now. Allocation: ART-NPC ≤ +50 MB,
  ART-HAB ≤ +25 MB, ART-B (dome) ≤ +30 MB, UI ≤ +5 MB, reserve ~10 MB. Quality first, but no waste:
  shared materials, mesh compression, no unused LOD/shadow meshes. Faces up to 1024 px per variant.
  Every art agent reports its size effect. Load time is shown by the loading screen.
- Save schema 6. Schema 5, 4, 3 and 2 saves load: old colonists get a deterministic appearance,
  skills from role and days worked, no relationships, rank "crew", and one commander chosen by
  seniority.

**Visual gate.** CRITIC (V3_DESIGN §9, pass ≥ 0.65 per subject, the mean must not drop). Pilots first (§13).

---

## 1. People — six adult body variants, children, uniforms, casual wear (ART-NPC; SIM data; RENDER draws)

Paul: *"stunningly modelled and animated, 3 male and 3 female variations, uniforms for their roles and
casual wear for when they are off work and socialise."*

- **Source (Paul, 29 September 2026): MPFB / MakeHuman.** The procedural pilot failed (people_closeup 0.59,
  people_outfits 0.61). People are built with the MPFB 2.0.17 Blender extension and CC0 MakeHuman assets
  (base mesh, skins, eyes, hair, clothes). CC-BY assets only with credit in `assets/models/people_credits.md`.
  Downloads stay outside the repo (`D:\Tools\mpfb\`). Exported models are CC0.
- **Six adult variants**, one skeleton (the v3 skeleton, extended with face bones if needed):
  `m1 m2 m3 f1 f2 f3`. Each differs in **build, height (1.62–1.92 m), face shape, skin tone, hair
  style and hair colour**. Hair colour and skin tone also vary per person through vertex-colour tint
  parameters, so 110 people do not look like 6 clones. Stylised-realistic, not cartoon: correct
  proportions, modelled faces (eyes with iris and highlight, brows, nose, lips, ears), fingers,
  cloth folds at elbows, knees and waist. They must hold up at **1.5 m from the camera** in the
  follow view (§3). That is the new close-up standard.
- **Children:** `c1` (boy) and `c2` (girl), age look 8–12, own proportions on the same skeleton
  (scaled bones), same outfit system (school uniform + casual).
- **Outfits** (separate skinned meshes on the shared skeleton, swapped at runtime; body parts hidden
  under clothing are removed per outfit to prevent poke-through):

  | outfit | who | look |
  |---|---|---|
  | `uniform_engineering` | technician, operator | coverall, tool belt, amber department stripe |
  | `uniform_science` | scientist | fitted jacket, lab-coat option, blue stripe |
  | `uniform_food` | grower, kitchen, venue staff | work shirt, apron, green stripe |
  | `uniform_medical` | medic | scrubs and tunic, white/red |
  | `uniform_security` | security officer (new role, §5) | armoured vest, black/red |
  | `uniform_command` | commander, captains | tailored jacket, rank insignia on the shoulder |
  | `casual_a` `casual_b` `casual_c` | off duty | jeans/tee/hoodie; dress/skirt/jacket; sport wear (per variant) |
  | `swimwear` | pool (§8) | modest one-piece, or trunks with a tee |
  | `prison` | prisoners (§6) | orange coverall |
  | `school` | children | school uniform |

  Rank insignia and department stripe are separate small meshes or vertex-colour masks, so RENDER can
  show rank and department on any uniform.
- **Rule:** on shift = uniform; off shift, at home, in leisure places or at social events = casual;
  outside = the v3 suit (the helmet visor shows the face variant when close).
- **Animation.** Keep the 24 v3 clips on all variants and add ≥ 30 new clips (smooth blends,
  in-place, v3 naming rule): `talk_idle`, `talk_gesture_a/b`, `listen_nod`, `laugh`, `argue`,
  `shout`, `sulk`, `cheer`, `wave`, `handshake`, `hug`, `kiss_brief` (a short kiss, faces meet, no
  more), `hold_hands_walk`, `flirt_lean`, `slap`, `punch`, `hit_react`, `fall_down`, `get_up`,
  `fight_idle`, `protest_fist`, `handcuffed_walk`, `escort_walk`, `sit_bench`, `sit_bar_stool`,
  `drink_bar`, `dance_a/b/c`, `swim`, `lounge_pool`, `jog`, `play_arcade`, `shop_browse`,
  `sit_class`, `teach`, `sleep_cell`; children: `child_play`, `child_run`. Paired clips (hug,
  handshake, kiss_brief, slap, punch/hit_react, escort/handcuffed) have an **offset spec** in
  `assets/models/npc_pairs.json` (distance, facing, sync time) so RENDER places the two partners
  correctly.
- **Robot dancers** (for the club, §8): a slim chrome humanoid robot, stylised and clearly a machine
  (visible joints, a light-bar face, no human anatomy), 3 dance loops, and one acrobatic pole-spin
  loop in a performance style — not sexual. Owner ART-NPC.
- Files: `assets/models/people_<variant>.glb` (body + all outfits of that variant as named child
  meshes `Outfit_<id>`); animation libraries as ART-NPC chooses; all of it listed in
  `assets/models/people_manifest.json` (outfit names, tint parameters, clip list, sizes).
  `npc_verify.py` extended: every variant × outfit × clip, no poke-through at the test poses, bone
  count, triangle budget (≤ 14 k triangles per body + outfit at LOD0, ≤ 3 k at LOD1).
- LOD: LOD0 inside 12 m of the camera, LOD1 beyond.

## 2. Identity and appearance data (SIM)

Each colonist, visitor and child gets, deterministically from the seed: `sex` (m/f), `variant`,
`age` (adults 21–64, children 6–12), `tint` {skin, hair}, `traits` (2–3 from a content list:
ambitious, lazy, romantic, jealous, hot-headed, calm, loyal, gossip, shy, charming, honest, greedy,
funny, pious, party-animal, workaholic), `attraction` (who this person can be attracted to: content
weights for opposite / same / both; deterministic per person), `home` (residence unit id), `partner`,
`family` (family id). The current outfit is derived state (`sim.people.outfit(a)`), so RENDER never
guesses. Names: content name lists per sex, seeded.

## 3. Follow view — over the shoulder (RENDER camera; UI HUD)

Paul: *"a first-person over-the-shoulder view of the NPCs … speech bubbles when the player is in
over-the-shoulder follow of an NPC to see the interactions."*

- **Enter:** select a person → `Follow` button or key **V** (F keeps the v3 overview follow). Also from
  the colonist list, the personnel file and any tabloid story ("Follow Dana").
- **Camera:** behind the right shoulder: 0.55 m right, 1.9 m back, eye height + 0.15 m; smooth spring
  follow (no jitter on turns); mouse drag orbits ±70° around the person; wheel zooms 1.2–4 m; Q/E
  swap the shoulder; the camera never passes through a wall (sphere cast against walls and props;
  pull in when blocked). Indoors: the roof and the wall segments between the camera and the person
  are hidden (reuse the cutaway rule). Multi-storey buildings (§7) hide the floors above the followed
  person's floor.
- **Speech bubbles** (only in the follow view, for people within 14 m and in line of sight; the
  followed person's bubble always shows): a glass bubble with a tail above the head, 1–2 short lines,
  fade in and out, never overlapping (stack upward), max 6 visible. Emote icons for non-verbal acts
  (heart, anger, zzz, music note, sweat drop, credit sign, question). Text from SIM (§4).
- **Follow HUD** (UI): a small top-left card — name, rank, role, mood face + satisfaction bar,
  current activity ("Off duty — at the Bar with Kai"), partner/crush icon, the last 3 lines said;
  buttons: Review (§6), Next person (Tab), Switch to the person they talk to (click a bubble),
  Exit (Esc). The rest of the HUD dims; time controls stay.
- The game keeps running; the follow view is a camera mode, not a pause.
- Performance: in the follow view, LOD0 people, full interiors and close lights only near the camera
  (≤ 40 m); everything else as normal.

## 4. Conversations, relationships, the social board (SIM; UI; RENDER bubbles)

Paul: *"have them converse about the state of things, their satisfaction … relationships … attracted
to other NPCs, even visitors, for drama … a social board log on interactions and scandals between
the NPCs, like a tabloid newspaper … a bit of an Easter egg."*

### 4.1 Encounters and conversations
- When two or more people are near each other with nothing urgent (meals, breaks, leisure places,
  parks, idle in corridors), SIM starts a **conversation** (content-tunable chance per second of
  proximity). A conversation has a **topic**, 2–6 exchanged lines (one line per 3–5 s), an outcome
  (relationship change, mood change, gossip spread) and animation hints (`talk_gesture`, `laugh`,
  `argue` …).
- **Topics come from state** (weights from state, deterministic): colony state (air, food, power,
  reactor warnings, hazards, deaths, a ship arriving, new buildings, research done), their own
  satisfaction (hungry, tired, overworked, bad housing, low rank, a punishment), work (department,
  captain, skills), gossip (relationships and scandals they know about), romance (flirting, dates),
  leisure (the dome, the pool, the arcade), small talk. A person whose need is critical **must** say
  so — the talk is a readable status channel.
- Lines come from `content/dialogue.json`: templates with slots (`{other}`, `{building}`,
  `{resource}`, `{captain}`, `{days}` …) and per-trait variants (a gossip says it differently from a
  shy person). **≥ 600 line templates** across ≥ 25 topics. Visitors and children have their own lines.
- API: `sim.social.talks_near(pos, radius)` → active talks with speaker, line text, emote, anim hint,
  start time; `sim.social.recent_lines(agent_id, n)`.

### 4.2 Relationships
- Sparse relationship graph: a pair gets an entry only after they interact. Values: `affinity`
  (−100…100), `attraction` (0…100, only where both people's attraction rules allow it and both are
  adults), `status`: stranger, acquaintance, friend, best friend, rival, enemy, crush (one-way),
  dating, partners, married, ex, affair.
- Drivers: shared work and leisure, compatible traits, conversations, gifts (from retail), help,
  rescue; negatives: arguments, rivalry for promotion, jealousy, punishments that one person caused,
  fights. Attraction drifts with proximity, traits and charm.
- **Romance chain:** crush → flirting → date (bar, park, pool, dome restaurant) → dating → partners →
  move in together (they request a shared unit, §7) → married (a small ceremony in the park or the
  dome, colony-wide morale bonus) — or break-up → ex (awkward, mood penalty when they meet).
- **Visitors:** tourists and traders (V3.1) join the graph while they stay. A colonist can fall for a
  visitor: a **fling** (short), a **visitor romance** (the colonist may ask to leave with the ship —
  the player decides: let them go, or refuse and take a morale hit), or an **affair** if the colonist
  already has a partner.
- **Drama:** affairs are discovered with a chance per day (higher with gossips around); discovery
  starts a scandal (§4.3), a break-up or a fight (hot-headed traits). Jealousy between rivals for the
  same person. Promotions (§5) create rivalries.
- **Families:** partners can request a child by adoption (through the medical bay) or immigration;
  **no births are simulated**. Immigrant shuttles can bring whole families (1–2 adults + 1–2
  children). Children live with their family, attend school (§5.3), play in parks, and **grow up**
  after `child_grow_days` (content, default 30 game days) into adults with skills from school.

### 4.3 The social board — "The Regolith Rag" (SIM writes stories; UI shows the paper)
- SIM keeps a **social log**: every notable social event (new couple, date, break-up, affair
  discovered, fight, arrest, promotion, demotion, punishment, protest, wedding, visitor romance,
  defection with a ship, riot, commander scandal, best-dressed, party at the club, arcade record,
  birthday) with actors, place, day and "heat" (how juicy).
- **Daily edition** at dawn: the top stories of the last day by heat become a tabloid issue:
  masthead **THE REGOLITH RAG**, issue number, date, a **lead story** with a huge headline and a
  **photo** (§4.4), 3–6 smaller stories, a gossip column, "Couple Watch", "Feud Watch", a commander
  approval poll (from satisfaction), and small ads (from retail stock and ship arrivals). Headlines in
  tabloid voice from `content/tabloid.json` (≥ 200 headline templates, puns allowed, never explicit).
  Stories link to people: click → select or follow them.
- The Rag is also a **helper**: it surfaces unrest, bad attitudes and scandals that affect work; a
  "Serious news" strip at the bottom lists the real problems (from alerts).
- New-issue toast; the Rag window keeps the last 30 issues (back issues).

### 4.4 Tabloid photos (RENDER)
RENDER provides `photo(agent_ids, place_hint, pose_hint) -> ImageTexture`: an off-screen SubViewport
render of the named people in the right outfits and a matching pose (argue, kiss_brief, hug, punch,
cheer, handcuffed_walk …) with a simple backdrop of the place (bar, park, corridor, pool) or the real
3D spot if cheap. 512×384, grainy "paparazzi" post-process. Cached per story. The same function
gives portraits for the personnel file.

### 4.5 Easter eggs (hidden; the player finds them)
1. **PRISM SHIFT arcade:** the gaming lounge (§8) has an arcade cabinet whose screen shows an attract
   loop of *Prism Shift* (Paul's neon tunnel racer: a neon tunnel with a prism ship; ART-B models the
   cabinet, RENDER animates the screen with a shader). Colonists who play it talk about high scores;
   the Rag runs "ARCADE KING" stories; about one person in a thousand is a "Prism Shift champion" with
   a unique line.
2. **The dev in the dome:** one very rare tourist named **"P. Barby"** visits in a unique jacket, says
   unique lines ("I made this place, you know."), and the Rag headlines the visit. Deterministic: at
   most once per game, after the super dome opens.
3. **Dance code:** in the follow view, the Konami code (↑↑↓↓←→←→BA) makes the followed person dance
   (`dance_c`) with a unique line; nearby friends join in. Award "Dance Floor Director".
Easter eggs are not in the codex until found; finding one gives an award.

## 5. Hierarchy, skills, education (SIM; UI)

Paul: *"hierarchy, base commanders, industry, science, food, maintenance captains and first hands, and
levels of person skills, and education modules to train NPCs."*

### 5.1 Ranks
| rank | count | effect |
|---|---|---|
| **Base Commander** | 1 per base | leadership bonus to the whole base (work speed, morale, unrest damping) from their `leadership` skill; takes the blame for problems (approval poll) |
| **Captain** — Industry, Science, Food, Maintenance, Security (new) | 1 per department per base | bonus to the department's work speed and quality; sets the department mood |
| **First Hand** | 1–2 per department per base | deputy: half a captain's bonus; leads when the captain is off shift |
| **Specialist** / **Crew** / **Trainee** | the rest | by skill level |

- Departments: Industry (operator: fabrication, mining, refining), Science (scientist, medic),
  Food (grower, kitchen, venue staff), Maintenance (technician: build, repair), Security (security
  officers, §6). A Medical captain may be appointed when the colony has ≥ 4 medics.
- The player **appoints** ranks (org chart, §10); SIM proposes the best candidate. Rank gives
  **entitlements**: commander and captains expect executive housing (§7) and extra leisure. A rank
  without its entitlement lowers that person's satisfaction; entitlements that others see as unfair
  raise unrest (a trade-off).
- Promotions and demotions create rivalries, happiness and drama (Rag stories).

### 5.2 Skills
- Skills 0–100 shown as levels 1–5 (Novice, Trained, Skilled, Expert, Master): `engineering`,
  `mining`, `fabrication`, `farming`, `cooking`, `medicine`, `science`, `piloting`, `security`,
  `leadership`, `social`. Each role's work uses one or two skills; skill multiplies work speed
  (L1 0.7× … L5 1.4×, content) and reduces wear and accidents. Skills grow by doing the work
  (diminishing returns) and by training; a small decay when unused for long.
- Immigrants arrive with skills from their background (content); the shuttle screen shows them.

### 5.3 Education — the Academy (§7)
- **Courses:** the player (or the captain, automatically) enrols people in a course: one skill, one
  level step, a duration in game hours, a teacher (any colonist with skill ≥ 60 in that skill) or an
  **instructor console** that teaches up to level 3 without a teacher. Students attend during their
  shift (their work stops — a trade-off). Children attend school daily.
- Sizes S/M/L: 4 / 8 / 14 seats. Levels upgrade seats and speed.

## 6. Reviews, attitude, discipline, unrest, security and jail (SIM; UI; RENDER shows)

Paul: *"allow players to review NPCs and have NPCs get bad attitudes and you have to punish them like
food rations, and then if you push them too much they rebel and beat each other up, so also have a
jail module and security."*

### 6.1 Satisfaction and attitude
- **Satisfaction** 0–100 per person. The v3 morale value stays as its needs component, so balance and
  tests keep working. Components (each shown with its reason): needs (food, drink, sleep, air), food
  quality, housing (quality vs entitlement), comfort and leisure, social (friends, partner,
  loneliness), work (fit with skills, overwork, rank), fairness (entitlements, punishments seen),
  safety (hazards, radiation, deaths, reactor state), freedom.
- **Attitude** −100…100: how a person behaves towards work and rules. Drifts with satisfaction, traits
  (lazy, hot-headed, loyal), their captain, friends' attitudes and discipline. Bad attitude (≤ −30) →
  slacking (slower work, long breaks), backtalk (bubbles), skipped shifts, petty theft (luxury items),
  arguments. Very bad (≤ −70) → starts protests and fights.

### 6.2 Reviews (UI shows; SIM supplies)
The **Personnel file** of each person: portrait (RENDER `photo`), rank, role, skills, satisfaction with
reasons, attitude with trend and reasons, performance (work done vs expected over 3 days, absences,
incidents), relationships (partner, friends, enemies), history (promotions, punishments, Rag
appearances). The player can **write a review**: *Excellent / Good / Needs improvement / Poor* — each
has an effect by traits (an ambitious person works harder after a good review; a hot-headed one reacts
badly to "Poor").

### 6.3 Discipline actions (each shows its expected effect before the player confirms)
| action | effect on the person | effect on others |
|---|---|---|
| Verbal warning | attitude +small (loyal, calm) or −small (hot-headed) | none |
| **Ration cut** (50 % or 75 % meals, 1–3 days) | attitude up short-term (fear), satisfaction down, hunger and health risk | fairness −small for friends |
| Extra shift | work output up, fatigue, satisfaction down | none |
| Demotion | rank down, satisfaction down, a rival is happy | drama |
| Confine to quarters (1–2 days) | no work, no leisure, attitude up or down by traits | fairness −small |
| **Jail** (1–5 days) | no work; prison rations; attitude may reset or harden | fairness down if seen as unfair |
| Praise / bonus leisure / gift (positive tools) | satisfaction and attitude up | small envy |

### 6.4 Unrest and rebellion
- **Unrest** 0–100 per base = weighted mean of low satisfaction and bad attitude, plus recent
  punishments (each adds; unfair ones add more), unmet entitlements, deaths and food cuts, minus
  security presence, commander leadership and leisure quality.
- Stages (deterministic thresholds, content): **Grumbling** (≥ 25: bubbles, Rag stories) →
  **Slowdown** (≥ 40: work speed −15 %) → **Protest** (≥ 55: a group gathers in a hall or the dome
  plaza with `protest_fist`, shouting a demand from state, e.g. "Full rations now!") → **Strike**
  (≥ 70: a department stops work until the demand is met or unrest falls) → **Riot** (≥ 85: fights
  break out; rioters damage furniture and structures (repairable), break into storage and injure each
  other; security arrests; injured people can die if there is no medical care).
- **Fights:** two people with enemy status, or hot-headed traits in a bad mood, can fight
  (`fight_idle` / `punch` / `hit_react` / `fall_down`): injuries (health −), bystanders join or flee,
  security comes to separate them and arrests.
- **Player responses:** meet the demand (the protest names one), a leisure day, a party at the bar
  (costs stock), amnesty (release prisoners: unrest −, security morale −), replace the captain,
  arrest the ringleaders (unrest down only if fairness says it was fair), lock down (the doors of a
  zone close: stops a riot from spreading, but raises unrest).

### 6.5 Security and jail
- New role **Security officer** (from immigrants, or retrained at the academy: skill `security`).
  Patrols public places; responds to fights, theft and riots; escorts arrested people to jail
  (`escort_walk` + `handcuffed_walk`). Target ratio 1 per 12 people (content).
- Buildings (§7): `security_office` (S/M: officers' post, lockers, monitors; faster response) and
  `jail` (S/M/L: 2 / 4 / 8 cells). Prisoners sleep and eat in the cell (`sleep_cell`) and wear
  `prison`. Without a jail, arrested people are confined to quarters instead (weaker).

## 7. New structures (SIM content and rules; ART-HAB / ART-B models; RENDER draws; UI palette)

Sizes stay S/M/L/XL for normal rooms. **Two new size labels** for single-size giant structures:
**XXL** (the apartment block) and **XXXXL** (the super dome). Paul did not name an XXXL; there is none.
In code these are fixed-size definitions with `"size_label": "XXL"` / `"XXXXL"` and their own radius;
the S–XL index system is not extended.

| id | name | size(s) | shape and content | unlock |
|---|---|---|---|---|
| `residence_tube` | Residence Tube | M, L, XL | **half-tube**: a half-cylinder vault lying on the ground, ribs, end walls with windows, a porch door at each end and side links. Variant chosen at placement: **Family** (2-bedroom units with a family table, children's bunks) or **Executive** (large units: bedroom, office, lounge, private bath). Units: Family M/L/XL 2/3/4; Executive M/L/XL 1/2/3 | Family: start; Executive: research `civic_1` |
| `apartment_block` | Apartment Block | **XXL** only | 3 storeys, ~20 m radius footprint: ground and first floor 5 units each (**10 units**, 1–2 bedrooms); top floor **2 executive penthouses with 3 bedrooms each** and a roof terrace under glass. Internal lift and stair core. | research `civic_2` |
| `retail` | Retail Module | S, M, L | shop fronts, shelves, a counter; sells luxury goods (clothes, snacks, gadgets, gifts) that raise satisfaction and allow gifts; visitors spend credits here | stage 1 |
| `park` | Park and Gardens | M, L, XL | glass dome over grass, trees, paths, benches, flower beds, a pond at L+; leisure, dates, jogging, weddings; small O₂ bonus; needs water | research `civic_1` |
| `academy` | Academy | S, M, L | classroom seats, teacher board, instructor consoles; school for children | stage 1 |
| `security_office` | Security Office | S, M | desk, monitors, lockers, response post | research `civic_1` |
| `jail` | Jail | S, M, L | cells with bars, bunks, a guard desk, a yard at L | research `civic_1` |
| `super_dome` | Super Dome | **XXXXL** only | the end game, §8 | research `arcology` (tier 3, needs graphene + metamaterials) |

- Housing: every person gets a home: dorm beds in habitats (v3 "crew quarters") or a unit. Units have
  a quality (dorm < family unit < executive unit < penthouse). Partners share a unit; families need a
  family unit. Commander and captains expect executive units or penthouses.
- **Multi-storey rule (SIM, RENDER, ART):** a building may have `floors` (apartment block 3, super dome
  5). Each floor has anchors with a `floor` index and height. People move between floors only through
  the building's lift/stair core (SIM treats the core as an internal link with a time cost; nav stays
  2D per floor). RENDER draws people at their floor height and, when the camera is near or in the
  follow view, hides the floors above the viewed floor. UI gives a floor selector for the overview
  camera (PgUp/PgDn, or a small slider when the building is selected).
- Door slots: residence tube M/L/XL 4/5/6; apartment block 6; super dome 12 (large gates).

## 8. The Super Dome — XXXXL end game (ART-B models; SIM rules; RENDER draws)

Paul: *"a super XXXXL end-game super dome that has an entire city block with pool, bars, gaming lounge,
adults club with robot pole dancers; it is 5 storeys high with an open centre; the outer walls' upper
levels are accommodation, lower levels shops and business; have all the modern services and shops."*

- **Size:** radius 48 m; a glass geodesic dome over a 5-storey ring building; total height ~38 m.
  Ring depth 14 m; **open centre** (atrium) 40 m across, open to the dome sky.
- **Levels:** L1 (ground) and L2 = shops and businesses facing the atrium along galleries: grocery,
  clothing, electronics, pharmacy/clinic, café, restaurant, barber/beauty, credit office, comms/post
  office, fitness gym, a hotel lobby (tourists stay in the dome), a **bar**, the **gaming lounge**
  (arcade cabinets including the Prism Shift egg, VR pods, pool table), and the **Club** (the adults'
  club: a stage with a light show, podiums with poles, **robot dancers** (§1), DJ booth, lounge
  booths; adults only, a bouncer at the door). L3–L5 = accommodation: 30 units (24 standard/family,
  6 executive) and tourist hotel rooms.
- **Atrium (ground):** a **pool** with loungers and a small water slide, a park strip with trees, a
  plaza with a fountain and café seats, and a stage for events (weddings, protests, concerts). Glass
  lifts (animated) and ramps connect the galleries.
- **Services:** every shop is a real venue: it needs stock (luxury goods, food, drinks — from industry
  or traders), staff (colonists with a job there: shopkeeper, bartender, DJ, lifeguard — new jobs
  under the Food captain), and gives satisfaction and **credits** from tourists (V3.1 tourism). A
  finished, staffed dome turns tourism into the late-game income.
- **Construction:** staged (foundation ring → structure per level → dome glass → fit-out per venue);
  each stage is visible. Cost huge (steel, glass, graphene, metamaterials, electronics). One per base.
  The dome needs power, water and air like any room (large amounts).
- **Look (critic):** from the overview it reads as a glittering city under glass (lit windows, signs,
  the pool glow at night); inside (follow view and floor cutaway) it feels like a mall and a resort:
  shop signs, lights, plants, people in casual wear everywhere.

## 9. Leisure economy (SIM)
New items (basic/mid tier): `luxury_goods`, `clothing`, `snacks`, `drinks`, `gadgets`, `gifts`, with
recipes (fabricator, kitchen, a new `distillery` machine for drinks is allowed) and trader stock.
Venues consume them. Colonists do not use money; tourists do. Leisure satisfaction depends on venue
quality and stock.

## 10. The interface (UI)
- **Follow HUD** (§3). Speech bubbles are drawn by RENDER as 3D-attached 2D; UI supplies the glass
  bubble style as a shared theme resource.
- **The Regolith Rag** window: a real tabloid layout (newsprint texture, bold condensed headlines, red
  masthead, a photo with a caption, columns), held in a glass-and-metal frame. Back-issues list.
  Click a name → select / follow.
- **Personnel file** (§6.2) with Review and Discipline buttons; each discipline action shows the
  predicted effect and asks to confirm.
- **Org chart** (Crew window, a tab per base): commander at the top, department columns with captain,
  first hands, crew; drag a person onto a slot; SIM's suggestion highlighted; entitlements shown.
- **Social tab** per person: relationship web (small graph), partner, friends, enemies, crush (only
  once "known": the player learns crushes from the Rag or from bubbles).
- **Unrest** meter per base in the top bar; the tooltip lists the causes; protest, strike and riot
  banners with the demand and the response buttons.
- **Academy** window: courses, seats, teachers, students, progress.
- **Housing** tab: units, who lives where, quality vs entitlement; reassign by drag.
- **Floor selector** for multi-storey buildings.
- Build palette: the new structures with XXL / XXXXL labels; every lock explained (V4 rule).
- Codex: people, ranks, skills, discipline, unrest, every new building; Easter eggs hidden until found.
- Version `5.0.0` in `project.godot`; the menu and the loader show it (the loader through
  `node tools/make_shell.mjs`, orchestrator).

## 11. Content, saves, tests (SIM)
- New content: `dialogue.json`, `tabloid.json`, `names.json` (if not present), `traits.json`,
  `social.json` (all social rates), `skills.json`, `ranks.json`, `discipline.json`, `unrest.json`;
  new buildings, items, recipes and research (`civic_1`, `civic_2`, `education`, `security`,
  `arcology`, plus 8–12 civic techs).
- Save schema 6 + migrations (§0).
- Tests (headless, deterministic): relationship formation over 10 days is reproducible; a starved and
  punished colony reaches Protest and Strike, and a fair response reduces unrest; a fight ends with an
  arrest when security exists; the jail holds and releases; the academy raises a skill; children grow
  up; multi-storey paths in the apartment block and the dome (every anchor reachable); the dome build
  stages complete; tourism income appears; the Rag produces an issue with ≥ 3 stories on day 3 of the
  showcase; the follow-view data APIs return lines; a v4 save migrates and runs 1 day. The full suite
  stays green.
- **Showcase** `content/saves/showcase_v5.fhsave`: 2 bases, ~110 people incl. 6 children, a finished
  and staffed super dome with tourists, an apartment block, residence tubes, a park, a jail with one
  prisoner, a protest brewing (unrest ~50), two couples, one affair about to break, and 5 Rag issues.

## 12. CRITIC subjects for 5.0
| subject | evidence |
|---|---|
| `people_closeup` | 6 variants + 2 children, front and ¾ at 1.5 m, in uniform and casual (pilot: m1 + f1) |
| `people_outfits` | every outfit on 2 variants, department stripes, rank insignia |
| `people_animation` | contact sheets of the new clips + paired clips in game (hug, argue, punch) |
| `follow_view` | in-game follow view: indoors, outdoors, a dome gallery; bubbles readable |
| `regolith_rag` | the tabloid window with photos |
| `social_ui` | personnel file, org chart, unrest banner |
| `residences` | residence tube family and executive, apartment block (outside and floor cutaway) |
| `civic_modules` | retail, park, academy, security office, jail |
| `super_dome` | overview day and night; atrium with pool; a shop gallery; the club with robot dancers; the gaming lounge with the arcade |
Plus every earlier subject must not drop.

## 13. Ownership, order of work, pilots

| path | owner |
|---|---|
| `sim/**` (suggested new files: `sim/people.gd`, `social.gd`, `ranks.gd`, `discipline.gd`, `unrest.gd`, `education.gd`, `housing.gd`, `floors.gd`), `content/**`, `tests/**` | **SIM** |
| `tools/blender/npc_*.py`, new `people_*.py`, `robot_*.py`; `assets/models/astronaut_*`, `people_*`, `robot_*`, `npc_pairs.json`, `people_manifest.json`; `art/npc/**`, `art/people/**` | **ART-NPC** |
| residence tube, apartment block, retail, park, academy, security office, jail (models, interiors, anchors with floors); `art/interiors/**` | **ART-HAB** |
| super dome (all levels, venues, pool, lifts), arcade cabinet, club stage and poles, dome props; `tools/blender/dome_*.py`, `assets/models/dome_*`, `art/dome/**` | **ART-B** |
| follow camera, bubbles in 3D, people and outfit drawing, paired-clip placement, floors and floor cutaway, `photo()`, dome/club/arcade effects; `presentation/**` except `main.gd`/`boot.gd`; `shaders/**`; `tools/render_*.gd` | **RENDER** |
| follow HUD, Rag window, personnel file, org chart, social/housing/academy windows, unrest UI, floor selector, palette, codex, Konami input, version; `ui/**`, `presentation/main.gd`, `boot.gd`, `project.godot`, `templates/web_shell.src.html` | **UI** |
| `docs/critic/**`, `art/critic/**` | **CRITIC** |
| `docs/V5_DESIGN.md`, `docs/V5_REQUEST.md`, `export_presets.cfg`, `tools/godot.mjs`, `shoot.mjs`, `serve.mjs`, `audio_probe.mjs`, `make_shell.mjs`, `build/web/` | **orchestrator** |

Requests: `docs/requests/<FROM>-to-<TO>.md` (append, dated). Progress: a dated "v5" section in
`docs/progress/<AGENT>.md`: what landed, what is next, what you did not test. Read the requests
addressed to you at every milestone. **SIM's first deliverable is a written API** (v5 section) in
`docs/requests/SIM-to-UI.md` and `SIM-to-RENDER.md`, with stub functions that return plausible data,
so UI and RENDER start at once.

**Order:**
1. **SIM:** people identity + outfit state + API stubs → floors model + new building defs (so ART and
   RENDER can place them) → conversations + dialogue content → relationships + romance + visitors →
   ranks + skills + academy → satisfaction/attitude/discipline/unrest/fights/security/jail → housing
   + families + children → social log + Rag issues → dome venues + leisure economy + tourism → eggs →
   saves, migrations, showcase, tests, perf.
2. **ART-NPC:** m1 + f1 in `uniform_engineering` + `casual_a`, face close-up, 6 new clips → **critic
   pilot** → remaining variants, children, all outfits, all clips, pairs spec, robot dancer → verify.
3. **ART-HAB:** residence tube (family + executive, L) → **critic pilot** → apartment block with
   floors → retail, park, academy, security office, jail (all sizes).
4. **ART-B:** super dome shell + one gallery level + atrium pool → **critic pilot** → all levels,
   venues, club, gaming lounge + Prism Shift cabinet, build stages.
5. **RENDER:** follow camera + bubbles with the v3 models (pilot, then the new people as they land) →
   outfits and variants → paired clips → floors + floor cutaway → `photo()` → dome/club/arcade effects
   → perf.
6. **UI:** Rag window pilot (with SIM stub data) → **critic pilot** → follow HUD, personnel file, org
   chart, unrest, academy, housing, floors, palette, codex, eggs, version.
7. **CRITIC:** pilots, then full rounds.
8. **Orchestrator:** integrate, build `build/web_v5preview`, tests, audio probe, pck size, critic
   final, report. A playable preview at every pause.

## 14. Request map (docs/V5_REQUEST.md → sections)
1–4 → §1 · 5–6 → §3 · 7 → §4.1 · 8 → §4.5 · 9 → §4.2 · 10 → §4.3–4.4 · 11 → design aim · 12–13 → §7 ·
14–15 → §7, §9 · 16 → §6.5, §7 · 17 → §5.3, §7 · 18 → §5.1 · 19 → §5.2 · 20 → §6.2 · 21 → §6.1, §6.3 ·
22 → §6.4 · 23–26 → §8.

## 15. Scope change, 2026-10-01 (Paul): realism in close view, viewer experience, styled interiors

Paul's words (summary): animations and rigging must look natural, because they break the realism of the
over-the-shoulder view; the over-the-shoulder camera needs more freedom to look around; "in the future we
will make this a viewer-centric experience for the players who like to watch the action unfold and just take
in the amazing 3D environment"; habitat interiors are "just blocks and lanes" and must be highly detailed,
"have pop culture references and some grounding in 2026 woven in to the settings, including being
ridiculous to highlight the crazy AI boom now". He asked to record this styling preference as a scope change.

Rules:
1. **Close-view realism is a quality gate.** Every clip and every seated/working pose is checked at the
   follow-camera distance. Faults that fail: floating or sinking feet, broken joints, body through furniture,
   snaps. (ART-NPC, RENDER; requests of 2026-10-01.)
2. **Viewer experience (future version).** Camera code must allow a later "watch" mode: free orbit, cinematic
   automatic shots of people and events, no HUD. Not in 5.0 unless Paul says so; 5.0 gets the freer
   over-the-shoulder camera.
3. **Interior style.** High-detail interiors, set in a future colony that still carries 2026 culture:
   - pop-culture references as parody or homage, with ORIGINAL names, text and art (no real logos, brand
     names, characters, lyrics or copied artwork; the title screen states all content is original);
   - 2026 grounding: everyday objects, habits and in-jokes of 2026 carried to the colony;
   - AI-boom satire, deliberately ridiculous: e.g. a kettle with a chatbot, motivational posters by an AI,
     "AI-powered" labels on everything, a GPU shrine, a toaster that asks for a subscription, a meeting
     room booked by agents arguing with each other, a "prompt engineer" desk plate. Keep it playful, never
     mean about real people or companies.
   - The Regolith Rag, dialogue lines and help text may carry the same tone.
4. Budgets stay: triangles per room as §7, the pck soft budget 200 MB; use a shared prop kit and texture
   atlases.
5. **Roofs (Paul, 2026-10-01).** In the over-the-shoulder view every roof stays on, for an enclosed feel
   (the camera stays inside under the ceiling). A new player toggle "all roofs off" cuts away every roof and
   upper wall in the whole colony in the normal view (Paul and a friend asked for it). RENDER draws it; UI
   adds the button, key and setting.
