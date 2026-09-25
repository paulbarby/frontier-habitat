# What is implemented, and what is not

Measured against `planetbase-inspired-game-spec.md` version 1.0. Every "yes" below is
covered by a headless test unless the row says otherwise.

## Delivery phases (spec 15)

| Phase | State | Evidence |
|---|---|---|
| 1. Simulation foundation | Done | `phase1_replay_10_days_save_load`: a ten-day game, saved mid-transport on day 5, reloaded and run on, ends with the same SHA-256 state digest as the uninterrupted run. |
| 2. Spatial prototype | Done | Terrain, placement with reasons, three network graphs, walking and airlocks. `unit_placement_reasons`, `a02_disconnected_district`. |
| 3. Survival slice | Done | `a12_opening_viability_all_seeds`: the documented layout reaches the end of day 3 with all eight colonists alive on all five tutorial seeds, with no scripted grants. |
| 4. Sustainable economy | Done | `a13_twenty_colonists_ten_days`: 20 colonists, 13 days, no deaths, own metal, no imports. |
| 5. Complete loop | Partial | Settlers arrive as a controlled event (spec MVP). Trade, robots and disasters are **not built**. |
| 6. Product pass | Mostly done (v2) | Original models, textures, sky, effects, full interface, charts, awards, audio. Not done: rebindable keys. |

## Acceptance tests (spec 16)

| # | Test | Result |
|---|---|---|
| 1 | Resource conservation | pass — 1,078 checks over 900 s of play with cancels, a killed carrier and a cancelled batch; the ledger balances at every sampled second |
| 2 | Disconnected district | pass |
| 3 | Night transition, priority shedding | pass |
| 4 | Transport matters | pass |
| 5 | Reservations | pass (inside test 1) |
| 6 | Emergency AI | pass — turns back with 16 s of air left |
| 7 | Airlock congestion | pass — ten people, longest queue 7, all got in, warning raised |
| 8 | Crop failure | pass |
| 9 | Save continuity | pass — cargo delivered once, batch completed once |
| 10 | Demolition | pass |
| 11 | Alert causality | pass — one root incident, the rest hang under it |
| 12 | Opening viability | pass — all five tutorial seeds |
| 13 | Sustainable colony | pass |
| 14 | Loss and recovery | pass |
| 15 | Performance | measured, not certified. 0.75 ms per simulation tick with 16 colonists and 54 structures on an Intel i7-14700K: 1,335 ticks/s against the 10 ticks/s that real time needs, so 4x never skips a logical tick. **Frame rate at 1080p with 200 colonists and 300 structures has not been measured**, and no reference GPU was agreed. |

Two extra tests cover the behaviour reported during play testing:

- `u01_far_site_reports_suit_range` — a plan too far from an airlock shows a reason.
- `u02_building_still_works_after_day_five` — far plans placed on day 6 are built, and
  anything that stops shows a reason.

## Implemented

- Fixed 10 Hz simulation on an accumulator, pause and 1x/2x/4x, deterministic entity order.
- Seeded terrain with start-area validation, mineral deposits, rocks, slope limits.
- Placement on a hidden 1 m grid, 15° rotation, a named refusal for each rule.
- Three separate graphs: electricity+water, atmosphere, walking. Revision numbers invalidate
  stale routes. A disconnected district keeps exactly the stock physically on its side.
- Power allocation by priority class with strict shedding order, battery charge and
  discharge limits, 95% charging efficiency, minimum-off timers.
- Water tiers: drinking before oxygen plants before crops and industry, with reserves.
- Abstract oxygen per room group, suit air, airlock queues and cycles, breach drain.
- Real inventories everywhere with atomic reservations and a conservation ledger that can
  prove nothing was duplicated or lost.
- Blueprints: reserve, deliver, build, commission. Cancel and demolition with warnings,
  50% salvage and recoverable ground piles. Nothing is ever deleted silently.
- Colonist AI: needs, survival first, suit-range refusal, task scoring with waiting time,
  specialist roles, morale and its effect on work speed.
- Machines with in-process batches that survive save and load, crops with interruption
  timers, wear after day five, repair with spare parts.
- Alerts with causes and countdowns; overlays for power, water, air and walking.
- Save/load: a versioned, verified, atomic file; three rotating autosaves; export and import
  in the browser; imported files are validated before anything is replaced.

## Version 2 (simulation, `docs/AAA_DESIGN.md` sections 2 to 10)

Every row is covered by a headless test. Save schema 2; a version-1 save is migrated on
load (`v2_migration_v1_save` loads `content/saves/showcase_day9.fhsave` and runs it 2 days:
ledger `{}`, no deaths, no false starving alert).

| Area | State | Test |
|---|---|---|
| Sizes S/M/L/XL, levels 1 to 5, upgrades with material delivery | Done | `v2_size_effective_defs`, `v2_level_multipliers`, `v2_upgrade_flow_conserves_ledger` |
| Items, crops (8), dishes (12), nutrition (4 nutrients), spoilage (cold storage exempt) | Done | `v2_crop_yields_per_type`, `v2_kitchen_chooses_valid_dish`, `v2_nutrition_decay_and_eat`, `v2_spoilage_exact_and_cold_exempt` |
| New buildings, multi-recipe machines, scientist role, party 2/2/2/1/1 | Done | `v2_content_integrity`, `a12_opening_viability_all_seeds` |
| Research (29 techs, special projects that need items) | Done | `v2_research_unlock_and_special_items` |
| Goals (5 chapters, 23 goals) and awards (32) | Done | `v2_goals_sustain_timer_and_pod`, `v2_awards_once_only` |
| The Meridian: placement, 5 stages, maintenance, supply runs | Done | `v2_meridian_placement_all_seeds`, `v2_meridian_stages_and_runs` |
| Chart series and daily rows | Done | `v2_charts_series_and_daily` |
| Planets (dry, cold, airless), difficulty, immigration policy | Done in the simulation | `v2_meridian_placement_all_seeds` (all planets) |
| Dust storm (stretch) | Done, on by default | `v2_dust_storm_timing_effects_and_save` |
| Reference campaign to the Meridian | Done for seed 1001 | `long_campaign_chapters_seed_1001`: chapter 3 done and hull patched day 21.8, no deaths |
| Showcase saves early / mid / late | Done | `tests/make_showcase_saves.gd` writes them; each audit `{}` |
| Tick under about 1 ms with 60 colonists and 150 structures | **Not met** | `long_perf_60_colonists_150_structures`: 1.35 to 1.63 ms on an i7-14700K |

## Version 3 (`docs/V3_DESIGN.md`, 24–25 September 2026)

| Area | What is built | Evidence |
|---|---|---|
| Astronauts | `astronaut_suit.glb` (6,839 tris) and `astronaut_indoor.glb` (5,964 tris, 4 heads), one skinned mesh each on a shared 24-bone skeleton, 24 clips at 30 fps, no root motion | `tools/blender/npc_verify.py` 236 pass / 0 fail; `tools/npc_check.gd` 140 tests / 0 fail (`art/npc/`) |
| Transitions | Pose states stand, sit, lie, kneel with enter/exit clips; quaternion cross-fade max(0.25 s, angle ÷ 300°/s) ≤ 0.6 s; phase-synchronised walk ↔ run; speed-matched playback (foot slide ≤ 1 cm) | `art/npc/godot_check.json` |
| Furniture use | `agent.use` {kind, b, i, pose, act}; beds, seats, work stations, stand points, exterior service points; one body per anchor, 0.45 m spacing, overflow queues in corridors | test `long_v3_use_slots_unique` (72,000 ticks) |
| Interiors | 94 room files (every room type, S–XL): family layouts, anchors per `furniture` content, ≤ 8 interior surfaces; `art/interiors/` has 174 renders | `tools/blender/rooms_build.py` 94 / 0 flags |
| Doorways | Wall as 32 segments; `doorway.glb` with sliding doors at each corridor; junction kit (posts, sills); tall items near a door hidden | critic round 8: 0.79 |
| Interior light | Real lights for the rooms nearest the camera, lamp pools, family accent lights with floor spill; night floor 58–113% of day | critic round 8: 0.75 |
| Map | 810 m (10× the v2 area), 125 m start plateau, exotic fields ≥ 220 m out, hazard zone fields; 86–88% buildable; chunked LOD terrain; v2 saves keep 256 m | tests `v3_map_810_*`, `v3_buildable_area_all_seeds` |
| Hazards | Meteor, meteor shower, wind storm, dust storm, quake, solar flare, dust devil; wear-based breakdowns with faults; hull breaches; meteor turret; shelter and maintain commands; deterministic 2-day queue with detection lead | tests `v3_hazard_*`, `long_v3_hazards_determinism_and_ledger` |
| Research | 45 techs; basic / applied / exotic research packs; Research Assembler; ×2 lab boost with packs; lab focus; data network; supply-run cargo choice; fragment surveys | tests `v3_research_packs_*`, `v3_lab_focus_and_supply_cargo` |
| Alerts | Hysteresis (raise after 20/5/0 s, clear after 30 s), one `output_blocked` alert, toast gate (one toast per key, 180 s quiet time, notices never toast) | test `v3_alert_output_blocked_300s`; `tools/ui/test_alert_gate.gd` 17/17 |
| Interface | Hazard panel with countdowns and banner, Shelter button, maintenance tab, research pack tabs, lab focus, cargo choice, hazard setting, camera-shake toggle, 810 m minimap | `docs/shots/ui3_*.png` |

**Critic gate** (`docs/critic/round_1.md` … `round_8.md`): 19 subjects, 3 scores each
(consistency, appeal, style), pass ≥ 0.65. Two subjects failed and were redone:
`interior_links` 0.647 → 0.71 and `npc_interaction` 0.63 → 0.71. Final: all 19 pass, mean 0.75,
range 0.70 (hazard props, hazard visuals) to 0.82 (suit). The last RENDER polish (round-8
fixes) was not re-rated.

**Measured** (i7-14700K, RTX 3060, headless Chrome with GPU, 1600 × 900):
tick 1.78 ms median at 70 colonists and 150 structures (budget 2.0 ms); late 810 m colony
(66 colonists) 56–71 fps mean, minimum 48–56 fps in the HUD-on overview, draw calls ≤ 1,342;
world generation 207 ms; web pck 62.3 MB (v2: 32.4 MB). Tests: 60 / 60.

## Version 3.1 (`docs/V3_1_DESIGN.md`, 25–26 September 2026)

| Area | What is built | Evidence |
|---|---|---|
| Sound | v3.0 web build was silent (Godot 4.4 web "sample" playback). Now Stream playback, static bus layout, output latency 150 ms | `node tools/audio_probe.mjs build/web`: peak −23.7 dBFS (new colony), −10.6 dBFS (`showcase_v31`); v3.0 build: −inf |
| Music | 6 Eleven Music tracks (title, day ×2, night, tension, arrival), 11.4 MB; director with 4 s crossfades, tension hold 30 s | `tools/ui/test_music.gd` 13/13 |
| World sounds | 13 new SFX; positional fall-off from the camera focus, silent beyond 120 m | `tools/ui/test_world_audio.gd` 12/12 |
| Doors | Solid full-height leaves in pockets inside the frame (nothing hidden), status light green/amber/red, capped cut tops, 10 radius variants + flat-roof variant | critic round 14: 0.79 |
| Decals at doorways | 8,898 decal pieces split per wall segment; hidden within 0.4 m of an opening; merged per room | 0 decals in 176 doorways; critic 0.80 |
| Paths | Room → doorway → corridor → doorway → room; string-pulled around furniture (0.30 m), rounded corners, speed and turn limits, no teleports; sim indoor walks stay in rooms and corridors | `tools/render_path_check.gd` (≈500k samples): walls 0 (was 198), outside intrusions 0 (was 176), furniture 0.128 % (was 4.67 %), slides 0 (was 9,205), visible jumps 0 (was 1,643); test `v31_indoor_walks_stay_indoors` |
| Airlocks | Suit room → inner door → pressure chamber → outer door → porch; sizes M (3.4 m, 2 riders) and L (4.0 m, 4 riders, research `eng_1`), old 2.8 m kept; phases enter/seal/pump/open/exit; beacon and pressure lights; suit swap only at suit anchors (`suit_swap` clip) | `tools/render_airlock_check.gd`: 159 cycles, 0 in every category; critic 0.78 |
| Door clearance | New corridor links refused where a door would open onto equipment; free sides shown as green/red arcs; every room ≥ 120° (S) / ≥ 180° (M+) free | test `v31_door_clearance` |
| Ships | 6 ship models (trader, shuttle, liner, medical, science, courier), upgraded landing pad (11.5 m), 20 s landing / 15 s take-off with legs, ramp, flames, dust, floodlights | critic 0.80 |
| Visitors | Traffic schedule (deterministic, forecast 1 day), Grant/Deny, orbit hold in hazards; traders (trade screen, credits), immigrants (choose by person), tourists (fees), medical, science, inspector; 7 visitor looks | tests `v31_*` (SIM), `test_ships_ui.gd` 18/18; critic 0.78 |
| Windows | Every panel, dialog and popup is clamped inside the view (8 px), shrinks and scrolls when too big | `tools/ui/test_window_bounds.gd` 68/68 at 1920×1080, 1280×720, 800×600 |

**Critic gate:** rounds 9–14. All 26 subjects pass; v3.1 subjects 0.77–0.80.

**Measured** (i7-14700K, RTX 3060, headless Chrome with GPU, 1600 × 900): tick 1.56 ms median at
70 colonists (limit 2.0); `showcase_v3_late` 64.5 fps mean, `showcase_v31` 63–70 fps, draw calls
≤ 1,281; web pck 79.7 MB (v3.0: 62.3 MB). Tests: 76/76.

**Known weak points of 3.1**
- Two colonists meeting in a doorway can still pass through each other (reduced 15 %, not solved).
- One frame of 131 ms in `showcase_v31` at speed 4, about 73 s after load, cause not found; a few
  frames of 51–59 ms remain. Audio dropouts measured 0 in 30 s runs.
- Old-save 2.8 m airlocks with corridors at blocked angles: bodies walk round the inner door housing.
- Nobody has listened to the music or sounds; a purchase is tested only in the test suite.

## Deferred (named in the spec, not built)

| Item | Note |
|---|---|
| Trade and landing-pad ships | Built in version 3.1 (six ship kinds, trade, visitors). |
| Robots | Cargo and maintenance robots are not built. |
| Disasters | Built in version 3 (seven hazard kinds and breakdowns). |
| Medicine production | Built in version 2 (recipe `medicine`, medic). |
| Cold and airless planets | Built: the New colony screen offers all three planets. |
| Audio | Built in version 2: 20 clips (ElevenLabs), five buses, volume settings. |
| Rebindable keys | Fixed for now. |
| Victory screen | Built in version 2 (goals chapter 5 complete). |

## Known weak points

- Performance beyond 70 colonists is untested. v3: 1.78 ms per tick at 70 colonists, with one
  1000-tick window at 1.97 ms; the HUD-on overview dipped to 48 fps in one of three runs.
- The long reference campaign finishes the hull on day 25.2 against a limit of day 27.
- The v2 showcase saves (256 m) can no longer be regenerated; they still load.
- Hazard visuals are hard to read inside a dust storm; the late showcase save starts in one.
- The reference campaign is tuned on seed 1001. On seed 1004 the survey does not happen by
  day 27: the forward airlocks wait for steel that the factories take first.
- The 3D view does not fade a roof progressively; it lifts it at a fixed camera distance.
- Meals leave a kitchen only above a keep level, so a colony with one kitchen and many
  people will see the kitchen buffer swing.
- The reference driver repairs its own layout when the terrain refuses a spot. That is
  deliberate (a seed is not a promise), but it means the demo is not identical on every seed.
