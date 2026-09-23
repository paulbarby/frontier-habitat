# ART-A to RENDER

## 1. Level parts on the roof must open with the roof (2026-09-24)

**What.** In every 2.0 room file, `L2`..`L5` contain parts that stand on the roof (antenna, roof module,
radiator fins, side annex, crown ring, beacon, emblem) and bands that hug the roof surface.
`world_view.gd` squashes `Roof` to the ground (scale.y = open factor) when the camera is near or the room is
selected. If `L2`..`L5` stay at full scale, those parts float in the air above the open room.

**Proposal.** Apply the same open factor to `L2`..`L5` as to `Roof` (scale and visibility), and show only
`L2`..`L<level>` (cumulative). `Lights` and `Anchor_*` empties stay as they are; `Anchor_Beacon` is the L5
beacon lamp (blink it only when L5 is visible).

## 2. Files and anchors

The list of 2.0 files and the object/anchor contract is in `docs/progress/ART-A.md` (updated at each
milestone). Every room has `Anchor_Door` outside the +X door at ground level. Chimneys and stacks have
`Anchor_Smoke*`, `Anchor_Fume`, `Anchor_Vent`, `Anchor_Vapour` (cooling towers, coming).

## 3. AO strength

COLOR_0 is linear AO (white = open, min 0.18), the same method and curve as ART-B's files. If it looks too
faint under your lighting, one global `pow(COLOR.r, k)` (k about 1.5..2) in the material changes all models
the same way. Please do not change it per model.

---
**RENDER answer (2026-09-24): done.**
1. `L2`..`L<level>` of a room now take the same open transform as `Roof` (scale about the model origin,
   lift, hidden when fully open); levels above the building level stay hidden. Exteriors keep their level
   parts in place (they have no roof). The selection outline skips them while the roof is open.
2. Anchors are matched by prefix: `Anchor_Smoke*` / `Anchor_Fume*` give smoke (industry) or steam (kitchen,
   cantina, others); `Anchor_Vent*` / `Anchor_Vapour*` / `Anchor_Steam*` give steam; up to 3 per structure.
   `Anchor_Door` gets a warm lamp halo at night; `Anchor_Beacon` blinks only when the level is 5.
3. AO: used as delivered (COLOR_0 linear, `vertex_color_use_as_albedo`); no per-model change.
