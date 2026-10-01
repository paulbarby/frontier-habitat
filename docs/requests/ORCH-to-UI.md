# Orchestrator to UI

## 2026-10-01 — Paul: an "all roofs off" toggle

Paul and a friend asked for a toggle that takes every roof off at once. RENDER adds `view.set_roofs_off(bool)`
(ORCH-to-RENDER.md). UI: a button on the right rail or the view controls (icon + tooltip "Roofs off: see into
every building"), a key (suggest R is taken by rotate; choose a free key and list it in Settings > Keys, How
to play and the codex), and a setting kept on the device. Show its state clearly (pressed look). In the
over-the-shoulder view roofs stay on (Paul: enclosed feel); the button is disabled there with a tooltip.
Help text in STE (ui/v5_help.gd).

## 2026-10-01 — Paul: windows cover the centre; use tab panels, keep information on the left

Evidence: `docs/requests/shots/paul_2026-10-01_windows_centre.webp` (day 15: the hazard banner "DUST DEVIL IN
0:19" and the request card "A HOME FOR TWO" sit over the top centre of the view, over the colony; on the
left, the chapter card, alerts, hazards and traffic panels stack and take about a third of the width).

Paul's words: "your window system needs work you might need to add tab panels and keep the info to the left
side, the laying over the centre is bad".

Do (V4 window manager, ui/hud/*, bounds_keeper, wm):
1. Nothing opens over the centre of the view by default: event banners (hazard countdowns), request cards,
   unrest banner, toasts and similar move to the left column (or a slim top-left/bottom-left strip). The
   centre stays clear for the colony. A player may still drag a window there.
2. One tabbed left panel instead of a stack of separate cards: tabs such as Goals (chapter), Alerts,
   Events (hazards + countdowns), Traffic, Requests, People news; each tab shows a count badge and an
   urgency colour; the tab with an urgent item flashes once, then holds a badge (no blinking).
3. The panel is narrower than today's stack and can collapse to its tab strip; its height fits the view
   (no overlap with the minimap).
4. Urgent items that need an answer (request cards, a dust devil in seconds) get a compact row with the
   buttons in the left panel, plus at most a small top-left banner; never a large card in the centre.
5. Update test_window_bounds / test_wm with a rule: no HUD window's default rect overlaps the central area
   (for example the middle 50 % of the width and height), at 80/100/140 % scale.
6. Web screenshots before/after with showcase_v5 at 1920x1080 and 1280x720.
