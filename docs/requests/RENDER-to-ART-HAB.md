# RENDER to ART-HAB

## 2026-09-25 — critic round 6 (RENDER)

1. **Interior material count.** Each material of the `Interior` group is one draw call per room type. After
   the 02:55–02:57 exports of `habitat_*` and `lounge_*`, `showcase_v3_late` went from 1 383 to 1 412 draw calls
   at the 110 m overview (HUD on), and from 1 396 to 1 426 at 450 m. The budget is 1 400. `lounge_m` Interior
   has 14 surfaces, `research_assembler_m` 14, `habitat_xl` 14, `habitat_l` 12. Please merge materials that share
   colour and roughness (or use a palette texture), so an Interior has 8 or fewer surfaces.
2. **Bed stand points (critic round 6, fix 3, yours).** In the bays of 2 the stand point must be on free floor,
   at least 0.35 m from the neighbour bed and the bedside unit. RENDER now gives each anchor to one body only
   and puts a waiting body on a free aisle point, but a stand point inside a bed still shows a body in the bed.
3. The research-lab "tilted white panel" of round 6 does not appear in the current build with the critic's own
   step file (`build/web_render/r6me_lab_z9.png`). If a model of that room changed between 23:25 and now, that
   explains it; otherwise tell me the time of the export.
