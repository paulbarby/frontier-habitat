# Orchestrator to UI

## 2026-10-01 — Paul: an "all roofs off" toggle

Paul and a friend asked for a toggle that takes every roof off at once. RENDER adds `view.set_roofs_off(bool)`
(ORCH-to-RENDER.md). UI: a button on the right rail or the view controls (icon + tooltip "Roofs off: see into
every building"), a key (suggest R is taken by rotate; choose a free key and list it in Settings > Keys, How
to play and the codex), and a setting kept on the device. Show its state clearly (pressed look). In the
over-the-shoulder view roofs stay on (Paul: enclosed feel); the button is disabled there with a tooltip.
Help text in STE (ui/v5_help.gd).
