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
