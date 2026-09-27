# Critic round 21 — `ui_theme` on the full rollout

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §7 · Pass ≥ 0.65 ·
Same calibration as rounds 1–20. The full detail is in `round_21.json`.

## Score

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| ui_theme | 0.80 | 0.76 | 0.76 | **0.77** | 0.69 (pilot) | PASS |

## The key question

**Does it read as refined glass with metal frames, rivets and seams?**

- **HUD and windows: yes.** Frosted glass shows the scene through it. There are brushed-metal bands,
  domed rivets, engraved seams, chamfered corners, and a title plate with the family accent line.
- **Full screens** (dashboard, colonists, research): they read as dark metal-framed panels more than
  glass. That helps readability, and they are consistent, but they are less "glass".

## Evidence

- `docs/shots/v4/`: 118 shots and 5 contact sheets.
- The contrast figures in `docs/progress/UI.md`.
- My own window-manager test in `build/web_ui` (14:14), in `art/critic/r21/` and `r21_wm.png`, plus
  the crops `r21_*_crop.png`.

## Round-15 fixes: all 8 landed

| fix | result |
|---|---|
| 1 Glass | The scene shows through. Body text measures 8.9–10.8:1 and secondary text 5.0–6.1:1. |
| 2 Nav rail | A window dragged into the rail moves left of it. |
| 3 Goals and hazard panels | They fold while covered and come back. |
| 4 Rivets | Domed, readable at 1:1, a calm rhythm. |
| 5 Grain and band | Landed. |
| 6 Stray square | Gone. |
| 7 Margin | Lines wrap. |
| 8 Seams | Hairlines inside the glass. |

## Rollout rules: all met

- One frame language, with no brackets left.
- Rimmed buttons; the primary button glows inside its rim.
- Metal-edged tabs with a lit accent.
- Seam lists in wells.
- Charts on wells with seam grid lines.

## Fixes (UI), most important first

1. **Scale 125%.** The build bar overlaps the minimap panel (`r21_s125_crop.png`). Lay out the bottom
   row so the build bar starts right of the minimap at every scale.
2. **Low drag.** A window dragged low stays partly off-screen and over the build bar until another
   window opens. Clamp it inside the work area when the drag ends.
3. **Full screens.** Add a 12–16 px frosted border zone and set the body to about 88%, so they read as
   the same glass family.
4. **Text at 80% and 1280×720.** Tab labels and hints are 11 px. Keep text ≥ 12 px; scale the frame,
   not the text.
