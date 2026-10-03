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

## 2026-10-01 — Paul: ONE unified panel manager for every alert, request and info pop-up (DO FIRST)

Evidence: `docs/requests/shots/paul_2026-10-01_request_card.webp` (the "A HOME FOR TWO" request card at the top
centre; it cannot be minimised; "2 requests more after this one").

Paul's words: "the alerts like this need to be able to be minimised, so maybe add in a panel based UI manager
for alerts and info and keep the centre UI area free from direct interaction ... make it so I have more
control over the popups and use a unified interface system, not some ad hoc scope creep monster."

This replaces the earlier note of the same date (tabbed left panel) and includes it. Do:
1. Design first: write `docs/UI_PANELS.md` (STE, one page): the one manager, its API, the item types, the
   placement zones, the player controls and the rules below. Every existing pop-up maps to it (list them
   all: alerts, hazards, traffic, request cards, unrest banner, chapter/goals card, toasts, medal pop-up,
   advisor, follow toasts, life events, ...). No pop-up may keep its own placement code after this.
2. One manager (e.g. `ui/hud/panel_manager.gd`): items are posted with type, priority (info / notice /
   warning / critical / needs-answer), source, text, actions, expiry. The manager alone decides where and
   how an item shows. Zones: a left dock with tabs (Goals, Alerts, Events, Traffic, Requests, People/news,
   ...) and count badges; a small top-left strip for at most one urgent line; nothing in the centre zone.
3. Player control: every panel and card can minimise (to its tab or a badge), close, and pin; a tab can be
   muted per item type ("do not pop up for traffic"); a "Notifications" section in Settings lists every
   type with Pop up / Badge only / Off; the choices are kept on the device. One key toggles the whole dock.
4. Same look and same controls for every item (the glass-and-metal theme); no item type with its own style.
5. Needs-answer items (requests) queue in the Requests tab with their buttons; the game never forces a
   card in the centre; an unanswered request shows its default outcome and deadline.
6. Tests: every item type posted at 80/100/140 % and 1920x1080 / 1280x720 → no default rect in the centre
   zone, all minimise/close/mute work, nothing lost when minimised (count badge correct).
7. Web shots before/after with showcase_v5.

## 2026-10-01 (later) — Paul: storm and atmosphere SOUNDS inside habitats

Evidence: `docs/requests/shots/paul_2026-10-01_storm_indoors.webp`. Paul: atmosphere sounds should not be
inside the habitats, especially in the over-the-shoulder view.
Do (ui/audio.gd, ui/world_sounds.gd, music director): when the listener (camera) is inside a room, corridor or
the dome, outdoor weather and wind sounds drop to a faint, low-passed hull rumble (for example -24 dB, low-pass
about 400 Hz) or stop; interior room tone takes over. Outdoors full level. Fade over about 0.5 s on the
transition. Follow view indoors uses this rule always. Test with tools/audio_probe.mjs (indoor vs outdoor
level in a storm) and report the dB numbers.

## 2026-10-02 — Paul: parties (V5_DESIGN.md §16): "Throw a party?" request rows (place, cost, guests, the reason),
party and drama items in the dock (News/Events), a party card in the venue inspector, the "Cheeky dialogue"
setting, Rag party reports, help text (STE). After SIM lands the API (SIM-to-UI.md).

## 2026-10-02 — Paul: HR department → V5_DESIGN.md §17 (your parts as listed there).

## 2026-10-03 — Paul: build palettes cover the centre while placing
The category palette is a compact edge strip outside the centre zone; it folds while placing; placement info goes to a small edge panel; tests check the centre zone while building. (Sent to UI.)

## 2026-10-03 — Paul: Colonists window, Priorities tab: check priorities work; layout must match the Colonists and Visitors tabs
Evidence docs/requests/shots/paul_2026-10-03_priorities.webp.

## 2026-10-04 — Paul (after playtesting): V5_DESIGN.md §18 (orders obeyed at once, chain of command, work queues, missing-capability alerts with production chains, package transport system). Your parts as listed there. SIM first: §18.1 bug fix.
