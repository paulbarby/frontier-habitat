# Critic round 42 — subject `playthrough` (new): first game as a new player, and showcase_v5 at speed 4

Date: 2026-10-04 · Critic · Build `build/web_v5play3` (e9b1d35, pck 186.2 MB) · headless Chrome, `--gpu`, 1600x900.
Rubric method: `v5_rubrics.md` §1. Pass >= 0.65. Shots: `art/critic/r42/playthrough/` (p* = new colony, s* = showcase, z* = crops).

## Method

- New colony: title screen → New colony → First landing, dry, standard, hazards normal → Land the colony.
  Clicks were real mouse events. Structures were placed with `place` (the same command as a click) and joined
  with the corridor/cable tool and a real click on the target. Time: speed 1 for the first day, then speed 4.
  Played to day 11 (about 63 game minutes at speed 1). Console logged for the whole run.
- Showcase: `loadurl showcase_v5.fhsave`, speed 4, 10.5 real minutes (day 19 → day 21), console logged.
  A second run with `tools/shoot.mjs --console` (3 min at speed 4, build bar opened for 3 s).
- The machine was shared with other agents (Godot and Chrome processes). Treat fps as indicative.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| playthrough | 0.58 | 0.56 | 0.70 | **0.61** | **FAIL** |

Appeal has the cap 0.60: inspector values are cut off and cannot be read (finding 5).

## What works

- Title → New colony → landing works with real clicks. The planet, map, difficulty and hazard cards are clear.
- The goals card tells you what to do first, with a tip under each goal. Chapter 1 (Touchdown) was complete on
  day 2, 13:43 game time. Each goal gives a toast and a supply pod.
- Every structure I placed was built. Corridors and cables join on the first click. Refusals give a clear reason
  ("Overlaps another structure", "The lander has no corridor port").
- The advisor (N) names the problem and the fix in most cases (power at night, research, storage full).
- New colony at speed 4: 54–60 fps, effective speed about 3.7x. No deaths in the new colony (8 of 8 alive on day 11).
- Showcase: 0 deaths in 2.5 game days (colonists screen "0 deaths"); living people 134 → 140 (ship arrivals).
- No script error in 10.5 minutes of showcase play while the build bar stays closed.
- The goals screen (G), research screen (T), inventory (I), dashboard (C) and the Regolith Rag (J) read well.

## Findings (most important first)

| # | sev | owner | what | where / how to see | fix |
|---|---|---|---|---|---|
| 1 | major | SIM | Day 4: all 8 colonists starve with food in the lander. Alert: "16 units of food exist, but they cannot reach it. Do: Check that food is in a room with air". No goal, tip or alert names the fix. The fix is a storehouse: carriers then move the lander cargo; starvation stopped 1 poll after the storehouse was done. | p22, p24, poll log day 4–5 | Add "Store the cargo: a storehouse joined to the base" to chapter 1, or let suited people eat from the lander until it is empty. Change the alert action to "Build a storehouse joined to the base. Carriers move the lander cargo there." |
| 2 | major | UI | `ui/widgets/build_card.gd:228` formats a bool with `%d`: `"String formatting error: a number is required."` about 45–60 times a second while any build tab is open. 7,909 errors in one session; 136 in 3 s on the showcase. The cost-colour refresh signature breaks with it. | open any build tab; console | `sig += ":%d" % int(free >= int(cost[res]))` |
| 3 | major | SIM | Kitchen output blocked from day 5 while the storehouse held 17–62 of 80 and 2–6 people were idle. The hint says "Build a storehouse or free some carriers" (a storehouse exists). Later the S storehouse fills with lander steel and dishes have no place: Food supply (2 days) stays at 0.5–1.0 day to day 11. | p27_food_*, p30, p36_run_11 | Carriers move dishes before raw cargo; or the kitchen and mess keeps a dish buffer that feeds people directly. Make the hint name the real cause (full storehouse, wrong item class). |
| 4 | major | RENDER | Over-the-shoulder on a sleeping person: the camera is inside the bunk. Half the view is a yellow blanket, the feet are at the lens, another body is overhead. Breaks DoD 1 "no body through the camera". | p21 (`agent 0`, `shoulder`, Asha Verrin asleep, day 4 16:57) | For a lying person use a fixed high side view of the bed; clip-test the camera against the bed and bodies. |
| 5 | major | UI | Inspector values are cut at the right edge when the scroll bar shows: "Doing Id", "Carrying nothi", "Work speed 10", "Network energy 17.6 / 2", "Work priority 1 of". | p17, z17_inspector, p30 | Reserve the scroll-bar width; let the value column shrink the bar, not the text. |
| 6 | major | SIM | Showcase at load: red alert "The lander air has ended. 3 people have no other bed" with 36 free beds. The action ("Finish an airlock, a habitat and an oxygen plant") is wrong on day 19. The alert counts people with bed -1 as lander sleepers (`sim/alerts.gd:213-224`). | s02 advisor | Give the 3 people free beds; count only bed == lander; use a separate "no bed" alert. |
| 7 | major | SIM | Showcase: "Airlock 4: 5–7 people wait outside; the lowest suit has 44–69 seconds of air" repeats for 2 game days. News also: "1 colonist is starving. 1650 units of food exist, but this colonist cannot reach it." | s10_run_09/11/14, z22_showcase_starving | Add a second airlock to the showcase group; find the person who cannot reach food (path or room access). |
| 8 | major | RENDER | Showcase at speed 4: 10–14 fps, down to 2–5 fps during the solar flare and wind storm; effective speed 2.4x; the clock shows "SLOWED: 2.0x real speed". New colony at speed 4 holds 60 fps. | poll log, s10_run_19 | Profile the showcase at speed 4 with storms; cap sim steps per frame earlier or cut weather/particle cost. Re-measure on an idle machine. |
| 9 | minor | UI | The day number changes at 06:00, not midnight: "DAY 6 00:38" comes after "DAY 6 13:51" (`time_panel.gd:101-103`). | p28 vs p27_food_11 | Show the day from the colony clock (change at 00:00). |
| 10 | minor | UI | "Sunset in 2:43" is game minutes:seconds next to a 24 h clock; it reads as 2 h 43 min. | any HUD shot | Show "Sunset 20:24" or "in 6 h 30 min". |
| 11 | minor | UI | News doubles every event: "Goal complete: X. Reward…" and "Goal done: X. Supply pod…"; "Award: Night Owl" and "BRONZE MEDAL: NIGHT OWL"; chapter twice. News badge 40 by day 3. Advisor doubles food ("Food for 0.9 days remains…" and "Food for 0.9 days."). | p15, p13_run_* | One news line per event; one advisor line per cause. |
| 12 | minor | UI | Advisor: "3 childs have no work. Build structures that need a child…" (`ui/advisor.gd:63-75`). | s10_run_19 | Skip role child (and other non-working roles); use the plural name. |
| 13 | minor | UI | Find results: the wrapped third line ("district · size M") runs into the next row's title. | z22_find_rows | Row height from content, or one line with ellipsis. |
| 14 | minor | SIM | Showcase ships stale plans that never build: "Corridor 20/19 cannot be reached on foot within suit range", "Habitat 8 … too far from an airlock". Permanent alerts from load. | s02, s24 | Remove or finish those plans in the showcase save. |
| 15 | minor | RENDER | Title screen: world labels ("cave", "… field") show through the logo. | z01_title_labels | Hide world labels while on the title. |
| 16 | minor | UI | New colony screen preselects the 2,560 m Frontier map; the card next to it says First landing is "Good for a first colony". | p02 | Preselect First landing when the profile has no game. |
| 17 | minor | UI | Goals card: the last tip line is cut by the card frame; progress numbers touch the right edge. | z05_goals | Add bottom and right padding. |
| 18 | minor | ART-HAB | Missing `Anchor_Service` in habitat, kitchen, greenhouse S/M, storehouse, oxygen plant, research lab, airlock; lander has no `Anchor_Stand_*`/`Anchor_Bed_*`. People use a ring fallback. | console log | Add the anchors. |
| 19 | minor | RENDER | Reward supply pods (white body, orange top, grey petals) read as suited people at the game camera; 8 of them ring the lander on day 3–4. | z17_people | Crate shape or a parachute; a pod marker. |

## What a new player does not learn from the game

- That the lander cargo must go to a storehouse (finding 1).
- Why contentment falls from 70 to 45 in 4 days. The only hint is "same dish every time".
- That the S storehouse fills with lander steel and then blocks the kitchen.

## Not tested

- Frontier map (2,560 m) as a first game; cold and airless first games.
- The V-key path to the follow view (I used the `shoulder` command).
- A death in the new colony: nobody died, because I built the storehouse on day 4.
