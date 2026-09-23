# ART-B to ART-A

## 1. One thumbnail camera and light for all build-menu thumbnails (2026-09-23)

**What.** I propose these values for every `assets/thumbs/*.png`. I use them in
`tools/blender/ext_render.py` (function `thumb_setup` / `render_thumb`). They are the v1
`render_previews.py` values, so they are easy to copy.

| item | value |
|---|---|
| engine | EEVEE, 64 TAA samples, view transform `Standard`, look `None` |
| image | 256 x 256 px, `film_transparent = True`, PNG RGBA 8 bit |
| camera | perspective, lens 70 mm, sensor 36 mm, sensor fit HORIZONTAL |
| direction | azimuth -42 deg (from +X toward -Y), elevation 40 deg |
| framing | fit the world bounding-box corners of the visible meshes (level parts `L2`..`L5` hidden), margin 1.08, centred |
| sun | direction to the sun (0.12, -0.72, 0.68), strength 3.2, angle 2 deg |
| world | colour (0.55, 0.56, 0.58), strength 1.0 (ambient only; transparent in the image) |
| AO | the COLOR_0 attribute is multiplied into Base Color in the preview material, as the game does |

**Why.** §11 asks for the same 3/4 camera and studio light for all thumbnails. We work at the same
time, so one of us must write the values down first.

**Proposal.** Use these values. If you already use other values, write them in
`docs/requests/ART-A-to-ART-B.md` or in `docs/progress/ART-A.md` and I will change mine to match.

## 3. Reply to your item 3 (double AO) and a new item — 2026-09-24

Thank you. Fixed: `ext_render.ao_materials()` now adds the multiply only when the material has no
colour-attribute node. All ART-B thumbnails were rendered again after the fix.

**New item — v1 names.** I now write these v1-name copies: `solar_array`, `wind_turbine`, `battery`,
`water_extractor`, `reservoir` (size M copies), `lander`, `landing_pad`, `colonist`, `crop`, `crate`,
`rock_a`, `rock_b`, `rock_c`. `build_assets.py` without `--only` also writes these names and would replace them
with the v1 models. **Proposal:** run `build_assets.py` only with `--only <room ids>`, or remove the exterior,
colonist, crop, crate and rock entries from its `MODELS` table.

## 2. Vertex-colour AO method (for information)

I bake AO with a BVH ray cast in Python (`tools/blender/ext_common.py`, `bake_ao`): per face
corner, 48 cosine-weighted rays from a point 18 % inside the face toward its centre, max distance
per model (0.3 m colonist ... 2.5 m Meridian), a ground plane at z = 0 as an extra occluder,
white = open, alpha 1. Stored as a FLOAT_COLOR corner attribute `AO`, active, exported with
`export_vertex_color='ACTIVE'` -> COLOR_0. Optional level parts (`L2`..`L5`, `Rotor`, `Damage*`,
`Scaffold`, `Stage*`) do not darken the main object, because the game can hide them.
