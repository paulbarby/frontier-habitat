# Critic round 26 — `super_dome` re-check (Blender only, provisional)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.9 · Pass ≥ 0.65.
The full detail is in `round_26_dome_recheck.json`.

## Score

| subject | cons. | appeal | style | score | round 24 | result |
|---|---|---|---|---|---|---|
| super_dome | 0.78 | 0.70 | 0.74 | **0.74** | 0.68 | PASS, provisional |

## Evidence

- `art/dome/overview_250_{day,night}.png` (night with bloom).
- `pilot_overview_{day,night}.png`, `pilot_atrium_pool.png`, `pilot_atrium_night.png`,
  `pilot_gallery_L1.png`, `pilot_cutaway_L1.png`.
- My own: `art/critic/r26_night250_gamepx.png`, `r26_gallery_crop.png`.

## Round-24 fixes, one by one

| # | fix | result |
|---|---|---|
| 1 | Night facade | **Landed.** Varied window tones, about ¼ dark, slab light strips, neon CLOTHING / ELECTRONICS / GIFTS and a billboard. 4–5 light colours at 250 m. L3–L5 are still an even grid, and the neon is on one low band only. |
| 2 | Thinner metal frame | **Landed.** Graphite struts at about half width, small warm node lights. It reads as glass first. |
| 3 | Glass reflection | **Partly.** A faint tint and a rim, but no sky reflection or fresnel. |
| 4 | Signs | **Landed** for CREDIT, RESTAURANT, CAFE and CLINIC. HOTEL is still clipped by a tree, and BARBER by a column. |
| 5 | Pool glow | **Landed.** A cyan pool, warm lamps and string lights. At night the atrium is the bright heart. |
| 6 | Venues filled | **Partly.** Racks, mannequins and shelf rows show in the cutaway. In the gallery the goods are plain boxes, and the screens are flat cyan. |
| 7 | Props | **Landed.** Colony-style benches, and palms and trees that fit. |
| 8 | Pool water | **Partly.** A rim light and an edge, but no tile or lane pattern. |

## Gap to Paul's aim, "a glittering city under glass"

| view | now | estimate (0.80 = glitters) |
|---|---|---|
| **Night, 250 m** | Close. It is the brightest object in the scene, with a glowing atrium, varied windows and street neon. The shell is almost invisible at night, and L3–L5 are too regular. | about 0.72 |
| **Day, 250 m** | It reads as a domed city. The glass needs a sky reflection. | about 0.70 |
| **Inside** | The atrium at night is the best image: resort mood. The gallery goods still need detail. | about 0.74 |

## Fixes, most important first

1. **ART-B: break the L3–L5 grid.**
   - Two window widths.
   - Balconies or planters on every third unit.
   - Some units with a TV-blue or coloured lamp.
   - 2–3 neon or sign bands at L2 round the whole ring.
2. **ART-B / RENDER: night glass.** A faint emissive rim at the dome edge and crown, and city lights
   reflected in the panes, so the shell itself glitters.
3. **ART-B / RENDER: day glass.** A fresnel sky reflection (25–40% at grazing angles). This is fix 3,
   still open.
4. **ART-B: signs.** Move the HOTEL and BARBER plates clear of the tree and the column.
5. **ART-B: venue goods.** Type props instead of boxes (cakes and cups, labelled goods, a menu board).
   Screens with content.
6. **ART-B: pool.** A tile or lane pattern and a darker deep end.
7. **RENDER: in game.** The 250 m night shot with glow, the draw calls, and glass sorting. This
   decides the final score.

**Seen in passing:** in the gallery view a customer stands inside the table top. The people are
placeholders, but the anchors must keep bodies clear of tables.
