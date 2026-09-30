# Orchestrator to ART-HAB

## 2026-10-01 — Paul: desks face into each other; people sit inside the desk (DO FIRST on resume)

Evidence: `docs/requests/shots/paul_2026-10-01_desk_seat.webp` (Paul's screenshot, in game, a room with
paired workstation desks: 2-3 monitors each, a centre divider, yellow desk lamps).

Paul's words: "the npcs need to sit at proper desks and not sit in the desk and by the look the desks were
meant to be rotated 180 degrees and face away and not in to each other".

Found in the picture:
1. The desk pair is back to back with a divider, but the monitors and chairs point INTO the pair: the chair
   and the person are inside the desk volume, on the divider side. The seat side is wrong by 180 deg.
2. The person sits inside the desk top (body through the desk and between monitors); the keyboard is on the
   far side of the divider.
3. Monitors on the outer edge face out at nothing.

Do:
- Find every room model with this desk pair (search interior builders for the workstation/desk-pair kit:
  research lab, command, office, academy, security office, others) and rotate each desk 180 deg in place
  (or move the chair, keyboard and monitors to the open side), so the monitors face the divider and the
  chair is on the open side, facing the monitors.
- Move the `Anchor_Seat_*` / `Anchor_Stand_*` of each desk with it: seat point 0.30 m behind the desk edge
  on the open side, facing the monitors (your NPC numbers: seat top 0.46 m).
- Add a check to your builder: a seat anchor is never inside a desk or table footprint and faces its screen.
- Rebuild, `node tools/godot.mjs import`, `check`; renders in art/interiors/. Tell RENDER to rebake nav grids
  (tools/render_nav_bake.gd) and to check the sit placement (ORCH-to-RENDER.md has the RENDER part).
