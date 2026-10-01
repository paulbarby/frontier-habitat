# UI panels: one manager for every alert, request and message

Owner: UI. Paul, 2026-10-01: "use a unified interface system, not some ad hoc scope creep monster".
Code: `ui/hud/panel_manager.gd` (`hud.panels`). Test: `tools/ui/test_panels.gd`.

## 1. Rules
1. One manager places every item that the game shows by itself. No other code places an alert, a banner,
   a card, a toast or a pop-up.
2. The centre zone stays free: the middle half of the width and the middle half of the height. The manager
   puts nothing there. A player may still drag a window there.
3. One look: each item is a card in the left dock, with a priority colour on its left edge. No item type
   has its own frame or colour scheme.
4. Every card has the same three controls: Minimise (one line), Pin (stays open, never fades), Close
   (hidden until it changes).
5. Windows that the player opens (inspector, personnel file, the Rag, orders, reactor controls, Find,
   advisor) are not items. The window manager (`ui/wm`) places them at the sides.

## 2. Zones
| zone | where | holds |
|---|---|---|
| Urgent line | top left, under the top bar | at most 1 line: the most urgent item; click opens its tab |
| Pop-ups | top left, under the urgent line | at most 3 new messages; each fades after 5 s (8 s for a warning) |
| Dock | left column, under the pop-ups, above the minimap | tabs (names from 320 px wide, else icon + count) with count badges; the open tab's cards. Pop-ups fold into News before the dock body gets under 200 px |
Width: a quarter of the view less 16 px (300 to 380 px). The dock never goes into the centre zone and
never over the minimap; its body scrolls.

## 3. Tabs
| tab | cards |
|---|---|
| Goals | the chapter and its goals (`goals_tracker.gd`) |
| Alerts | the incidents (`alerts_panel.gd`) |
| Events | a hazard countdown (`hazard_banner.gd`), the reactor (`reactor_banner.gd`), unrest and lockdown with the 7 answers (`unrest_banner.gd`), the hazard forecast (`hazard_panel.gd`) |
| Traffic | ships and their notices (`traffic_panel.gd`) |
| Requests | each open request with its buttons, the outcome when nobody answers, and the deadline (`request_card.gd`) |
| News | the last 40 messages (every pop-up, newest first) |
A tab shows its count and the colour of its most urgent item. A new urgent item makes its tab flash once;
then the badge stays. The tab does not blink.

## 4. Item types and priority
Types (Settings, Notifications): alert, hazard, reactor, unrest, request, traffic, people, goal, award,
research, build, system. Priority: info, notice, warning, critical, needs-answer.
For each type the player picks: **Pop up** (pop-up, badge, flash), **Badge only** (badge, no pop-up),
**Off** (no pop-up, no badge; the cards stay in their tab). Kept on the device (`user://settings.json`).

## 5. API
- `panels.post(type, text, priority, icon)`: a message. It goes to News, and to the pop-ups when the type is
  set to Pop up. `hud.toast()` calls it.
- `panels.host(tab, control, title, icon)`: a card in a tab that shows a module of the HUD. The module
  keeps its data code and loses its placement code.
- `panels.urgent()`: the line for the urgent zone (needs-answer > critical > warning countdown).
- `panels.toggle_dock()` (key L), `minimise_dock()`, `pin_dock()`, `select_tab(id)`, `mode(type)`.

## 6. Player controls
- Dock header: the tabs, Minimise (only the tabs show), Pin (a window over the dock does not fold it; an
  urgent item does not change the tab), Close (only the urgent line and pop-ups stay; key L opens it again).
- A card: Minimise, Pin, Close. A tab's mute button sets its types to Badge only.
- Settings, Notifications: every type with Pop up / Badge only / Off.
- Follow view: the dock goes dim; the urgent line and pop-ups stay bright.

## 7. What moved onto the manager
Goals tracker, alerts panel, hazard forecast, hazard countdown banner, traffic panel, reactor banner,
unrest banner (and lockdown), request card, toasts, medal pop-ups, chapter banners, follow-view toasts,
life-event messages, order answers.
