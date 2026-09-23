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

## Deferred (named in the spec, not built)

| Item | Note |
|---|---|
| Trade and landing-pad ships | The landing pad can be built; no ship arrives. |
| Robots | Cargo and maintenance robots are not built. |
| Disasters | The dust storm is built (version 2). Meteor, radiation and equipment fault are not built. |
| Medicine production | Built in version 2 (recipe `medicine`, medic). |
| Cold and airless planets | Built: the New colony screen offers all three planets. |
| Audio | Built in version 2: 20 clips (ElevenLabs), five buses, volume settings. |
| Rebindable keys | Fixed for now. |
| Victory screen | Built in version 2 (goals chapter 5 complete). |

## Known weak points

- Performance beyond 70 colonists is untested; at 68 colonists a tick is 1.35 to 1.63 ms.
- The reference campaign is tuned on seed 1001. On seed 1004 the survey does not happen by
  day 27: the forward airlocks wait for steel that the factories take first.
- The 3D view does not fade a roof progressively; it lifts it at a fixed camera distance.
- Meals leave a kitchen only above a keep level, so a colony with one kitchen and many
  people will see the kitchen buffer swing.
- The reference driver repairs its own layout when the terrain refuses a spot. That is
  deliberate (a seed is not a promise), but it means the demo is not identical on every seed.
