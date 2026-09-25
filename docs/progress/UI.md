# UI progress log

Owner: UI agent. Files: `presentation/main.gd`, `presentation/boot.gd`, `main.tscn`, `ui/**`,
`assets/ui/**`, `assets/fonts/**`, `assets/audio/**`, `project.godot`, `tools/ui/**`.

## 2026-09-24 — design system, HUD, first screens landed

Check: 103 scripts, 0 failed. Web export: `build/web_ui/`. Screenshots checked at 1280x720 with the
day-9 showcase save.

### Landed

| area | files | notes |
|---|---|---|
| Palette | `ui/theme/palette.gd` | §1 colours, category, role, tier, nutrient and severity colours. |
| Fonts | `ui/theme/fonts.gd` | Inter (variable: 400/500/600/700 by FontVariation), Space Grotesk with +1/+2/+3/+6 px tracking, JetBrains Mono for numbers. Loaded at run time, engine font as fallback. |
| Panel look | `ui/theme/fh_style.gd` | Scripted StyleBox: chamfered corners, gradient fill, 1 px border, corner brackets, header strip, accent bar, outer glow. |
| Theme | `ui/theme/ui_theme.gd` | One Theme with type variations: HudPanel, CardPanel, WellPanel, ModalPanel, ToastPanel; Primary/Ghost/Tab/Nav/Speed/Chip/Danger/Card/List buttons; Head/Title/Display/Num labels; tooltips, scroll bars, line edit, slider, toggles. |
| Glass blur | `ui/widgets/glass.gd` | Frosted backdrop (13-tap blur of the screen texture) behind every glass panel; follows the panel's fade; one switch in Settings. Screens re-copy the back buffer so they blur the HUD too. |
| Icons | `tools/ui/make_icons.mjs` → `assets/ui/icons/*.svg` + `icons.json`; `ui/theme/icons.gd` | 167 duotone glyphs: 34 items, 7 item categories, 10 building categories, 5 roles, KPIs, severities, actions. Rasterised at the drawn size x2 with mipmaps. |
| Kit | `ui/kit.gd`, `ui/widgets/*` | Factories (labels, buttons, chips, bars, badges), FhButton (wrapped tooltips, sounds), GlowBar, KPI widget, build card, medal. |
| Charts | `ui/charts/` | chart_base (axes, nice ticks, legend, in-chart hover tooltip), line/area/stacked area, grouped bar (vertical/horizontal), donut, gauge, sparkline. |
| Data adapter | `ui/data.gd` | Every 2.0 field read with `.get`, every helper called only after `has_method`; derives what it can when a system is missing. |
| HUD | `ui/hud.gd`, `ui/hud/*` | Top bar (8 KPIs with trend, days of supply, breakdown + sparkline tooltips, click to the dashboard page; materials), time panel (day/night dial, 06:00 clock, sunrise/sunset countdown, speed buttons), nav rail (goals, research, dashboard, inventory, colonists, awards, overlay, menu; badges), goals tracker (chapter, goals, bars, sustain timers, rewards), alerts (incidents with severity icon + word, time left, action, consequences, Show), build bar (7 category tabs, cards with thumbnails, cost chips red when short, output, power, S/M/L/XL chips with per-size numbers, lock with the research), inspector (Overview, Output, Crops, Menu, Upgrade, Staff, Stats; colonist Status + Nutrition), minimap (terrain, structures by category, links, colonists, Meridian, camera view, click/drag to jump, overlay toggles), toasts, placement hint (cost, validity, reason, suit-range warning, keys). |
| Screens | `ui/screens/*` | Screen host (stack, pause, aliases), confirm dialog, pause menu, settings, save/load/import/export, how to play, loss report, title screen, new colony, award pop-up, chapter banner. |
| Game shell | `presentation/main.gd`, `presentation/boot.gd` | Title flow, new colony with planet/difficulty options, sizes while placing (Z/X or [ ]), RENDER ghost and link preview, settings applied (quality, UI scale, glass, edge pan, volumes), screen keys G T C I P V H F1, device profile. |
| Stores | `ui/profile.gd`, `ui/settings.gd` | `user://profile.json` (awards ever earned on this device), `user://settings.json`. |
| Audio | `ui/audio.gd`, `ui/sfx.gd` | Buses Master/Music/SFX/UI/Ambience, player pool, manifest `assets/audio/manifest.json`. Silent without files. |

### Boot and automation

- No URL parameters → title screen. `title=1` forces it; `title=0` skips it. Any of `seed`, `load`,
  `demo`, `fast` → straight into the game (other agents' tools keep working).
- New params: `planet=dry|cold|airless`, `difficulty=relaxed|standard|hard`.
- `window.__fh` adds `fps` and `title` (the open screen name).
- New commands: `place <def> <size> <x> <y> [rot]`, `tool <def> <size> [x y]`, `hover <x> <y>`,
  `build <tab>`, `agent <n> [tab]`, `select <def> [tab]`, `tab <name>`, `open <screen> [arg]`,
  `title [off]`, `newgame <seed> [planet] [difficulty]`, `quality <n>`, `uiscale <f>`, `hud on|off`,
  `time <sec|off>`, `award <id>`, `chapter <n>`, `toast <text>`, `fps`, `screen`.

## 2026-09-24 (later) — every screen landed, orchestrator findings fixed, audio

Check: 115 scripts, 0 failed. Export `build/web_ui/` (32 MB pck, with the other agents' assets).
Screenshots at 1600x900 in `docs/shots/ui_*.png` (25 files) plus `ui_hud_1280.png` at 1280x720.
Web build: about 59 fps with the day-9 save (headless Chrome, real GPU).

### Screens (`open <name>` in `window.__fh.cmd`)

| name | file | shot |
|---|---|---|
| title | `ui/screens/title_screen.gd` | `ui_title.png` |
| research | `research_screen.gd` + `ui/widgets/tech_node.gd` | `ui_research.png` |
| goals | `goals_screen.gd` | `ui_goals.png` |
| victory | `victory_screen.gd` | (opens when `state.goals.victory` >= 0) |
| awards | `awards_screen.gd` + `ui/widgets/medal.gd`, pop-up `award_popup.gd` | `ui_awards.png`, `ui_award_popup.png` |
| dashboard (alias colony, nutrition) | `dashboard_screen.gd`: overview, life, food, industry, population, research | `ui_dashboard*.png` |
| inventory | `inventory_screen.gd` | `ui_inventory.png` |
| colonists | `colonists_screen.gd` (+ immigration settings) | `ui_colonists.png` |
| menu, settings, saveload, help, newcolony, lost | as named | `ui_menu.png`, `ui_settings.png`, `ui_saveload.png`, `ui_help.png`, `ui_newcolony.png` |

### Orchestrator findings (2026-09-24) — fixed

1. Award cascade: `ui/hud/watchers.gd` treats the first 30 game seconds after any load or new game
   as catch-up. Goals, chapters, research and awards that appear then are recorded silently; one
   toast says "This colony has N awards." Nothing pops up and nothing enters the device profile on
   the title screen. Checked: day-9 save + `fast 40` → one summary toast, then only a real new medal.
2. Medal cards: a stack at the top centre, 4 s each, `MOUSE_FILTER_IGNORE`, at most 3 at once.
3. Plurals: `Kit.plural(n, "colonist")` in every text the interface formats.
4. Screen names as §14: research, goals, awards, dashboard, inventory (and colony = dashboard).

### Audio

20 clips generated with ElevenLabs (audio-gen skill, Paul's key) from `tools/ui/audio-events.json`
into `assets/audio/*.mp3` (1.3 MB): click, hover, tick, select, confirm, place, error, open, close,
toast, alert_warning, alert_critical, award, chapter, research, construct, airlock, and three 20 s
ambience beds (wind, base hum, night). `assets/audio/manifest.json` maps them to buses and levels.
Ambience follows day and night. Volumes per bus in Settings. Not listened to by a person yet.

### Coordinator follow-ups (2026-09-24, late) — done

- R1: placement uses only `view.set_ghost` / `clear_ghost` / `set_link_preview`; old ghost code removed.
- Camera speed slider drives `rig.pan_speed`.
- Chart x labels stay inside the chart (the last one right-aligns at the edge).
- Airlock sound: when an airlock within 45 m of the camera focus starts a cycle (at most every 2.5 s).
- HUD performance, RENDER's stress colony (152 structures, 60 colonists), 1600x900, headless
  Chrome with the real GPU (capped at 60 fps by vsync, so draw calls and process time are the measure):

  | | before | after |
  |---|---|---|
  | draw calls added by the HUD | +732 (2052 vs 1320) | +230 (1550 vs 1320) |
  | minimap draw calls | 522 | 20 |
  | frame rate, HUD on | 60 (cap) | 59–60 (cap) |
  | process time, HUD on minus off | about 13 ms (single samples) | within noise: 21.4 vs 18.9 ms paused, 18.2 vs 20.5 ms at 1x (smoothed) |

  Changes: minimap painted into one texture at about 1 Hz (camera view drawn live); top-bar KPIs
  are one hand-drawn control each and redraw only when a value changes; sparkline data is read only
  when a tooltip opens; trends read the live series without copies; slow panels (goals, alerts,
  nav, build bar, minimap) refresh at 2.5 Hz; containers are cleared at once, not by queue_free;
  the alerts panel shows only the cards that fit above the minimap. New commands: `perf`
  (fps, draw calls, smoothed process ms) and `hudpart <module> on|off`.

### Open issues

- Structures without a thumbnail show a glyph on a hexagon plate; thumbnails appear as ART lands them.
- Medal pop-ups sit over open screens for their 4 s.

## 2026-09-24 — version 3, milestone 1: alert toasts, hazards, research packs, maintenance

Contract: `docs/V3_DESIGN.md` §2 and §8. SIM's hazard module (`sim.hazards`) did not exist
during this work; everything reads the contract names with `has_method` / `.get()` and falls
back safely. Research packs, lab focus and supply-run cargo use SIM's real code.

| item | files | state |
|---|---|---|
| Alert toasts (§2) | `ui/hud/alert_gate.gd`, `ui/hud/watchers.gd`, `ui/hud/alerts_panel.gd` | done, tested |
| Hazard panel + banner + Shelter (§8) | `ui/hud/hazard_panel.gd`, `ui/hud/hazard_banner.gd`, `ui/data.gd` | done; real data needs `sim.hazards` |
| Research: packs, labs, focus, lock reasons | `ui/screens/research_screen.gd`, `ui/widgets/tech_node.gd`, `ui/widgets/focus_picker.gd` | done on SIM's real API |
| Maintenance view | dashboard tab Hazards (`open hazards` / `open maintenance`), inspector wear row, Maintain now | done; real data needs `sim.hazards.at_risk` |
| Inspector parts | assembler recipes (locks, water, automatic), turret, wear/fault/breach, Meridian cargo | done |
| New colony hazards, camera shake | `ui/screens/newcolony_screen.gd`, `ui/settings.gd`, `settings_screen.gd`, `presentation/main.gd` | done |
| Minimap 810 m | `ui/hud/minimap.gd` | done: image ≤ 360 px, Zoom (colony), hazard rings, hazard-zone overlay |
| `__fh.cmd` | `presentation/main.gd` | `hazard`, `follow`, `goto`, `interior`, `uimock`, `alerts`, `shake`; boot `debug=1`, `hazards=` |
| Icons | `tools/ui/make_icons.mjs` | +14: meteor, dust, quake, flare, dust_devil, wrench, shelter, turret, breach, pack_basic/applied/exotic, icat_science, hazard |

### Alert toast rule (UI side)

`ui/hud/alert_gate.gd`: a toast only for a new key at warning or critical; the same key never
toasts again for 180 s after it cleared; notices never toast; only roots toast; `blocked:<id>`
keys are one alert `output_blocked`. The alert cards use the same gate: stable order, and a key
that cleared and came back stays as one card ("CLEARED", dimmed) until it has been clear 180 s.
SIM's `live: false` (waiting `clear_after`) shows as "CLEARING". The "broken" log toast is gone
(the alert toasts once instead).

Test `node tools/godot.mjs script res://tools/ui/test_alert_gate.gd`: 17 of 17 pass.
Part A (made-up streams): the v2 defect (blocked 3 s on, 1 s off, 300 s) gives 0 toasts as a
notice and 1 toast as a warning, and the card never disappears; two harvesters blocked in turn
= 1 toast; changing numbers in the text = 1 toast; back after 100 s = 1 toast, after 200 s =
2; consequence promoted to root = no new toast; alert present at load = 0 toasts. Part B (real
simulation, 300 s from each showcase save): no alert toasted twice, no card went and came back
more than once.

### Mock data

`uimock hazards|maintenance|labs|all|off` (only with `debug=1`) fills the hazard, at-risk and
lab rows with made-up values (places relative to the lander, real machines). The shots of the
hazard panel, banner, Hazards page and the wear row use it. Never in play.

### Screenshots (1600 x 900, `docs/shots/`)

`ui3_hazard_panel.png` (panel + banner, mock), `ui3_hazards_page.png` (mock),
`ui3_insp_wear.png` (wear row, Maintain now, banner above the build bar, mock),
`ui3_insp_lab.png`, `ui3_insp_meridian.png`, `ui3_research_tree.png`, `ui3_research_labs.png`,
`ui3_newcolony.png`, `ui3_settings.png` (real data).

### Requests

`docs/requests/UI-to-SIM.md` (hazard names to confirm; per-lab RP rate; set cargo without a
flight; debug on a loaded save), `docs/requests/UI-to-RENDER.md` (`shake_enabled`,
`open_interior`, overlay `hazard`).
## 2026-09-24 — version 3, milestone 2: on SIM's real hazard code, measured

SIM's `sim/hazards.gd` landed during this work. The UI now reads it directly:
`forecast()` / `active()` (`eta_s`, `end_s`, `whole_map`, `countered`, `advice`), `info(bid)` (wear,
fail_at, fault, item, eta_s, at_risk, breach, turret charge), `at_risk()`, `sheltered()`,
`zone_at()`, `turret_range(b)`, and `load_state(state, {debug: true})` for `load=` + `debug=1`.
Log toasts (once each): `hazard_detected`, `hazard_start`, `hazard_impact`, `hazard_intercepted`,
`hazard_end`, `breach_sealed`, `shelter`, `survey`. Warnings, breaches and breakdowns come as
SIM alerts and toast once through the gate.

Checked in the web build (new colony, seed 1001, 810 m map, `debug=1`, commands
`hazard meteor 470 380 2 45`, `hazard solar_flare ...`, `hazard quake ...`, `hazard wind_storm ...`):
cards with real countdowns and advice, the banner under 30 s, Shelter → "End shelter" (SIM state),
the impact toast "A meteor hit near Lander.", quake and meteor rings on the minimap, zone overlay,
colony zoom. Shots: `ui3_hazard_real.png`, `ui3_banner_real.png`, `ui3_after_impact.png`,
`ui3_minimap_810_hazard.png`, `ui3_minimap_810_zoom.png`, `ui3_hazards_page_real.png`,
`ui3_cmd_interior.png`, `ui3_cmd_follow.png`.

Automation: `idof <def>` / `idof agent [n]` return ids for `interior` and `follow`; `shelter on|off`;
`minimap zoom|whole`. Tested: `interior 38` (habitat, roof open), `follow 16`, `goto 300 300`,
`hazard meteor` without debug → "refused: start with debug=1".

### HUD cost (showcase_late, 1600 x 900, paused, real GPU, capped at 60 fps)

| build | HUD off | HUD on | HUD adds |
|---|---|---|---|
| v2 (`build/web`) | 890 draws | 1134 | +244 |
| v3 (`build/web_ui`), no hazard | 877 | 1124 | +247 |
| v3, hazard panel + banner + minimap rings (mock) | 877 | 1192 | +315 |

Process time: 9.1–9.8 ms HUD on in both builds (noise). The hazard panel and banner are hidden,
with no draw calls, when nothing is detected.

### Not done / not tested

- Per-lab RP per day: SIM's `lab_info` gives multipliers only; the Labs page shows "x1.6" (now and
  without packs). Asked SIM for `rate` (UI-to-SIM C1).
- Cargo choice is kept in the UI until "Supply run" is pressed; asked SIM for `ship {action: "cargo"}` (C2).
- Camera shake off: works by zeroing the rig's private `_shake` each frame until RENDER adds
  `shake_enabled` (UI-to-RENDER 2). Not checked by eye during a real quake.
- Hazard toasts in the first 30 s after a load or new game are silent (the v2 grace rule).
- The alert list can overlap the minimap header for a moment when many cards arrive (v2 behaviour: it
  drops one card per frame until it fits).
- One web export crashed at start on the 810 m map ("memory access out of bounds") while other agents
  were changing files; the next two exports and the ART-HAB and RENDER builds did not. Not reproduced.
- Not tested: 1280 x 720 layout of the new panels; the OptionButton popup style of the focus selector;
  a real turret, breach and meteor fragment site in the inspector (none existed in the test colonies).
## 2026-09-25 — v3.1: sound works, mood music, world sounds, ships, trade, visitors

Contract `docs/V3_1_DESIGN.md` §1, §2, §6.5. The orchestrator's §1 fix (Stream playback,
`default_bus_layout.tres`) is kept; `ui/audio.gd` still makes a bus only when the layout lacks it.

### Sound and latency (§1)

- `project.godot` `audio/driver/output_latency.web=150` (engine web default 50). Cost: sounds start up
  to about 150 ms after their cause (the interface click too).
- Tool `tools/ui/audio_glitch_probe.mjs`: an AudioWorklet tap on every source to the destination counts
  dropouts (a 128-sample block of silence right after sound). `--burn <ms>` busy-waits each frame (a slow
  machine); `--stall N` is a positive control. `maxfps` below the display rate silences web audio, so it
  is not used for this.

  | latency | new colony 42 fps (burn 18) | new colony 30 fps (burn 28) | late save speed 1 | late save speed 4 |
  |---|---|---|---|---|
  | 50 (default) | 255 dropouts / 13 s | 324 / 13 s | not measured | not measured |
  | 75 | 0 | 0 | - | 299 / 21 s (burn 18) |
  | 100 | 0 | 0 | 58 / 21 s | 161 / 21 s |
  | 150 (chosen) | 0 | 0 | 5–8 / 21 s | 9–10 / 21 s |
  | 200 | - | - | 6 / 21 s | 12 / 21 s |

  The dropouts left at 150 ms come from frames of about 140 ms on the late save while the colony runs
  (`__fh.cmd('spikes')`): not the HUD (same with it hidden), not the simulation (`simprof 300`: mean
  2.3–2.5 ms, max 18.7 ms per tick). Reported to RENDER (UI-to-RENDER 6). More latency does not help.
- Gate `tools/audio_probe.mjs build/web_ui`: music 0.5 (default) peak −23.6 dBFS, PASS; music 1.0
  −18.1 dBFS; music 0 (ambience only) −30.1 dBFS, PASS at −60.

### Music (§2.1)

6 tracks from Eleven Music (`tools/ui/audio-events.json`, 128 kbps): title 105 s, day 1 and 2 165 s,
night 150 s, tension 105 s, arrival 25 s; 11.4 MB. Levels from ffmpeg volumedetect in
`assets/audio/manifest.json` ("music" table). Director `ui/music.gd`: title / day / night / tension from
main twice a second; 4 s crossfades; no restart in the same state; day tracks alternate; a gap of
5–20 s from a local counter; tension (active hazard not covered, critical alert, breach) holds 30 s after
the cause clears and loops; `mus_arrival` cue over the music (−10 dB dip) on touchdown.
Test `tools/ui/test_music.gd`: 13 of 13. Web: title screen `mus_title`, new colony `mus_day_1`.

### World sounds (§2.2)

13 SFX generated. `main.audio.world(name, pos) -> handle`, `world_stop`, `world_move`: full within 12 m of
the camera focus, silent at 120 m, at most 3 of one name (a nearer one replaces the farthest); loops stop
at `max_s`. `ui/hud/world_sounds.gd` plays what the simulation decides: airlock phases (seal, pump loop,
vent / door), meteor and shower strikes, quakes, intercepts, storm loop, ship descent / touchdown /
take-off. RENDER keeps door_slide and ramp for view events. Test `tools/ui/test_world_audio.gd`: 12 of 12;
in `test_ships_ui` the real colony played airlock_seal 6, airlock_pump 14, airlock_vent 5, door_slide 4,
ship_descent 1, ship_touchdown 1 in 60 s.

### Ships, trade, visitors (§6.5) — on SIM's real API

- Traffic panel `ui/hud/traffic_panel.gd` under the hazard panel: kind, phase, countdown (in orbit: time
  before it leaves), offer chips, Grant / Deny, Settlers, Trade; hidden with no ships.
- Trade screen `ui/screens/trade_screen.gd`, shuttle dialog `ui/screens/shuttle_screen.gd` (count, beds,
  oxygen and food checks), Visitors tab in the colonist list, visitor inspector card, credits in the top
  bar (click: trade), toasts for `ship_*` and `trade`.
- `__fh`: `traffic`, `traffic <id> grant|deny`, `ship <kind> [s]` (debug), `trade [id]`,
  `trade <id> buy|sell <item> <n>`; test helpers `findspot`, `cable`, `idof visitor`, `volume`, `music`,
  `burn`, `spikes`, `simprof`, `prof`.
- Fixed on the way: compact dialogs no longer slide in (the shuttle dialog stood 827 px above the screen).
- Test `tools/ui/test_ships_ui.gd`: 14 of 14.
- Shots: `docs/shots/ui31_traffic_panel.png`, `ui31_shuttle_screen.png`, `ui31_trade_screen.png`,
  `ui31_visitor_card.png`, `ui31_visitors_tab.png`.

### Not done / not tested

- The shuttle dialog chooses a number of settlers, not persons (SIM takes a count; asked, UI-to-SIM 1).
- Late-save dropouts (5–10 per 20 s) remain until the ~140 ms view frames are fixed (RENDER).
- Music and SFX not listened to by a person. HUD draw calls with the traffic panel not measured.
- No purchase tested (the migrated save has 0 credits); a sale was tested (paid on delivery).
## 2026-09-25 (later) — window bounds (Paul's request) and door sectors

**Window bounds** ("info and UI windows can not open outside the view panel"). One place:
`ui/hud/bounds_keeper.gd`, a node that runs last each frame (process_priority 1000). It covers every HUD
panel, every screen frame and dialog, toasts, medal pop-ups, banners and the placement hint: a window that
leaves the view moves back inside with an 8 px margin; a window taller than the view gets `fit_height()`
when it has it. `ui/screens/screen.gd`: content in a scroll area; title, tabs and extras in a sideways clip
area (the close button stays outside it); `fit_view(vp)` caps compact dialogs to the view width, sizes
their content area to the view height and centres them; full screens keep margins of at least 8 px.
Screens open with a fade only (the slide tween fought the clamp). Desktop minimum window 800 x 600 (was
1024 x 600). No window can be dragged, so there is no drag case; tooltips are placed by the engine.

Test `node tools/godot.mjs script res://tools/ui/test_window_bounds.gd`: **68 of 68 pass** — 1920x1080,
1280x720 and 800x600 (logical, no stretch scaling: harder than the game); HUD with every panel full
(mock hazards, traffic, labs), inspector on a structure and a colonist, 4 toasts, medal, banner; 17 screens
and tabs (each proven open), the confirm dialog; inspector at the 4 corner structures; resize 1920x1080 ->
800x600 with dashboard, new colony, research and settings open.
Shots at 800x600 (web, stretch on): `docs/shots/ui31_bounds_hud.png`, `_dashboard`, `_research`,
`_newcolony`, `_settings`, `_shuttle`.

Correction to the v3.1 section above: the "compact dialogs no longer slide in" change did not apply then
(a text replace missed); the shuttle dialog was fixed by giving its check lines a width. It is true now.

**Door sectors.** `ui/hud/sector_overlay.gd`: green and red arcs on the wall ring of the room ghost and of
both rooms of a corridor being drawn, with a dot where the corridor meets the wall. Data
`hud.data.blocked_sectors(def, size)`: SIM's `sim.place.blocked_sectors` when it exists, else a copy of
ART-HAB's measurement. The hint shows SIM's refusal sentence; until SIM has the rule it warns. Shots:
`docs/shots/ui31_link_sectors.png` (the shot shows SIM's current refusal "no corridor port", not a sector
refusal: that rule is not live yet), `ui31_link_sectors_free.png`, `ui31_room_ghost_sectors.png`.
## 2026-09-25 (later) — shuttle by person, sectors on SIM's rule

- Shuttle dialog: one check box per settler (role and what it does), All / None / As many as free beds,
  the bed, oxygen and food checks for the picked number, and a countdown (arrives in; in orbit: SIM `t_s`,
  time before it leaves). Confirm sends `traffic_answer {id, grant: true, accept_idx}`. The traffic panel's
  orbit countdown also reads `t_s`.
- Door sectors: now SIM's own rule, `sim.place.link_angle_ok_for` (the test behind the `door_blocked`
  refusal; model angle = rot - world angle). The ART-HAB copy `assets/ui/door_blocked_fallback.json` and the
  interim warning are deleted. `docs/shots/ui31_link_sectors.png` is a real refusal: rooms 47 -> 51 on
  showcase_v3_late (found by the new `findblocked` command), the red dot on the blocked wall and SIM's sentence
  "The door would open onto equipment. Choose another side of the room." as the hint.
- Tests: `test_ships_ui` 17 of 17 (new: one check box per settler, countdown, accept_idx [0] stored by SIM);
  `test_window_bounds` 68 of 68 after the shuttle change.
## 2026-09-25 (later) — "Invalid polygon data, triangulation failed" traced and fixed

`ui/poly_guard.gd` `PG.ok(points, tag)` now guards all 19 polygon calls of the interface (charts, widgets,
title screen, the theme stylebox): fewer than 3 points, area under 0.01 px² or NaN/inf -> the polygon is
skipped and counted by caller. In `test_window_bounds` (68 of 68 pass) the counts were
`sparkline.gd:51` 3,223 (a flat series at the chart bottom: zero-height quads) and `bar_chart.gd:60` 3
(zero-height bars). The engine error no longer appears.
## 2026-09-25 (later) — the ~61 s long frames; duplicate door_slide

`spikes` now splits each frame over 50 ms into sim / view.sync / HUD / audio script time. The long frames about a
minute into play are the first night frames at sunset (both showcase saves stand near dusk): 139–147 ms with scripts at
2–14 / 7–13 / 0–2 / 0 ms. Reproduced paused with a view-only night switch (108 ms once, then none); music and
ambience changes give none. Not UI work; sent to RENDER with the numbers (UI-to-RENDER, 2026-09-25). No UI change
could reach the 50 ms target for those frames. The UI's duplicate door_slide at the airlock "open" phase is removed
(RENDER plays every door). Debug commands added: `mus <state|auto>`.
## 2026-09-25 (later) — traffic notices

`sim.traffic.notices()` ([{code, count, text}], e.g. "3 tourists have no bed. The fee drops.") shows as an amber line on
the card of the ship it belongs to (by kind: tourists -> liner; the first such ship landing, landed or boarding), or at
the bottom of the traffic panel when that ship is not on show; never in the alert list. Tests: `test_ships_ui` 20 of 20
(new: the notice sits on the mock liner card; no tourist text in the alerts), `test_window_bounds` 68 of 68.