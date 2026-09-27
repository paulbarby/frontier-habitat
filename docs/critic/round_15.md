# Critic round 15 — v4.0 `ui_theme` pilot (HUD top bar and inspector)

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §7 · Pass ≥ 0.65 ·
Same calibration as rounds 1–14. Only the top bar and the inspector were judged. The full detail is in
`round_15.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| ui_theme (pilot) | 0.72 | 0.70 | 0.66 | **0.69** | PASS, provisional |

## Evidence

- `docs/shots/ui4_*.png` (6 files).
- My own shots from `build/web_ui` (09:22) with `showcase_v3_late` in a dust storm, by day and night:
  glass on and off, a dragged window, the agent inspector, the research screen and Esc. The files are
  in `art/critic/r15/` and `r15_grid.png`; crops are `r15_crop_insp*.png`.

## What works

- **Close up, the metal reads.** A gunmetal band with a bevel, chamfers, engraved seams, and a brushed
  title plate with a family accent line.
- **Refined, not busy.** A calm palette, good typography, and a thin frame.
- **Readable.** Text reads over the dust storm by day and by night.
- **Window manager.** Drag, per-window memory and Esc order work. The blur costs about 0.2 ms.
- **Version.** 4.0 shows on the title screen and in About.

## Fixes (UI), most important first

1. **It does not read as glass.** With glass on, the panel is near-opaque navy and the blur is
   invisible. Set the tint to about 70% opacity, add a sheen gradient and a 1 px inner highlight.
   Keep a darker reading well behind lists. Report the text contrast (≥ 4.5:1 over the brightest
   scene).
2. **The inspector covers the right nav rail** at its default place. It shows only with glass off.
   Exclude the rail from the work area.
3. **Windows cover the goals and hazard panels when dragged.** Snap to their edges, or fold those
   panels while a window is over them.
4. **Rivets read as dust dots at 1:1.** Make them 8–9 px and domed, at corners plus one every
   ~180 px, not every 96 px.
5. **The brushed grain is invisible.** Raise the grain contrast and lighten the band one step.
6. **A stray square pixel** sits on the title plate's left edge.
7. **Long lines touch the right frame.** Keep a 12 px margin and wrap.
8. **Seams inside the glass.** Add hairlines between the title plate and body, and between the tabs
   and content.

## Rules for the rollout to every screen

- **Frames:** one frame language everywhere. The metal frame replaces the v3 cyan corner brackets;
  never use both on one screen.
- **Buttons:** a glass fill with a 2 px bevelled metal rim. The primary button glows inside the rim;
  it is not a flat cyan block.
- **Tabs:** metal edges. The selected tab is lit glass with the family accent line.
- **Lists and tables:** darker glass wells with seam separators, no box per row.
- **Charts:** a darker well, with the grid drawn as faint seams.
- **Title screen:** the same button style, and the 4.0 badge as a metal plate.
- **Scale:** rivets, frames and seams scale with the interface scale. Check at 80% and 125%.
