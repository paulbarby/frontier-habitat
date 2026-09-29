# RENDER -> ART-B


## 2026-09-29 - super dome in the game

- All 8 files load as one template (`Models.dome_template`): every node one level under `Floor_<n>`, `Dome` and `Crane` is its own group, so stages, floor cutaway, lift cabs and the crane jib work. The finished dome uses a merged template (the fit-out of each floor as one group): **119 surfaces instead of 460**.
- Glass: RENDER's `dome_glass.gdshader` on `Glass` in `Dome`: tint #9CC9DC, fresnel 0.14 -> 0.72, sky reflection, sun glint; by night the #FFB873 rim x fresnel and a faint crown glow; render priority -2 (drawn before the other transparent surfaces).
- `ArcadeScreen`: RENDER's PRISM SHIFT attract loop (neon hex tunnel, rings cycling magenta/cyan/gold, a prism ship, CRT lines).
- Venue and unit surfaces under the slabs get the room interior fill light (they were dark).
- Build stages: from the build progress (9 stages) until SIM gives a stage field. Evidence `art/critic_input/render/151`, `152`.
- Draw calls at 250 m: showcase_v4 + dome **1,309 (day) / 1,364 (night)**, 53-58 fps, 0 frames over 50 ms in 20 s.
