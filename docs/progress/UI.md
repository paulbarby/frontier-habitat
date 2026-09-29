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
## 2026-09-26 — effect sounds only when zoomed in and close (Paul)

`ui/audio.gd`: world sound level = zoom factor x distance factor, by class, numbers in `assets/audio/manifest.json`
"world_rules". Local (doors, airlock seal/pump/vent, construction, ramp, turret, ship descent/touchdown/take-off,
the old airlock sound): zoom full <= 20 m, silent >= 35 m; source full within 8 m of the focus, silent at 25 m.
Big (meteor impact, quake rumble, storm loop): every zoom, 0.4 of the level at >= 150 m zoom, silent beyond 500 m.
Levels follow the camera each frame (loops fade out on zoom-out, back on zoom-in); a silent one-shot does not start.
Construction and upgrade sounds moved from the interface bus to world sounds at the structure.
Tests: `test_world_audio` 16 of 16 (no local sound at 110 m or 50 m zoom; full at 15 m zoom within 8 m; loop fade;
big events at 110 m zoom lower than close); `test_ships_ui` 20 of 20 (camera at 15 m over the pad);
`test_window_bounds` 68 of 68; `audio_probe` PASS: music −23.7 dBFS peak, ambience only −30.1 dBFS.
## 2026-09-27 — version 4.0, milestone 1: theme and window manager pilot, version

Contract `docs/V4_DESIGN.md` §7 (and §3.4, §6, UI of §2 and §5 later).

**Theme "space-age glass" (pilot: HUD top bar + inspector window).**
- `ui/theme/metal.gd`: procedural textures, made once: a nine-patch metal frame (brushed gunmetal band, 9 px
  for windows, 6 px for HUD bars; outer bevel light top-left, dark bottom-right; dark inner lip; faint cyan inner
  glow; chamfered top-left and bottom-right corners; a rivet in each corner and one per 96 px edge tile with an
  engraved seam at each tile start) and a brushed title plate with end rivets and an engraved seam.
- `ui/theme/glass_frame.gd`: the StyleBox: drop shadow (windows), cool frosted tint, top sheen, title plate with a
  family-colour accent line, and the metal frame as ONE nine-patch per panel (shared texture).
- Blur `ui/widgets/glass.gd`: radius 6.5 and a fine frost grain, still 13 samples.
- Cost, measured uncapped (`tools/ui/perf_uncapped.mjs`, Chrome without vsync, late save, 1600x900, inspector
  open): glass on 59.6 fps, glass off 60.4 fps, HUD off 68.8 fps: the blur costs about 0.2 ms a frame (noise level).

**Window manager** `ui/wm/window_manager.gd`: register(window, id, title-bar handle, default place); opens at the
remembered place (per window, `user://windows.json`, fractions of the free work area) or at its default place in
the work area (view minus top bar, build bar and nav rail); drag by the title bar (the title bar cannot leave the
view); snap to work-area and other window edges within 14 px; click raises; Esc closes the last window (after tools
and screens); Shift+Esc or `closeall` closes every window; the v3.1 bounds keeper stays. The inspector is the
first window (dragged by its header; Esc/close-all clear the selection).
Commands: `wm`, `drag <id> <x> <y>`, `esc`, `closeall`, `glass on|off`.

**Version:** `application/config/version="4.0.0"`; title logo badge "4.0" and footer "Frontier Habitat 4.0.0";
Settings → About "Frontier Habitat · version 4.0.0" (Settings dialog widened to 880 px for it).

**Tests:** `tools/ui/test_wm.gd` PASS (default place, snap, Esc, reopen at the remembered place, title bar kept in
view, close all, resize to 1280x720 inside the view); `test_window_bounds` 68 of 68; `test_ships_ui` PASS.

**Shots:** `docs/shots/ui4_pilot_hud_inspector.png`, `ui4_pilot_inspector_moved.png` (dragged, colonist),
`ui4_pilot_frame_closeup.png`, `ui4_pilot_bar_closeup.png` (3x crops), `ui4_title_version.png`,
`ui4_settings_about.png`.

**Not yet:** only the top bar and the inspector use the new look (by the pilot rule); buttons, tabs, lists and the
other panels keep the v3 look until the critic passes the pilot. Rivets are 5–6 px: at 1:1 they read as small dots.
## 2026-09-27 — version 4.0, milestone 2: critic round 15 fixes 1–8 and the rollout to every screen

**Fixes (round 15, UI part).**
1. Glass reads as glass: blur smoke 35% → 20% (`ui/widgets/glass.gd`); GlassFrame tint 50% (top) to 64% (bottom),
   effective opacity over the scene about 60–71%; sheen 10%; a 1 px inner highlight at the top edge of the glass.
   Contrast, measured by `tools/ui/contrast.gd` on the late save by day in the dust storm (1600x900):
   - measured in the panels (background = p90 of non-text pixels): goals 8.87:1, hazards 9.07:1, inspector 10.82:1,
     alerts 10.69:1 for body text (TEXT); 4.96–6.05:1 for secondary text (TEXT_2). AA 4.5:1 met.
   - worst-case bound (brightest scene pixel p99.5 #caa581, unblurred, top of the glass, full sheen): TEXT 4.74:1
     (HUD) and 6.43:1 (windows); TEXT_2 2.65:1 and 3.59:1. The blur averages, so no real panel reaches this bound.
   - TEXT_3 (hints, disabled) was 2.5:1; raised from #6A7F97 to #8497AE: 3.47–4.24:1 measured (below AA; it is only for hints and disabled text).
2. Nav rail: the work area ends 8 px left of the rail's real rect; each frame a window that grew or was dragged into
   the rail strip moves left (not while it is dragged). The inspector no longer grows: long lines wrap (fix 7).
3. Goals, hazard and traffic panels are snap targets and FOLD while a window covers them; they open again when it
   leaves (window manager `_process`, `folded_names()`).
4. Rivets: domed (sphere-normal shading, specular), 8.6 px across plus the seat ring (10 px), at the corners and one
   per 180 px edge tile (TILE 96 → 180, MARGIN 24).
5. Grain contrast about 2x; band one step lighter (gradient #59636E–#2A3139 → #6C7783–#363E47); band 8 px (HUD) and 10 px (windows).
6. The stray square: the title plate's own end rivets are removed (the frame carries the rivets).
7. Inspector: right margin 22 px (10 px band + 12 px glass); wear line and fact rows wrap; tabs share the width
   (clip, 3 px side margins, 11 px text). The window keeps 392 px on every tab (tested).
8. Seams: an engraved hairline (dark + light) under every title plate, between the inspector tabs and content,
   and every HSeparator/VSeparator is now a seam (`ui/theme/seam_line.gd`).

**Rollout (round 15 rules), theme level, so every screen follows.**
- One frame language: `ui/theme/rim.gd` (bevelled metal rim, one triangle-array command) used by FhStyle
  (`rim`, `engraved`, `inner_glow`, `top_line_w`); brackets removed from the theme. HUD panels, the default
  PanelContainer, toasts and full screens are GlassFrame; a panel under 48 px gets the 2 px rim instead of the nine-patch.
- Buttons: glass fill, 2 px raised rim; pressed = engraved. Primary: dark teal glass that glows inside the rim
  (no flat cyan block). Tabs: metal edges; selected = lit glass with a 2 px accent line in the family colour
  (screens: their accent; inspector: the structure family). Nav, chip, speed, danger, card buttons: rimmed.
- Cards and wells are engraved into the glass; lists in the alerts, hazard and traffic panels use `list_row.gd`
  (signal bar + seam, no box per row). Line edits are engraved. Tooltips and popups are rimmed.
- Charts: a darker engraved well; grid lines as faint seams (`chart_base.draw_seam_h/v`); the hover tip is rimmed.
- Full screens: the header is the GlassFrame title plate (height follows the header); tabs sit on the plate.
- Title: the 4.0 badge is a brushed plate with a bevel and four rivets. Tech tree nodes have the metal rim.

**Tests.** New `tools/ui/test_theme_v4.gd` PASS (no theme style with brackets or a flat border; panel kinds; rims;
primary glow; engraved cards/wells; accent tab; seams; tint range; tile 180; bands; rivet 10 px; every visible HUD
panel and the research screen use v4 styles). `test_wm` extended (width kept, clear of the rail after a drag into
it, goals fold and unfold): PASS. `test_window_bounds` 68/68, `test_ships_ui`, `test_music`, `test_world_audio`,
`test_alert_gate`: PASS. `check`: 0 failed.
**Find (V4_DESIGN §3.4), first part.** `ui/hud/find_window.gd`: a window of the window manager (key `/` or
Ctrl+F, or the new Find button on the nav rail; drags, remembers its place, Esc closes it). Type a name, a type or a
family word ("kitchen", "habitat 2", "lab", "science"); every matching structure is listed in a dark well with its
family icon, district, size and status (the inspector's status words); corridors and cables are not listed. Click or
Enter: the camera goes there and selects it. "Mark all <type>" marks every structure of that type on the map
(`ui/hud/find_marks.gd`: a pulsing ring in the family colour and a name tag; an arrow at the view edge for each one
outside the view). Commands: `find <text>`, `findmark <def>|off`. Test `tools/ui/test_find.gd` PASS (14 checks).
Still to do for §3.4: family icons on the minimap and a label layer by family.
Also: OptionButton (drop-down lists) now has the rimmed button style (it had Godot's default look); the title
screen's primary button text is light on the dark glowing glass; compact dialogs are 20 px wider so the metal band
does not push the content into a sideways scroll (test: no sideways scroll bar on any screen at 1600x900); the
colonists table "Doing" column is 232 px (was 260) for the same reason.Label layer (§3.4): Find window → "Names on the map": Off, All rooms, or one family. Name tags over the rooms,
never overlapping, family-colour underline (`find_marks.set_labels`, command `findlabels off|all|<family>`); it adds to
the 3D view's own labels, which show important blocks only. Minimap: family icons on the rooms when a room is at
least 4 px across (colony zoom), and a ring on each structure marked from Find. With several bases (sim.bases, SIM
milestone 2) each Find row names its base and a base name matches.
New colony (SIM request 2026-09-27): a Map row, "Frontier" (2,560 m, scenario "frontier") is the default, "First
landing" (810 m) stays. Test `tools/ui/test_newcolony_map.gd` PASS (default, 2,560 m, 810 m).Tables (round 15 list rule): inventory, colonists (both tabs) and trade lists are now `Kit.seam_list()` rows (an
engraved seam between rows, none round section headings) inside `Kit.well_scroll()` (a darker engraved well).
Keys: "/ or Ctrl+F" and "Shift+Esc" added to Settings → Keys and Help → Controls.**Bases (V4_DESIGN §2 UI; SIM `sim.bases`, milestone 2).** With more than one base the top bar starts with a base
switcher: "All bases" or one base (hidden with one base). Picking a base moves the camera to its core and sets
`hud.base_filter`: the alerts panel shows that base's alerts and the colony-wide ones (`issue.base` −1); the inventory
screen shows `sim.bases.totals(base)` and names the base in its subtitle. Find rows name their base. Test
`tools/ui/test_bases_ui.gd` PASS (11 checks; the second base is founded with an Outpost Kit through the real
`deploy_outpost` command, the kit placed as test set-up like SIM's own test). No screenshot yet: no save has two
bases, and the UI does not write state to make one.
Rename: a pencil button (new icon `edit`, `tools/ui/make_icons.mjs`, 183 icons) beside the switcher while one base is
picked opens a name field; it sends `rename_base` (tested). Still to do for §2: the Outpost Kit deploy tool (preview
`sim.bases.check_outpost`), `core_expiry` in the alert copy, per-base chart series (SIM offers to add them).
**Evidence (rollout milestone).** `tools/ui/evidence_v4.mjs` (web build, headless Chrome, GPU): 118 shots in
`docs/shots/v4/`: every screen and HUD state by day (time 180) and at night (time 450), at 1600x900 and 1280x720
(HUD + building inspector, colonist inspector, toast + award, traffic panel, Find, Find marks, label layer + minimap
icons, goals, research tree and labs, dashboard overview/food/hazards, inventory, colonists, visitors, awards, menu,
settings, save/load, help, new colony, shuttle, trade, victory, lost, title, title + settings), and interface scale
80% and 125% at 1600x900 (HUD, research, settings). Contact sheets `docs/shots/v4/_sheet_*.png`.
Not in the shots (made after the run, tested headless): new-colony hazard cards 10 px taller, Find/Shift+Esc key
lines in Settings and Help, the base switcher and rename (hidden with one base; no save has two bases).
Not shown by the save: the confirm dialog (same compact modal frame as save/load).

**Cost** (`tools/ui/perf_uncapped.mjs`, uncapped Chrome, late save, 1600x900, inspector open; two runs, noisy):
HUD on 49.4–50.3 fps, glass off 51.5–52.3, HUD off 56.4–59.8. HUD 2.2–3.5 ms a frame (pilot 2.2 ms); glass blur
0.5–1.1 ms (pilot 0.2 ms: the panels are larger and more of them are glass now). Draw calls: HUD +363 (v3 +247):
the rims and seams are separate commands; batching them is open. Label layer: 1.9 ms when it redrew every frame;
now it redraws only when the camera moves: no measurable cost with a still camera.
Export `build/web_ui`: index.pck 70.9 MB (budget 95 MB; the size changed with other agents' assets).
## 2026-09-27 — draw-call budget, readable hints, critic round 21 fixes

**Draw calls (coordinator: HUD ≤ 250).** Measured in the web build (`perf` draws, HUD on minus HUD off, late
save, 1600x900, inspector open): 363 → **242**.
- `ui/theme/bake.gd`: each rimmed look (buttons, tabs, cards, wells, inputs, tooltips) is painted once into a
  small texture and drawn as ONE nine-patch (was a fill polygon + 1–2 rim rings + up to 3 glow rings).
- HUD panels: glass tint, sheen, highlight and the metal frame are one baked nine-patch (was 2 polygons, a rect
  and the frame). Windows: the fill and the drop shadow are baked nine-patches.
- `ui/widgets/glass_shared.gd`: every HUD panel, window and toast shares ONE blur drawer (one triangle array,
  one draw) instead of one blur node per panel. Full screens keep their own.
- Glow bars: only filled rects (the outline, gradient polygon and target line were separate commands).
- Per-module count before the last two steps: top bar 42, goals 58, build bar 32, time panel 24, minimap 19,
  nav rail 18, inspector + alerts + hazards + traffic 102.

**Hints (coordinator).** TEXT_3 is now #9FAFC2: 4.64–5.66:1 measured on the four HUD panels (was 2.5:1).
P.DECOR (#6A7F97) is for decoration only. Worst-case bound (brightest pixel, no blur, top edge, full sheen) stays
below 4.5:1 for TEXT_2/TEXT_3 (2.65 / 2.48); no measured panel is near it.

**Critic round 21.**
1. Bottom row: the build bar starts right of the minimap's real edge; when it does not fit, the tab names hide
   (icons and tooltips stay). The top bar hides credits, research, morale, energy (in that order) before it
   reaches the time panel. The alerts panel drops its "Do:" line, then its cards (summary stays), before it
   reaches the minimap. The interface scale is limited so the logical view stays at least 1300 x 660.
2. Low drag: at the end of a drag the window goes fully inside the work area.
3. Full screens: a 14 px frosted border zone in the lighter tint, the body at about 88 % (`frost_border`).
4. Text floor `ui/text_floor.gd`: no text under 12 screen px at any scale or window size; each text control
   keeps its wanted size and gets the floor on top; custom-drawn text uses `P.fs(n)`. Goal hints wrap, the
   inspector tabs flow onto a second row, KPI widths follow the floored size.
Tests: `test_window_bounds` 79/79 (new: bottom and top rows at 80/100/125/140 % in 1600x900 and 1280x720;
three low drags); `test_theme_v4` (new: no text under 12 px at 80 %); all 10 UI tests PASS; check clean.
## 2026-09-27 — version 4.0, milestone 3: helpers (V4_DESIGN §6)

- **Why stopped?** `ui/why.gd`: a plain reason and the fix for every structure (every SIM block code:
  materials, unreachable, suit range, occupied, broken/fault, off, no power, no water, no reservoir, no input
  (names the missing input), output full, storage full, stock limit, deposit empty, no worker (names the role),
  no recipe, no dish, no project, no packs, no air; an unknown code is shown by name) and for every colonist
  (idle: no job for the role, jobs it could not reach; needs first; suit air low; low morale). The inspector shows
  it in a dark well at the top of the body while the structure or colonist is stopped; it updates live.
  Colonist reasons are inferred from goal, needs and backoff until SIM adds `sim.agents.why()` (asked).
- **Advisor** `ui/advisor.gd` + `ui/hud/advisor_window.gd` (key N, nav rail): the biggest problems (worst live
  alerts, then food/water under 2 days, power deficit), the next goal steps (current chapter, with progress and
  the hint), unused potential (idle colonists by role, no research project, structures switched off, free beds,
  spare power with full batteries). Every row says what to do; Show moves the camera. Window-manager window.
- **Codex** `ui/codex.gd` + `ui/screens/codex_screen.gd` (key K, nav rail): items, structures, research, hazards
  (38/42/45/8 entries), a search box and a seam list; each entry says where it comes from (recipes, buildings,
  crops, deposits) and what uses it (recipes, build costs, research packs, dishes), with links between entries.
  Items show a **crafting tree** (`ui/widgets/craft_tree.gd`): raw materials on the left, recipe and building
  under each product, click a card to open it.
- **Planner overlays**: "radiation", "sun" (share of the day in sunlight), "resources" (deposits by tier) on
  the minimap (header buttons, a legend under the map) and in the O cycle. The 3D layers are RENDER's: split
  written in `docs/requests/UI-to-RENDER.md`. "Explored" and "vehicle ranges" wait for SIM data (asked in
  `docs/requests/UI-to-SIM.md` with the other v4 names).
- Keys N and K added to Settings → Keys and Help. New icons `advisor`, `codex` (185 icons).
- Test `tools/ui/test_helpers.gd` PASS (22 checks: why for every structure and colonist, off / no input / unknown
  code / idle colonist, inspector well, advisor content and place, codex counts and relations, hull plate tree
  down to ore, links, search, planner overlays). HUD draw calls 244–249 with the new rail buttons.
- Minimap: the planner buttons sit in the map header; the overlay buttons use 3 px margins and fitted icons, so
  the panel is 282 px tall (was 310): the alerts panel keeps a full card at 1600x900.
- "materials:<item>" on a working structure (repair, upgrade, ship work) reads "Waiting for <item>" in the
  status badge and the why well.
- Shots: `docs/shots/ui4_helpers_advisor.png`, `ui4_helpers_why_structure.png`, `ui4_helpers_codex_item_tree.png`,
  `ui4_helpers_codex_structure.png`, `ui4_helpers_codex_research.png`, `ui4_planner_radiation.png`,
  `ui4_planner_sun.png`, `ui4_planner_resources.png` (Frontier map, seed 1001).
- Not yet: rich tooltips on every control beyond the existing ones; the vehicles and orders screens, the reactor
  controls and the Outpost Kit tool wait for SIM names (item 4 of the coordinator's list).
## 2026-09-27 — door sounds only right up close (Paul)

`assets/audio/manifest.json`: `door_slide` and `airlock_seal` are class **door** with their own `world_rules.door`:
full at a camera zoom of 10 m or less, silent at 18 m; full within 3 m of the camera focus, silent at 8 m; 6 dB
lower (door_slide −8 → −14 dB, airlock_seal −6 → −12 dB); at most one door sound at a time; the same door (name and
position to 0.5 m) not again within 1.5 s (`ui/audio.gd`, `max_at_once`, `repeat_s`). Other local sounds keep their
rules. `test_world_audio` 23/23 (new: none at 20 m zoom; none with the source 10 m from the focus at 10 m zoom; full
at −14 dB within 3 m at 10 m zoom; one at a time; no repeat within 1.5 s; local rules unchanged). The generic
local-sound checks now use airlock_vent. `test_ships_ui` PASS (RENDER's doors are now silent at the 15 m pad camera).
## 2026-09-27 — version 4.0, milestone 4: tooltips, clipped lines, orders/vehicles/reactor screens (mock)

**Rich tooltips.** Every button, check box, slider and text field in the HUD, the windows and every screen now has
a tooltip ("Title\nwhat it does"): screen tabs (`screen.TAB_TIPS`), inspector tabs, goals chapters, inventory
filter, settlers controls, colonist rows, quality chips, sliders, edge pan, Back/OK, new-colony cards, codex
search and rows, research queue, size chips, menu dish toggles, cancel batch, title menu, lost and victory
buttons. Probe `tools/ui/probe_tooltips.gd` lists any control without one.
Fixed on the way: a goals-screen error (`ch[i]` on a Dictionary) when it rebuilt.

**Clipped lines (1280x720).** Free text wraps (inspector title and subtitle, goal names, hazard place, Find rows,
dashboard alerts, goals-screen victory line); table cells and small buttons keep one line with an ellipsis and
the full text in the tooltip (colonist and visitor tables, minimap overlay name, base switcher).
Test `tools/ui/test_tooltips_clip.gd` PASS: HUD (with inspector, Find, advisor, orders, reactor), kitchen
inspector and 14 screens in a 1280x720 window: every control has a tooltip; no line cut without an ellipsis.

**Orders, vehicles, reactor (V4_DESIGN §4.2, §5), against a mock.** `ui/v4_data.gd` is the one adapter: when SIM
has `sim.vehicles` / `sim.orders` / `sim.reactors` every call goes there; else, with the mock on (`v4mock on`,
boot `v4mock=1`, tests), a deterministic mock answers with the shapes in its header; with neither, each screen
says "not available yet" (never fake data in a real game).
- **Vehicles screen** (nav rail; `ui/screens/vehicles_screen.gd`): list with charge/fuel bars; the vehicle's
  charge or fuel, range now, cargo, crew/seats, wear, cargo chips, who is on board; orders Drive to… / Explore
  area… (click a place, `main.pick_point`) / Return; out-of-range refused with the reason. **Routes** tab: each
  medium rover's route and a route builder (rover, load base, unload base, load chips).
- **Orders window** (`ui/hud/orders_window.gd`; the colonist inspector's Orders… button): a group of colonists,
  Go to / Explore / Survey (click a place), Work at (click a structure), Stay, Return, Board (vehicle list),
  Cancel. A deadly order is refused with the reason (no air on the way, radiation); "Confirm anyway" asks, then
  sends it with force.
- **Job priorities**: colonists screen tab Priorities: 8 kinds of job, 3 / 2 / 1 / – per colonist.
- **Reactor window** (`ui/hud/reactor_window.gd`) and **meltdown banner** (`ui/hud/reactor_banner.gd`): phase
  sequence normal → warning → critical → breach with the time to the next phase, temperature, coolant, fuel rods,
  power, blast radius, radiation zone; SCRAM / Cool / Evacuate, each confirmed. The banner shows while any
  reactor is past normal (critical pulses red); toasts go under it. Minimap: vehicles as diamonds, the blast
  radius of a reactor past normal.
- New icons: rover, route, orders, reactor, scram, coolant, evacuate (192). The nav rail shrinks its buttons in
  a short view (46 → 32 px) so it always fits.
- Test `tools/ui/test_v4_screens.gd` PASS (24 checks: not-available without data; mock lists; vehicle detail;
  route rules; vehicle order range; Orders button; order given, refused with reason, forced, cancelled; window
  place; priority step; banner; reactor card; phase advance; SCRAM; Cool; bounds).
- Shots (preview data): `docs/shots/ui4_v4_vehicles.png`, `ui4_v4_routes.png`, `ui4_v4_inspector_orders_button.png`,
  `ui4_v4_priorities.png`, `ui4_v4_reactor_warning.png`, `ui4_v4_reactor_banner_window.png`.
- When SIM's names land: `live()` switches each system; commands go through `main.submit` with the payloads in the
  adapter header (proposed to SIM in `docs/requests/UI-to-SIM.md`). SIM-to-UI.md has no v4 vehicle/order/reactor
  names yet (checked 2026-09-27).

**Export.** `build/web_ui` index.pck **94.4 MB** (budget 95 MB). It was 71.6 MB at the helpers milestone; my
additions this round are scripts and seven small SVG icons, so the growth is from other agents' assets. It is
0.6 MB from the budget.
## 2026-09-27 — vehicles live (SIM milestone 3), rover depot panel, Outpost Kit from cargo

- `ui/v4_data.gd`: vehicles use SIM's live `sim.vehicles.list()` and `kinds()`; rows normalised (charge and fuel
  0..1, full-tank range from the kind: rovers charge_cap / charge_per_km, hopper fuel_cap / fuel_per_hop × hop_m;
  cargo_cap; route {from, to, load, back, trips}). `vehicle_cmd()` sends the real commands (drive, return, stop,
  alight, board, cargo, route, route stop, deploy); `build_vehicle`, `cancel_vehicle`. When the game is paused the
  result is read at once and a refusal is shown with its reason (texts for every SIM code: no_driver, broken,
  no_route, moving, no_store, no_seat, no_path, kit_far, too_close_base, locked_research, busy, no_bay, …).
  `LIVE_SYSTEMS` lists what is switched: only vehicles. Orders and the reactor stay on the mock (SIM has
  `sim/orders.gd` in progress, not yet published).
- **Vehicle screen**: charge or fuel, range now, cargo x of cap, crew/seats, wear, who is aboard, why it is stopped
  (`block`); orders Drive to…, Return, Stop, Board… (the Orders group or the selected colonist), Get out; Cargo:
  Unload all, +5 / +1 load chips (stores within 85 m); **Deploy Outpost Kit…** when a kit is aboard: pick the place,
  preview with `sim.bases.check_outpost` and the 30 m reach, then `deploy_outpost` with the vehicle's cargo inventory.
- **Routes**: every vehicle's route with trips; builder with vehicle, base A, base B, "take to B" and "bring back"
  chips; Stop. With one base it says a second base is needed.
- **Rover depot**: new inspector tab **Vehicles**: the bays and what stands in each; the vehicle being built
  (parts delivered, then assembly with progress; what it waits for; Cancel with confirm); a Build card per kind
  with seats, cargo, cabin, bay, cost chips (free stock) and the research lock.
- Riders: the colonist's why box says "Riding in <vehicle>" and why the vehicle is stopped. Orders window: Board
  is live (`vehicle_board`); the other orders say they come with SIM's orders.
- Test `tools/ui/test_v4_screens.gd` rewritten on SIM's own set-up (Frontier game, depot spawned active, rovers in
  bays): PASS (live rows, screen detail, load/unload, no_driver refusal, board, Deploy button and SIM refusal
  too_close_base, routes with one base, depot tab with bays and kinds, build ordered, busy, Building section,
  cancel; orders, priorities and reactor on the mock; bounds).
- Not done: web screenshots of the live vehicle screens and the depot tab (no web command puts a vehicle or a
  depot on the map; debug commands asked of SIM). The earlier `ui4_v4_vehicles.png` / `ui4_v4_routes.png` show the
  mock layout.
## 2026-09-27 — orders live (SIM milestone 4); live screenshots with SIM's debug spawns

- `ui/v4_data.gd`: `LIVE_SYSTEMS` = vehicles and orders. Orders: `sim.orders.check(agent, payload)` preview for
  each colonist first (SIM's STE reason and `confirmable`), then `order {agents, kind, x, y | v | b | site, confirm}`;
  Cancel = `order_clear`; the current order is read from `agent.order` (kind mapped go → Go to). "Stay here" is
  sent per colonist at its room (inside) or its place (outside). Priorities: SIM's five categories
  (`job_categories()`), `set_jobs {agent, jobs}` and `{agent, clear: true}`; the cell is the colonist's own value,
  else the colony priority. Vehicle Explore area = `vehicle_explore {id, x, y, r: 150}`. The reactor stays on the mock.
- **Orders window**: Go to…, Stay at…, Stay here, Survey… (the nearest unsurveyed hazard site within 40 m of the
  click), Work at…, Return to base, Board (vehicle_board), Cancel orders. A refusal shows SIM's own text;
  "Confirm anyway" shows only when every refusal is confirmable (air margin, staying outside, radiation), asks,
  then sends `confirm: true` for those. A row shows "(risk accepted)" for a confirmed order.
- **Priorities tab**: Construction, Food, Industry, Logistics, Repair; click steps 3 → 2 → 1 → – → 3; grey =
  colony priority, bright = the colonist's own; "Colony" per row clears the colonist's own values.
- Debug commands for screenshots (`main.gd`, debug only): `simcmd <kind> <json>` (SIM's `spawn_vehicle`,
  `place_finished`, …), `orders` (opens the window with the selected colonist); `order` goes through the window
  when it is open.
- Test `test_v4_screens` PASS (31 checks; new: orders live, stay, SIM refusal with its text and confirmable,
  confirmed order with confirm, order_clear, vehicle_explore reaches SIM, five categories, set_jobs, clear).
  Finding reported to SIM: "stay" at the lander for a colonist inside it is refused with suit_range (the test
  prints a NOTE; the UI shows SIM's text).
- **Live shots** (Frontier seed 1001, SIM `place_finished` depot size L + `spawn_vehicle` medium rover, small
  rover, hopper): `docs/shots/ui4_live_depot_vehicles_tab.png` (bays with the three vehicles, Build cards with the
  research lock), `ui4_live_vehicles.png`, `ui4_live_routes.png`, `ui4_live_orders_refused.png` (SIM's suit-air
  refusal and Confirm anyway), `ui4_live_priorities.png`.
## 2026-09-27 — SIM milestone 5: tech tree, tiers, why stopped, build palette

- **Research tree** (`ui/screens/research_screen.gd`): 82 projects, 16 lanes (branches) × 5 tier columns. New
  branches get lanes, names and icons (`ui/data.gd branches()` adds `mat, nuc, veh, explore, rad, deep` until SIM
  adds them). Column heads show the research packs that tier uses (icons, tooltip names them). Nodes show pack
  chips and RP (fixed: pack count overlapped the RP at the text floor size). Bar over the tree: search (name,
  description, what it unlocks, branch; others dim to 25 %, their links dim too; Enter selects the first match
  and scrolls to it), "Can start now" filter, match count, legend (done, active, queued, can start, locked).
  Detail text wraps (the panel no longer widens).
- **Tiers** (`ui/data.gd`): `item_tier()` basic/mid/high-end (seed + recipe propagation; items made only from
  water or crops are basic; crops, dishes, water, finds, medical have none), `building_tier()` = tier of its
  lowest recipe. `TIER_COLOR` grey / cyan / gold. Icons: `Icons.item_cat` fallback to the category icon for new
  items; new icons `icat_find`, `expand`.
- **Codex** (`ui/codex.gd`, `ui/screens/codex_screen.gd`): all 72 items; the list line and the detail say the tier
  (badge); "Where it comes from" says "(needs the structure at level 2)" for `min_level`. Crafting tree
  (`ui/widgets/craft_tree.gd`): tier stripe on each card, a tier legend, columns narrow (340 → 236 px) to fit the
  pane, opens scrolled to the item, cut recipe labels end in "…" and the card tooltip gives the full text;
  "Wide view" hides the list (the metamaterial tree then fits in 1448 px).
- **Why stopped?** (`ui/why.gd`): `level_low` → "Needs level N" (fix: upgrade, or pick another recipe);
  `deposit_locked` → "Deposit locked", names the material and the research. Inspector short codes; recipe chips
  show "(L2)" and are disabled below the level.
- **Build palette** (`ui/hud/build_bar.gd`, `ui/widgets/build_card.gd`): one row per tier with a tag (Basic 11,
  Mid 6, High-end 7 in Industry); the drawer scrolls when the rows do not fit and keeps clear of the goals,
  alerts and map panels; long output names show as the icon only (tooltip names it).
- Debug commands (`main.gd`): `rsearch <text>`, `codexwide 0|1`.
- Test `tools/ui/test_tiers.gd` PASS (45 checks). All UI tests PASS; check clean; pck 77.3 MB.
- Shots: `docs/shots/ui5_tech_tree.png`, `ui5_tech_search.png`, `ui5_tech_search_reactor.png`,
  `ui5_craft_metamaterial.png`, `ui5_craft_metamaterial_wide.png`, `ui5_build_industry.png`.

## 2026-09-27 — SIM milestones 6 to 8: reactor live, dose, fog, points of interest, satellite; mock removed

- **Mock removed** (`ui/v4_data.gd`): every V4 system is SIM's (`vehicles`, `orders`, `reactors`, `explore`).
  Gone: `mock_on`, `mock_set`, `mock_tick`, the `v4mock` command and boot key, the "preview data" lines.
  Without a system (older saves) the screens say "not available".
- **Reactor** (`ui/hud/reactor_window.gd`, `ui/hud/reactor_banner.gd`): rows from `sim.reactors.list()`
  (stage ok → normal; heat 0..100 with warning 60, critical 85). Card: sequence, status line (time to the next
  stage from SIM's forecast, SCRAM countdown, cooling), heat gauge with ticks, change per s, coolant (keeps 8),
  fuel rods + time left in the rod, power, blast 60 m, zone 140 m, evacuation. Actions in a 2-column grid, each
  with a confirm: SCRAM, Restart (only after SCRAM, off at warning heat), Dump coolant (off without coolant),
  Evacuate (off while on; toast "N colonists leave; M cannot"). SIM refusals show as text.
  `reactor [scram|restart|cool|evacuate|stage <s>]` command (stage = SIM debug `reactor_stage`).
- **Dose**: colonist card badge (HIGH DOSE ≥ 250, DANGEROUS DOSE ≥ 750, RADIATION SICK > 1,000), a Dose bar to
  1,000 mSv, "Radiation now" (ground rate × room 0.1 / cabin 0.3 × research cut). Colonists list: Dose column,
  amber / red, sort puts the highest first.
- **Minimap** (`ui/hud/minimap.gd`): fog always (unexplored darkened; image remade only on `fog.rev`), new
  header buttons Explored (darker fog, legend: % explored, satellite bands, uplink) and Vehicle range (rings of
  half the range left; legend gives each vehicle's reach, "the whole map" for a full rover). Found points of
  interest (icon by kind, visited dim with a tick), satellite icon over its next band, cyan ticks for mapped
  bands, "5/16". Radiation overlay reads `sim.reactors.rad_at` (breach zones); rad and toxic zones drawn.
  Resources overlay shows surveyed deposits only.
- **Points of interest**: Find lists them (kind, "Needs anyone / on foot / a scientist", distance, what a visit
  gives, TO VISIT / VISITED); click aims the camera and pulses the tag. 3D tags (`ui/hud/poi_marks.gd`). Orders
  → Survey accepts a point of interest within 40 m (`{kind: "survey", poi}`).
- **Launch pad**: Satellite tab (in orbit: bands mapped, next band, no-uplink warning; build order progress and
  Cancel; Build satellite with cost and research lock).
- Icons: satellite, poi_wreck, poi_probe, poi_meteorite, poi_cave, poi_anomaly, poi_deposit, range, explored.
- Tests: new `tools/ui/test_v4_live.gd` (showcase_v4, debug on). `test_v4_screens` reactor step now checks
  "no reactor"; `test_tooltips_clip` without the mock.
- Finding to SIM: in showcase_v4 the comms tower and the launch pad have no power, so the satellite does not map.
- Shots (web, showcase_v4, debug=1): `docs/shots/ui6_reactor_warning.png` (coolant dumped twice, then stage
  warning: "Critical in 10:23"), `ui6_reactor_critical.png` ("Breach in 6:14"), `ui6_reactor_scram.png`,
  `ui6_fog_pois.png` (Explored overlay, 3D tags), `ui6_find_pois.png`, `ui6_range_overlay.png`,
  `ui6_launch_pad_satellite.png`, `ui6_colonists_dose.png`.
- Follow-ups in the same round: SIM added `tier` to items.json and the six branches to research.json (the UI's
  request); the UI now shows SIM's tier for every item that has one (a recipe no longer overrides it; crops get
  SIM's tier too) and `test_tiers` compares with SIM's field. Window manager: a window still at its default place
  (never dragged, no remembered place) follows a work-area change (the top bar is 62 px at load, 54 px after
  its rebuild; the inspector stayed 8 px low, `test_wm`). Colonists list: Doing 198 px, so the list has no
  sideways scroll bar at 1600×900 (`test_theme_v4`).

## 2026-09-28 — POI-find stall check, shutdown crash, critic round 22

- **POI-find stall (RENDER: one 667 ms frame).** Measured the UI's reaction (headless desktop, showcase_v4):
  fog image 2.1 ms (remade only on `fog.rev`), minimap repaint 1.3 ms, structure signature 0.1 ms, POI rows
  0.07 ms, toast 0.5 ms, Find rebuild 8 ms (only while Find is open), POI tag icon 0.17 ms. `poi_found` has no
  sound in the manifest, and every stream loads at start (no first load). Frames after `reveal_band` over the
  probe: 4-20 ms. Web (`--gpu`): the frame with the find was `sim 126 ms, hud 0 ms` (the `spikes` command). So
  the UI is not the stall. Still done: the fog image is built from bytes (LA8) in one pass, and the POI and
  satellite icons are rasterised at start (`ui/hud/poi_marks.gd`), not in the frame of the first find.
- **Shutdown crash (0xC0000005 after `tools/check_scripts.gd`).** Bisected over all 231 scripts: loading
  `presentation/models.gd` (or world_view.gd), then `ui/screens/screen.gd`, then `ui/screens/codex_screen.gd`
  crashed 6 of 6; without the `static var wide` in codex_screen.gd (a script that extends screen.gd) it exits
  with 0 (check 4 of 4). Fix: `wide` is an instance var, kept on `hud.codex_wide`. No other static var is in a
  script that extends a project script. `tools/godot.mjs` comment updated. The desktop build loads the same
  scripts, so it had the same risk at exit.
- **Critic round 22, fix 1**: screens can size to their content (`screen.gd fits_content()`, `fit_scroll()`,
  header width from the title/tab row so no tab is cut): Vehicles (both tabs) and the Priorities tab are centred
  and as large as their content; other tabs stay full. Route line plural fixed ("deliveries").
- **Fix 2**: tech-tree node text at 12 px or more through the text floor (state word, RP, pack counts 12; names
  12/13), locked nodes brighter (name and state TEXT_2, pack icons 75 %).
- Tests: `test_v4_live` +4 checks (Routes and Priorities fit, header not cut, Colonists tab full again).
- Shots: `docs/shots/ui7_tech_tree_12px.png`, `ui7_vehicles_fit.png`, `ui7_routes_fit.png`,
  `ui7_priorities_fit.png`, `ui7_colonists_full.png`.

## 2026-09-28 — every lock explained; steady alert entries; the rail as one strip

- **Locks (Paul stuck on the workshop).** Root cause on the UI side: `ui/data.gd building_unlocked` checked the
  colony stage only when research was absent, SIM checks it always, so a stage-locked card looked unlocked
  and placement then said only "This structure is not unlocked yet." Now `data.lock_info(def, size)` uses SIM's
  `sim.place.lock_info` (text with progress) and adds the card line: "Needs stage Stable outpost (safe
  reserves 0.0/1.0 days)" (first unmet condition) or "Needs research: Rover Parts" (+ unmet prerequisites in
  the full text). `data.stage_conditions(i)` reads the stage rules as sim/metrics.gd.
  - Build card: lock icon + the reason on two lines where the output and size chips were; tooltip and the
    click toast have the full text. Drawer line: "N locked (the card says what unlocks it …)".
  - Placement hint: the full requirement (wraps at 520 px).
  - Codex structure entry: "How to unlock": the stage (reached, or its conditions with ✓/→ and values now),
    the research as a link, "Unlocked: you can build it."
  - Advisor: an item needed now (a repair, maintenance, a blueprint's materials) with none in the colony:
    maker locked → "No spare parts, and the workshop that makes it is locked. To unlock it: <SIM text> Or buy
    some from a trader ship or salvage …"; maker unlocked but not built → "build a workshop …".
  - Test `tools/ui/test_locks.gd` (54 cards, 35 locked, every locked card has a line and a full text; UI and
    SIM agree on every card; stage and research lines; hint; codex; advisor both cases).
- **Flickering "Output blocked".** Two UI causes found and fixed; one SIM-side behaviour noted.
  1. Alerts panel fit: it dropped its last card at the minimap and took it back with 170 px free; a card taller
     than that came back, overflowed and left again. Now a card comes back only when the room it needs is
     free (mean card height; the cut card's height for 5 holds) and not within 6 s of a cut; tight mode the
     same (the height it saved). Counter `max_changes`.
  2. Alert gate: output blocked (a known flapper) was held only 10 s after its FIRST clear, so the first flap
     made it leave and come back. It is now held 180 s from the first clear (as after a flap).
  - SIM side (for SIM): in showcase_v4 the `output_blocked` issue itself comes and goes while the mine's buffer
    is full part of the time (seen at 60 s, gone at 120 s, back at 180 s): the mine runs a batch between.
  - Test `tools/ui/test_alert_steady.gd`: 600 s, a powered mine in showcase_v4 with its buffer kept full,
    emptied by 4 every 45 s and refilled 20 s later: the entry never leaves the gate list, never leaves the
    screen while the set of alerts is the same, the list never reorders, the card count does not change in
    570 s (and settles with the goals open).
- **Right rail** (`ui/hud/nav_rail.gd`): one glass strip in the HUD metal frame (rivets), rail buttons with the
  metal rim and bevel (shared baked styles), hover: brighter glass + cyan inner glow + brighter rim; selected:
  lit glass, strong glow and a cyan accent bar on the left; engraved seams group screens | vehicles, codex |
  advisor, find, overlay | menu. Shots `docs/shots/ui8_rail_day.png`, `ui8_rail_night.png`.
- Shots: `ui8_build_locks.png`, `ui8_place_hint_lock.png`.

## 2026-09-28 — storage everywhere (Paul: "show if they are full … and what is stored")

- `ui/storage.gd`: holders of a structure (input, store, output, supplies), per holder used / capacity / %,
  incoming, FULL (used >= capacity), level (amber from 80 %, red from 95 %), items with reserved units and the
  time to the next spoiled unit (SIM `sim.inventory.contents(b).spoil`; none in cold storage or input buffers).
- Inspector: a Storage section on every structure that holds items. Storehouse, cold storage and the lander
  open on a Storage tab (the inspector now starts a new structure on its first tab); other holders show it
  on Overview (and on Output for machines, in place of the old buffer lines). Per holder: title, "16 / 16
  (100%)", FULL badge, bar, "N more on the way in", one line per item (tier stripe, icon, name, reserved,
  spoils in m:ss, amount; the tooltip has free/reserved). A FULL badge in the header when a store or an
  output buffer is full. Vehicles screen: cargo fill bar and FULL.
- Inventory screen, tab "By structure": SIM `sim.inventory.by_structure(base)` rows (structures, vehicles,
  "Carried", "On the ground"): base, fill bar and %, FULL, top 4 items; sort fullest first or by name; base
  filter; click a row: the camera goes there and selects it.
- Map FULL tag: RENDER's (RENDER-to-UI 2026-09-28). Asked RENDER to use `contents(b).full` (100 %), not 98 %,
  so the tag and the panels agree. The UI draws no world tag.
- **Web fault found and fixed:** the first switch to the new tab made the web build fault ("memory access out
  of bounds"): the inventory screen's `_update()` still wrote the freed item-row labels of the last tab. The
  tab now drops them. Found by bisecting in the web build (desktop showed nothing).
- The shutdown crash came back while I bisected with a temporary `static var` in inventory_screen.gd (it
  extends screen.gd): the same cause as on 2026-09-28. Removed; check exits 0 again.
- Debug read command `storage <def>` (used/capacity/full per structure) for screenshots.
- Test `tools/ui/test_storage.gd` (showcase_v4): all 19 holders show a Storage section whose totals, FULL
  and item lines match SIM; stores open on Storage; a full machine shows "Output 12 / 12 (100%)" + FULL and a
  header FULL; By structure lists 16 rows fullest first with the full machine flagged, filters by base,
  sorts by name, a click selects; the last tab's rows are dropped; vehicle cargo shows its fill.
- Shots: `docs/shots/ui9_storage_storehouse.png`, `ui9_storage_full_machine.png`, `ui9_storage_by_structure.png`.

## 2026-09-29 — the game drives the web loading screen

- `presentation/main.gd` (web only): `_ready` first sets `window.__fh.loaded = false` and reports 0.05
  "Loading the colony" (so the shell waits for the game's own end mark, not its 1.5 s guess). Each frame
  `_web_load_step()` reports "Building the planet" (0.30-0.55, first frames) and, while RENDER's load cover
  warms the shaders, "Preparing graphics" (0.55-0.95 from the cover's hold time and fast frames). When the
  cover lifts (the first real frame) it sets `window.__fh.loaded = true` and calls `__fh_load(1)`; the shell
  fades out. Without a cover it ends after 240 frames. Desktop: nothing.
- Check (`tools/shoot.mjs --gpu --throttle 150000 --early …`): 5.5 s download 66 %, 6.3 s "Preparing graphics"
  95 %, 6.9 s 99 %, 7.2 s the title screen, with no black frame between. Sheet: `docs/shots/ui10_loader_sequence.png`
  (order of the tiles: 5.5, 6.3, 6.6, 6.9, 6.0, 7.2, 7.5, 7.8 s).

## 2026-09-29 — "OUT OF REACH" explains itself

- `ui/why.gd reach(hud, b)`: SIM's `sim.agents.reach_info(b)` (why ok | no_air | no_access | no_path | too_far,
  text, walk_m, straight_m, reach_m, lock_name) → one line, the reason and a concrete fix:
  - too_far: "Walk from Airlock 2: 180 m, suit reach 120 m" / fix "Build an airlock closer: within 120 m on
    foot, joined to rooms with air." + "Or research Extended Suits: suits hold more air." (the next suit-air
    research not done);
  - no_path: "No walking path from any airlock with air" + SIM's text (straight-line metres) / "Clear the way:
    steep slopes, crevices, boulders or structures block the path. Or build an airlock on this side.";
  - no_air: "No airlock has air" / "Join an airlock by a corridor to rooms with air, and keep the oxygen plant
    powered."; no_access: "No open ground round it" / "Clear the way …";
  - ok (the block is older than the check): "In reach: 18 m from Lander, suit reach 142 m" / "Nothing to
    build: wait, or raise its priority."
  A fallback (straight line to the nearest airlock with air) runs on a SIM without reach_info.
- Used by "Why stopped?" (plans and active structures), the Materials line of a plan, the Construction line,
  and the inspector's OUT OF REACH / TOO FAR badge tooltip (reason + "Fix: …"). The 3D tag is RENDER's.
- Test `tools/ui/test_reach.gd` (Frontier: a plan 250 m out; a copy next to the lander; SIM rows for no_path
  and no_air; the badge tooltip and the Materials line).

## 2026-09-29 — v5 — PILOT: "The Regolith Rag" window

- `ui/hud/rag_window.gd` (window manager, id "rag"; key J; nav rail button; debug `rag [n]`, `ragscroll px`):
  a tabloid page in the glass-and-metal window. Newsprint paper (tiled noise texture made at run time, no
  file), red masthead band "THE REGOLITH RAG" with issue, day, price; black strap with SIM's tagline; the
  lead story (kicker chip, huge condensed headline, 540×405 photo with a black caption bar, byline, drop-cap
  body); stories in rows of three columns with rules; boxed columns THE DUST-UP (gossip), COUPLE WATCH,
  FEUD WATCH; the RAG POLL box (big %, change, bar, commander); SMALL ADS (4 boxed ads; ship arrivals from the
  traffic forecast when SIM gives fewer); the SERIOUS NEWS strip in the game's own glass style and STE text.
  Back issues: the header's list (SIM keeps up to 30). Every name is a link: click selects the person
  (follow comes with the follow HUD).
- Fonts (OFL, +0.13 MB): Manrope 800 condensed to 80 % (`Fonts.rag_size(px)`, per-size variations so the weight
  and the tight spacing hold), Source Serif 4 400 / italic / 600 for the newsprint.
- `ui/widgets/rag_photo.gd`: RENDER's `view.photo(agents, place, pose)` when it lands; until then a grainy
  flash-shot placeholder with two silhouettes posed by the pose hint.
- `ui/v5_data.gd`: v5 adapter; SIM's `sim.social.rag_issues()` is live (stub) and mapped by `norm_rag()`;
  `ui/mock_rag.gd` (preview issues) is only used when SIM has no social system.
- Version 5.0.0 in project.godot (the title menu reads it).
- Test `tools/ui/test_rag.gd` PASS (16): every page part, names link and select, every issue inside the view.
- Shots: `docs/shots/ui11_rag_top.png`, `ui11_rag_middle.png`, `ui11_rag_bottom.png`, `ui11_rag_back_issue.png`.
- Not tested: the web build at 1280×720 (headless only); the photo from RENDER (not there yet).
- Next: follow HUD, personnel file, org chart, social tab, unrest, academy, housing, floors, palette, codex, eggs.

## 2026-09-29 — v5 — critic round 25 fixes (Rag) and the people UI

Critic round 25 (regolith_rag 0.71), all 8 UI points:
1. A window that covers the alerts panel folds it (`alerts_panel.gd fold_set`, used by the window manager).
2. At 1280×720 (logical height < 800) the Rag is compact: masthead 46 px, lead headline fit to 2 lines,
   the photo starts above the fold. Checked in the web build with `shoot.mjs --size 1280x720`.
3. Newsprint grain and fibres, halftone dots on the photo, a double rule under the masthead.
4. The right column is filled: quote of the day, INSIDE TODAY with page numbers, "THE RAG KNOWS."
5. The poll trend is in words: "▲ UP n POINTS", "▼ DOWN n POINTS", "— NO CHANGE".
6. Name links: pointing-hand cursor and a tooltip on hover.
7. Three layouts by story mix: standard, special edition (black masthead, red strap, full-width photo),
   quiet (small photo). Debug `raglayout <standard|special|quiet|auto>`.
8. Small ads: 4 in each issue (SIM ads, ship arrivals, house ads).
Shots: `docs/shots/ui12_rag_1600_top.png`, `ui12_rag_1600_bottom.png`, `ui12_rag_special.png`,
`ui12_rag_quiet.png`, `ui12_rag_1280_top.png`, `ui12_rag_1280_bottom.png`. Test `test_rag.gd` PASS (20).

People UI (V5 §3–§7, §10), all in the v4 window manager and inside the view:
- **Follow view** (RENDER's camera): key V / Shoulder / Follow buttons; Tab next, Esc exit. Follow card
  `ui/hud/follow_hud.gd` (name, rank, mood, satisfaction, doing, talking with, last 3 lines; File, Next, Switch,
  Exit). The rest of the HUD dims to 0.28; the inspector stays hidden; the time controls stay.
- **Bubble style**: `ui/theme/bubble_style.gd` → `view.bubbles.ui_style()`.
- **Konami code** in the follow view: egg "dance" (`egg` command, `view.egg_dance` if present); the device
  profile keeps found eggs; toast "SECRET FOUND".
- **Personnel file** `ui/hud/person_window.gd` (id "person"): File tab (portrait, facts, satisfaction with 9
  parts and reasons, attitude, skills with levels, recent lines), Social tab (relationship web + list; an
  unknown crush is hidden), Review tab (4 grades, 9 actions; each with its predicted effect on two lines,
  green/red, "(estimate)" when it is the UI's table; confirm first; SIM's answer or "not yet" shown).
- **Crew screen** `ui/screens/crew_screen.gd` (key U, nav rail): Org chart (commander + 5 departments;
  drag a person onto a slot → confirm → `appoint`), Housing (every home, beds, "wants family/executive" in red;
  drop → `set_home`), Academy (courses, students, enrol form → `enrol`).
- **Unrest**: top-bar KPI (stage, value, causes in the tooltip; click opens Crew); banner
  `ui/hud/unrest_banner.gd` at protest, strike and riot (demand, 7 responses with confirm → `unrest_response`;
  it pulses in a riot). Debug `unrest <stage|off> [value]` (UI view only).
- **Floor selector** `ui/hud/floor_selector.gd` (multi-storey structure selected; PgUp/PgDn). The cutaway waits
  for RENDER's `set_view_floor`.
- **Palette**: Civic tab (security office, jail, super dome); XXL / XXXXL labels in gold with a size tooltip,
  kept on a locked card under the lock reason. `Data.size_word()` in the hint, inspector and find window.
- **Codex**: People tab (ranks, skills, satisfaction, attitude, discipline, unrest, security, relationships,
  follow) and found eggs only.
- Requests: `docs/requests/UI-to-SIM.md` (7 commands, `people.predict`, `education.students`, unrest finding),
  `docs/requests/UI-to-RENDER.md` (`set_view_floor`, `egg_dance`, `photo`).
- Test `tools/ui/test_v5_people.gd` PASS (34).
- Shots: `docs/shots/ui13_person_file.png`, `ui13_person_social.png`, `ui13_person_review.png`,
  `ui13_follow_hud.png`, `ui13_crew_org.png`, `ui13_crew_housing.png`, `ui13_crew_academy.png`,
  `ui13_unrest_protest.png`, `ui13_unrest_riot.png`, `ui13_palette_civic.png`, `ui13_codex_people.png`.
- Not tested: drag and drop with a real mouse (the test calls the drop); the floor cutaway, the dance and the
  photo (RENDER APIs not there); every SIM command answers "not yet" (SIM has no `cmd_*` yet); unrest from SIM
  does not reach protest (finding sent), so the banner shots use the debug stage.
- Finding: SIM's unrest stub peaks at about 37 with every colonist unhappy.
- Suite: 21 UI tests, 20 PASS. `test_ships_ui` fails 1 check (landing pad not powered after SIM's 18:04–18:31 changes; finding sent). `test_wm` failed once: the alerts panel had become a snap target; it now folds but is no snap target (PASS).
- Also: the inspector stays hidden in the follow view (test check added); the review actions show the effect on a second line (green/red); a locked XXL / XXXXL card keeps its size label.

## 2026-09-29 — v5 — critic rounds 29 and 30 (follow view, social UI, Rag)

Rag (round 30: 0.75):
- Special edition: the lead headline is 2 lines at most (as on the other layouts); test checks the laid-out
  line count on all three layouts.
- Quiet day: the "SLOW NEWS DAY" kicker; a smaller lead (46 px headline, 300 px photo); the gossip column
  takes 6 items; a WHO SAID IT? puzzle box (3 real lines from colonists, the names in another order, the
  answers at the foot). An issue with a cold lead (heat under 0.25) and 2 stories or fewer is quiet too.

Social UI (round 30: 0.71):
1. Reading glass (about 88 %) behind lists, tables and graphs: `ui_theme.gd` style `reading_hud`; used by
   the personnel file and the build drawer (every palette tab, Civic included).
2. The personnel file opens in the inspector's place (top right); the inspector hides while the file of its
   person shows. The first-frame width (822 px) is fixed: the file settles to its content (540 px) and is
   placed again.
3. The discipline confirm has headed lines: ON <PERSON> (attitude, satisfaction), ON OTHERS (the effect and
   who sees it: friends and partner by name), RISK, and UNFAIR (red) when the person's attitude is 0 or more
   (the UI's rule until SIM's `predict` gives `unfair`). Debug `person ask <action>` shows it.
4. Unrest banner: its own frame by stage: protest amber, strike orange, riot red on a dark red body with a
   beating border and glow. A riot shows "DAMAGE: … · INJURED: …" (SIM fields `damage`, `injured`; "not
   reported yet" until they exist).
5. Every response shows its effect under the button (UI estimate, marked so in the tooltip).
6. Crew: 13 px body text on the person chips (not the 10 px mono chip font), 30 px rows, a mood face per
   person (new icons `mood_0` .. `mood_4`); the department columns reach the bottom (the Crew slot fills);
   Housing adds beds by quality (beds, used, free) and "Waiting for a better home"; Academy adds the crew's
   skill table (levels 1-5 by colour).
7. Satisfaction: the 9 parts in one column, each on a 0-100 track with the 50 mark, worst first, with its
   reason beside it.

Follow view (round 29: 0.67): the follow card has the inspector's rows (Health, Fed, Water, Rested) and
its mood face; the inspector stays closed. Toasts move to the top edge, centred, two at most, while following.

- Tests: `test_v5_people.gd` PASS (45), `test_rag.gd` PASS (22).
- Requests: `UI-to-SIM.md` (unrest `damage`/`injured`, `response_effect`, `predict.unfair`).

## 2026-09-29 — PAUSED (Paul)

- Done: every critic round 29/30 UI fix above is in code; `check` clean (258 scripts); `test_v5_people` PASS (45),
  `test_rag` PASS (22), `test_window_bounds` PASS; the other suite runs were stopped for the pause.
- Half-done: no web export and no shots of round 30 yet (`build/web_ui` is the older build). The steps file is
  ready: scratchpad `r30shots.json` (ui14_rag_special, rag_quiet, person_file, person_social,
  discipline_confirm, follow_card, unrest_protest/riot, crew_org/housing/academy, palette_civic).
- Next: run the rest of the UI suite (test_wm, test_theme_v4, test_tooltips_clip, test_v4_screens, test_bases_ui,
  test_find, test_locks), export to build/web_ui, take the ui14 shots, view them, report to the coordinator.
- Open outside UI: `test_ships_ui` fails 1 check (landing pad not powered after SIM's 18:04–18:31 changes; in
  UI-to-SIM.md).
