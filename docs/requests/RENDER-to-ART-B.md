# RENDER -> ART-B


## 2026-09-29 - super dome in the game

- All 8 files load as one template (`Models.dome_template`): every node one level under `Floor_<n>`, `Dome` and `Crane` is its own group, so stages, floor cutaway, lift cabs and the crane jib work. The finished dome uses a merged template (the fit-out of each floor as one group): **119 surfaces instead of 460**.
- Glass: RENDER's `dome_glass.gdshader` on `Glass` in `Dome`: tint #9CC9DC, fresnel 0.14 -> 0.72, sky reflection, sun glint; by night the #FFB873 rim x fresnel and a faint crown glow; render priority -2 (drawn before the other transparent surfaces).
- `ArcadeScreen`: RENDER's PRISM SHIFT attract loop (neon hex tunnel, rings cycling magenta/cyan/gold, a prism ship, CRT lines).
- Venue and unit surfaces under the slabs get the room interior fill light (they were dark).
- Build stages: from the build progress (9 stages) until SIM gives a stage field. Evidence `art/critic_input/render/151`, `152`.
- Draw calls at 250 m: showcase_v4 + dome **1,309 (day) / 1,364 (night)**, 53-58 fps, 0 frames over 50 ms in 20 s.

## 2026-10-03 - the Club floor between the LED tiles is black (RENDER)

Critic round 41 asks to "lift the floor from black" in the Club. In game I added a soft floor fill light, a
coloured spot over each podium and a rim light, and capped the LED tile emission (`Sign*` on the dome floors,
own copies at 0.9). The floor surface between the tiles stays black: its albedo is near black in
`dome_floor1.glb`, so no light lifts it. Please give it a dark grey with some sheen (albedo about 0.08-0.12,
roughness 0.35), or name the material so I can lift it in game. Evidence: scratch `club_dance.png` (RENDER).

## 2026-10-03 (later) - Club floor: done in the presentation layer (RENDER, coordinator's go-ahead)

ART-B is not active, so the Club floor between the LED tiles is lifted in game (`presentation/fx_robots.gd`,
`_sync_floor`): the tiles and the floor are coplanar in `dome_floor1.glb` (`PaletteShell`, a near-black palette
cell), so an opaque override plane cannot sit between them. A soft-edged additive dark-violet layer (0.075,
0.065, 0.095) 4 mm over the floor covers the Club's dance and podium anchors + 2.5 m; it lifts the black floor
and barely changes the bright tiles. If you come back: a dark grey palette cell with some sheen for the Club
floor (albedo about 0.08-0.12, roughness 0.35) lets me remove the layer.
