# Critic r42 — ui_layout

Date: 2026-10-04 · Critic · Build `build/web_v5play3` (e9b1d35, pck 186.2 MB) · Rubric `docs/critic/v5_rubrics.md` ·
Spec `docs/UI_PANELS.md`, V5_DESIGN §15.6, §15.8 · Pass ≥ 0.65.

## Evidence

- 128 headless shots and 27 crops (`tools/shoot.mjs --gpu`), save `showcase_v5.fhsave`, in `art/critic/r42/ui_layout/`.
  Steps: `art/critic/r42/ui_layout/mk.mjs`. Logs: `log_game_1920.txt`, `log_game_1280.txt`.
- Sizes: 1920x1080 and 1280x720, interface scale 80, 100 and 140 %. Title screen at both sizes and scales.
- Note: at 1920x1080 the logical view is 1600x900 (canvas scale 1.2). So the 1920 shots are the 1600x900 layout.
- `z_*.png` files are crops and zooms of the shots.

Not tested: real mouse hover and clicks (tooltips, drag), the tab mute button, the Notifications modes in play.

## Score

| subject | consistency | appeal | style | score | result |
|---|---|---|---|---|---|
| ui_layout | 0.62 | 0.58 | 0.72 | **0.64** | **FAIL** |

Appeal cap 0.60 applies: text a player must read is not shown at 1600x900, 100 % (personnel file, finding 1).

## What works

- Default play view, 1920 and 1280: the centre is clear. The dock is a left column above the minimap. One urgent line.
  Three pop-ups stack above the dock (`g1920_06_popups`).
- Dock tabs: names in 3 x 2 at 100 %, icon + count at 140 %. The count colour shows the most urgent item.
  Minimise, Pin and Close work. Close keeps the urgent line (`g1920_03_dock_min`, `g1920_05_dock_closed`).
- Settings: Notifications lists 14 types with Pop up / Badge only / Off and a clear rule text. Interface scale
  slider 80–140 %. Keys card in two columns (`g1920_07_settings_a`, `_c`).
- Build palette: one strip at the bottom; its top is at 80 % of the height. Tier labels; locked cards give the
  reason. A picked tool folds the strip; one small hint panel shows the size, the keys and "Valid spot". Remove
  asks in the same panel (`g1920_08_build_civic`, `g1920_09_tool_habitat`, `g1920_09_tool_remove`).
- Inspector at 1920: habitat, lab upgrade and dome venues are clean and readable.
- Colonists and Priorities tabs: same header, rows, well and side card. Colony default row with gold frames.
- Crew org chart reads as a command board. The HR tab shows the effect of each answer before the choice.
- Title: What's new (14 lines) reads at both sizes and scales. How to play, People: complete STE topics.
- Follow view: card top left, HUD dim, dock folded, urgent line bright (`g1920_30_follow`, `g1280_30_follow`).
- One glass-and-metal frame language on the dock, cards, inspector, side windows, full screens, title and Rag frame.

## Findings (most severe first)

| # | sev | owner | what | where | fix |
|---|---|---|---|---|---|
| 1 | major | UI | Right-quarter windows clip text to zero width. Personnel file: no "Satisfaction" and "Attitude" headings, the "Needs improvement" button is blank, effects cut ("attitude +8, satisfa"), "Captain of F", the satisfaction value and reasons are off the window. Advisor: group titles missing, lines cut mid-word ("The fab nee"). At 1280/140 the file header is "M / Ca". | `g1920_12_person_file`, `_review`, `z_g1920_person`, `z_g1920_advisor`, `g1280_20_s14_person`. Cause: `ui/wm/quarter.gd` `relax()` sets `clip_text` on labels over 6 and buttons over 10 characters; minimum width becomes 0. | Wrap headings and long labels; let buttons wrap in their flow row; never clip a label under its text width or 24 px. Test: every visible Label or Button in advisor, Find, Orders, Reactor, personnel file shows at least 80 % of its text at 1600x900 and 1280x720, 80/100/140 %. |
| 2 | major | UI | Orders opens exactly on top of the person inspector. The inspector bars and text show through the glass under the buttons. The second button column is cut ("Stay", "Surv", "Medium rover 1 ("). | `g1920_13_orders`, `z_g1920_orders`, `g1280_13_orders` | Open Orders as a tab of the inspector, or stack it under or left of the inspector. Use the dense reading glass. No window opens on the rect of another open window. |
| 3 | major | UI | Full screens opened without an argument show no active tab: How to play, Codex, Dashboard, Colonists. | `z_g1920_screen_tabs`, `g1920_14_colonists`, `g1920_17_help` | `ui/screens/screen.gd` `_ready()`: set `tab = tabs[0][0]` before `_hdrer()` builds the buttons. |
| 4 | major | UI | Fixed font sizes defeat the 12 px text floor. Dock tab names: 11 pt set every frame (`panel_manager.gd:660`): 6 px glyphs at 1280x720/80 %. Priority cells: 12 pt (`colonists_screen.gd:517`); "CONSTRUCTION" cut to "ONSTRUCTIO". | `z_g1280_s80_dock_4x`, `z_g1280_s80_prio_3x`, `z_g1280_dock_native3x` | Use `P.fs()` for these sizes, or let `ui/text_floor.gd` own them. If two rows of named tabs do not fit, use icon + count. |
| 5 | major | UI | 1280x720 at 140 %: the build strip lies over the minimap and under the inspector; the credits sit under the time panel; inspector values are cut ("1", "13"); the dock body is about 160 px and the request buttons are out of view. | `g1280_20_s14_build`, `z_g1280_s140_topbar`, `g1280_20_s14_requests` | Place the strip between the minimap and the inspector. Drop or shorten top-bar items before they meet the time panel. Add 1280/140 to `test_panels` for these rects. |
| 6 | major | UI | Colonists window tabs do not share one layout (Paul, 2026-10-03). Visitors has no side card and a smaller header. Each SHIP cell is cut while the right quarter is empty. The tab strip moves about 370 px between tabs. | `g1920_14_visitors`, `z_g1920_tabs_all` | Give Visitors the same side card slot (ships now and next), the same header style and column widths. Fix the tab strip position (do not let the subtitle push it). |
| 7 | major | UI | The floor selector lies inside the centre zone: 1920 x 1315–1430, y 400–685; 1280 x 850–948, y 240–470. | `g1920_10_insp_dome_venues`, `g1280_20_s14_insp` | Put the floor chips in the inspector header, or on the right rail. Add the selector to the centre test. |
| 8 | major | UI | Find results overlap: the wrapped subtitle "· size M" prints over the next name. "Mark" is cut to "Mar" at 1280. | `z_g1920_find_overlap`, `g1280_11_find` | Let the row height follow its content, or cut the subtitle to one line with a tooltip. |
| 9 | major | RENDER | World POI labels ("meteorite field", "cave") draw through the title logo. | `z_t1920_title_ghost`, `t1280_00_title_s140` | Hide `fx_explore` labels while the title screen shows. |
| 10 | minor | UI | Dock cards repeat their title: card bar and module head say the same ("ALERTS 2 CRITICAL" twice; "HAZARD FORECAST / HAZARDS NO EVENT DETECTED"; "SHIPS / TRAFFIC"). Long names are cut ("TOURIST LI..."). | `g1920_02_tab_1_alerts`, `_2_events`, `_3_traffic` | Hide the module head inside a hosted card. |
| 11 | minor | UI | Request card: body text has no left padding; a long name wraps in the header and the next card cuts it; Skip and Dismiss carry the same check icon as the yes answer. | `z_g1920_requests`, `g1920_15_crew_hr` | 8 px body margin; one-line header with a tooltip; a neutral icon for Skip and Dismiss. |
| 12 | minor | SIM | Party offer text: "Someone" / "the colony set a record on the arcade" (lowercase start; `sim/party.gd:347`). The effect says "1 to 3 minutes" next to a "2 hours" choice (`sim/party.gd:323`). | `z_g1920_requests` | Name the person or write "The colony"; use game hours in the effect text. |
| 13 | minor | UI | News keeps the start-up colony's messages after a load ("Seed 1001, dry world. The lander is down..."). | `g1920_02_tab_5_news` | Clear the feed on load. |
| 14 | minor | UI | Pop-up Pin, Minimise and Close are about 10 px, dim grey. | `z_g1920_popups`, `g1920_06_popups` | 16 px icons at text contrast. |
| 15 | minor | UI | The Rag window covers the right part of the dock and cuts the urgent line and pop-ups. | `g1920_16_rag` | Open the Rag right of the left column, or as a full page with a dim. |
| 16 | minor | UI | Venue goods show a coloured dot and a number with no item name ("● 9"). | `z_g1920_venues_floor` | Show the item icon and name. |
| 17 | minor | UI | What's new and the loader tips do not name job priorities or the build strip (DoD 5). Settings has no "All roofs off" toggle (§15.5). The bottom title line is cut at 1280/140. | `z_t1920_whatsnew`, `g1920_07_settings_a`, `t1280_00_title_s140` | Add the rows and the toggle; keep the footer inside the view. |
| 18 | minor | RENDER | Status tags overlap and cut each other ("OUT OF REACH" twice). | `g1920_10_insp_lab_upgrade` | Declutter overlapping tags. |
| 19 | major | RENDER | Outside this subject. Follow view on a sleeping person: the camera is at the hip; only legs and a yellow bed block show. | `g1920_30_follow`, `g1280_30_follow` | Framing rule for lying poses (head and torso in frame). For the follow_view critic. |

## To reach 0.80

Fix 1 to 8. They have few root causes: `quarter.relax()`, the screen tab order, fixed font sizes, and the
placement of Orders, the floor selector and the build strip at 1280/140. Then pass the glass over the narrow
windows again at 1600x900.
