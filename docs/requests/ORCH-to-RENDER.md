# Orchestrator to RENDER

## 2026-10-01 — Paul: people sit inside desks (do after ART-HAB's desk fix)

Evidence: `docs/requests/shots/paul_2026-10-01_desk_seat.webp`. ART-HAB turns the paired desks 180 deg and
moves the seat anchors (ORCH-to-ART-HAB.md). Then: rebake nav grids; check that a seated body is placed on
the chair at the anchor, facing the screen, and never overlaps the desk box (add this to a render check:
seated body capsule vs furniture boxes, every seat anchor of every room type, 0 overlaps).

## 2026-10-01 — Paul: grounding, and more camera freedom in the over-the-shoulder view

1. Grounding: people float when they run. Check the drawn body's foot height against the floor/terrain each
   frame (with ART-NPC's clip fixes); no body may float or sink by more than 1 cm when a foot is planted.
2. Camera freedom: the player must be able to look around freely and see the person: full orbit around the
   person (360 deg, not +-70), wider pitch (from low near the floor to high above), zoom from close face
   shot to about 8 m, a free-look mode that keeps the camera on the person but lets the mouse look anywhere,
   and a smooth return behind the shoulder. Keep the wall rule and the smoothing measured on 2026-10-01
   (re-run tools/render_follow_probe.mjs after the change).
3. Scope change (V5_DESIGN.md §15): a viewer mode is coming. Design the camera code so that a cinematic
   "watch" mode (automatic shots of people and the colony) can be added later.
