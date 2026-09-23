# ART-A progress log (room buildings)

Owner: ART-A. Files: `tools/blender/build_assets.py`, `tools/blender/rooms_*.py`; in `assets/models/` and
`assets/thumbs/` the files of the **room** types, `airlock`, `junction`, `corridor`.

## 2026-09-24 — milestone 2: all room types delivered

All 2.0 files exist and pass every check (91 files, `tools/blender/build_report.md`: 91 rows, 0 flags).

| group | ids | files |
|---|---|---|
| sized (22 types) | habitat, lounge, cantina, medical, bio_lab, storehouse, cold_storage, greenhouse, fungus_farm, algae_bioreactor, kitchen, oxygen_plant, water_recycler, atmo_processor, research_lab, mine, refinery, polymer_plant, workshop, glassworks, electronics_fab, fabricator | `assets/models/<id>_s/_m/_l/_xl.glb` + `<id>.glb` (= M); `assets/thumbs/<id>_s/_m/_l/_xl.png` + `<id>.png` (= M) |
| single size | airlock, junction, corridor | `assets/models/<id>.glb`; `assets/thumbs/<id>.png` |

### Contract of every room file

- Objects: `Base`, `Roof`, `Interior`, `L2`..`L5` (single-size files: no L parts), `Lights` where the model
  has lamp lenses. Corridor: `Base`, `Roof` (1.0 m on X, as v1).
- Empties: `Anchor_Door` (every room with a door), `Anchor_Beacon` (L5 lamp), `Anchor_Smoke*` (kitchen,
  refinery, glassworks), `Anchor_Fume` (bio_lab), `Anchor_Vent*` (oxygen_plant stacks, algae core,
  water_recycler, polymer_plant), `Anchor_Vapour1..4` (atmo_processor towers), `Anchor_Hatch` (storehouse),
  `Anchor_Telescope` (research_lab), `Anchor_Light` (airlock roof light). RENDER confirmed the prefix handling.
- Footprint: every vertex >= 0.10 m inside the footprint circle. Floor top z = 0.14. Room wall to 1.40 m at
  radius R - 0.32; foundation ring to R - 0.10 (corridor ends meet it).
- Trays: greenhouse and fungus_farm trays sit at `sizes.tray_offsets[size]` (re-import check: error 0.0000 m),
  soil top z = 0.55, tray 3.0 x 1.4 m.
- COLOR_0 = baked AO on every primitive (linear, white = open, min 0.18), same method and curve as ART-B.
- Budgets met: S <= 3000, M <= 4500, L <= 6500, XL <= 9000 triangles (all objects incl. L2..L5).
- Material reuse beyond the section-11 meaning: `L4Band` = fungus-farm violet grow strips; `Glow` = bio-lab
  green cross and algae tube rings; `PlantDark` = algae tube body; `Frost` = medical privacy windows,
  cold-storage drum and floor; `Plasma` = electronics-fab blue window band and screens.

### Family look (for UI and screenshots)

- Habitat family: white domes (habitat with portholes; L/XL two decks + skylight), glass panorama dome
  (lounge), roof terrace + canopy + abstract neon sign (cantina), red cross (medical; L/XL isolation pods),
  pod cluster + green cross + fume stack (bio_lab), low drum + cargo hatch, L/XL silos (storehouse),
  frosted drum + fin ring (cold_storage).
- Agri: triangulated lattice glass dome (greenhouse), dark ribbed dome (fungus_farm), ring of green
  glowing tubes round a core (algae_bioreactor), dome + chimneys + service hatch (kitchen).
- Life: dome + glass panels + 1/2/3/4 electrolysis stacks (oxygen_plant), drum + ring of filter columns +
  blue pipes (water_recycler), 2/2/3/4 hyperbolic cooling towers (atmo_processor).
- Science: hex pods (stacked at L/XL) + observatory with slit and telescope (research_lab).
- Industry (graphite podium, dark deck, orange accents): mine (white dome + lattice headframe + hoppers),
  refinery (gable shed + 1/1/2/3 chimneys), polymer_plant (vats + pipe rack), workshop (sawtooth shed +
  crane), glassworks (glowing kilns + glass cooling bed), electronics_fab (clean-room blocks + ducts),
  fabricator (barrel-vault hall + gantry + rolling door + plate stacks).

### Build and review

Rebuild all (about 2.5 min incl. thumbnails):
`"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/rooms_build.py -- [--only id1,id2] [--sizes s,m] [--no-thumbs] [--review]`
Review sheets: `tools/blender/previews/rooms/_review_<family>.png` (sizes side by side, M open, M level 5,
XL level 5 from the game side) and `_family_<family>.png` (thumbnails). Families: habitat, agri, life,
science, industry, links.

### Known limits

- Level parts sit partly on the roof; RENDER opens them with the roof (done on their side).
- Corridor end collars (x in +-0.44..0.5) stretch with the corridor length, as in v1.
- Weakest looks: storehouse S/M deck is plain; cold-storage `Frost` is close to `Hull` in colour; junction is
  simple by design (colonists walk through its centre).
