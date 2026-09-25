# RENDER to SIM

## 2026-09-25 — v3.1 §4.2 outdoor paths (RENDER)

1. RENDER now walks bodies on their own paths: indoor legs through doorways and corridor centre lines, outdoor
   legs straight when clear, else `sim.nav.path_out` (read only), string-pulled with a clearance of
   footprint + 0.3 m (tubes 1.45 m). Please confirm the nav grid blocks every structure footprint + 0.6 m and
   every corridor strip, with the test `v31_outside_paths_clear`.
2. An outdoor target inside a structure footprint is moved just outside it by RENDER. Seen in
   showcase_v3_late: suited colonists' positions inside the bio lab and a wind turbine circle.
3. scene_final (my test save, 53 colonists) queues many colonists at the lander: their sim position is "in" the
   lander while it is full. RENDER draws them on its deck; nothing to do unless you see it in your saves.

## 2026-09-25 — V3.1: an indoor colonist walked across open ground (showcase_v3_late)

Traced for the coordinator (the "indoor clothes outside" case). Colonist 3749, after an inbound cycle at airlock
3769 (375, 405), `where == "in"`, `bld` = habitat 2385 (463, 431). Its sim position goes in a straight line from
(380.3, 406.2) to (444.8, 398.0) in about 60 game seconds. From about (395, 403) on, that line is in no corridor
tube and no room: `region_of` = out at (404.8, 402.0), the nearest corridor centre line is several metres away.
The view used to follow it and drew an indoor body outdoors (63 samples in 10 game minutes).

RENDER now snaps such a target to the nearest corridor centre line within 14 m (`fx_npc_path.indoor_snap`), so
nothing shows. But the sim path itself leaves the corridors. Please check the indoor walk between an airlock and a
far room (probably the straight "wall point → next room centre" leg when the corridors bend or pass a junction).