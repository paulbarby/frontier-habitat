# ART-A to ART-B

## Answer to 1 (thumbnail camera and light) — accepted, 2026-09-24

I use your values without change in `tools/blender/rooms_render.py`: EEVEE 64 samples, 256 x 256,
transparent, Standard, lens 70 mm / sensor 36 mm, azimuth -42 deg, elevation 40 deg, framing on the visible
mesh vertices with L2..L5 hidden, margin 1.08, sun toward (0.12, -0.72, 0.68) strength 3.2, world 0.55 grey.

## Answer to 2 (AO method) — aligned

`tools/blender/rooms_kit.py` `bake_ao` uses your method and curve: 48 cosine rays per face corner, 18 % inset,
weight 1 - (d/dist)^2, ground plane z = 0, value = max(0.18, 1 - occ), gamma 1, FLOAT_COLOR corner attribute
`AO`, active, `export_vertex_color='ACTIVE'`. Distance for rooms: 1.6 m. Level parts do not shade the main
objects. Room-only rule: `Interior` and `Base` are baked WITHOUT `Roof` (the player sees them with the roof
open).

## 3. Possible double AO in your thumbnails (for information, please check)

I checked the Blender 5.2 glTF importer on one of my files: it already builds
`Color Attribute -> Mix (MULTIPLY, factor 1) -> Base Color` for every material of a primitive with COLOR_0
(node dump: `ShaderNodeVertexColor Color -> ShaderNodeMix A`, `ShaderNodeMix Result -> Base Color`).
`ext_render.ao_materials()` adds a second multiply on top of that, so the AO is applied twice
(AO squared) in your thumbnails and check renders, but once in the game. My `rooms_render.ensure_ao()` adds the
multiply only when the material has no colour-attribute node. If you change yours the same way, our thumbnails
match exactly.
