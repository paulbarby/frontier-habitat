# Critic round 25 — v5.0 `regolith_rag` pilot (in game)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.5 · Pass ≥ 0.65.
The full detail is in `round_25_rag_pilot.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| regolith_rag (pilot) | 0.74 | 0.66 | 0.72 | **0.71** | PASS, provisional |

The pass is provisional because the photo is a placeholder and the stories are SIM stub data. The
score is for the UI.

## Evidence

- `docs/shots/ui11_rag_{top,middle,bottom,back_issue}.png` (1600×900).
- My own shots from `build/web_ui` (18:24), `showcase_v4`, at **1280×720**: `rag`, `ragscroll 700`,
  `rag 3`, `rag 1`. The files are in `art/critic/r25/` and `r25_grid.png`.

## What works

- **All §4.3 sections are present.** Red masthead with issue, day and price, strap line, kicker tag,
  huge lead headline, photo with caption, by-line, 3 stories, gossip column, Couple Watch, Feud
  Watch, approval poll, small ads, and a plain-STE Serious News strip.
- **It reads as a tabloid at a glance.** Cream paper, bold condensed capitals, black rules, a red
  kicker. The voice lands.
- **It sits cleanly in the glass-and-metal window.** The issue picker in the title bar works for back
  issues, and names are underlined links.
- **It is readable** at 1600×900 and at 1280×720.

## UI fixes, most important first

1. **Alerts panel.** The window covers the Alerts panel without folding it, so the alert text is cut
   at both sizes. Apply the V4 fold rule, or open the window right of the left panels.
2. **1280×720.** The masthead and a 3-line headline fill the first view, and the photo starts below the
   fold. Auto-fit the lead to 2 lines (40–64 px) under 800 px height, and shrink the masthead 30%.
3. **Flat paper.** Add a subtle newsprint grain, a halftone on the photo, and a double rule under the
   masthead.
4. **Empty right column.** After the poll, "THE RAG KNOWS." floats over empty space. Flow the gossip
   column or a second story into it.
5. **Poll glyph.** The red "=" is unexplained. Use an arrow or dash with words ("no change", "+4 since
   yesterday").
6. **Name links.** They need a hover state and a tooltip ("Click: select. Shift-click: follow").
7. **One template.** Every issue has the same layout. Add 2–3 layouts by story mix: a big-photo lead,
   a split lead, a SPECIAL EDITION for riots.
8. **Small ads.** Two boxes leave half the row empty. Fill it or widen them.

## Content gaps (not UI)

| owner | gap |
|---|---|
| SIM | Building completions fill the story row with one template. "NEW UTILITY CABLE 16 OPENS ITS DOORS" — a cable has no doors. Rank people stories first, and give buildings their own templates by type. |
| SIM | Story bodies are one line and repeat: "Our spies saw them together." is on every lead. Write 2–4 sentences from the event. |
| SIM | The poll is 61% in every back issue. It should move with satisfaction. |
| SIM | Gossip has 2 lines; Couple Watch and Feud Watch have 1 entry each. They need 3–5 items each. |
| RENDER | The lead photo is a placeholder silhouette. It needs `photo()` (V5 §4.4). |

**Tone check:** nothing explicit, and no children in any story seen.
