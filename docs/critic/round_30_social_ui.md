# Critic round 30 — v5.0 `social_ui` pilot and `regolith_rag` re-check

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.5, §3.6 · Pass ≥ 0.65.
The full detail is in `round_30_social_ui.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| regolith_rag | 0.78 | 0.72 | 0.76 | **0.75** | 0.71 | PASS, provisional |
| social_ui (pilot) | 0.74 | 0.66 | 0.72 | **0.71** | new | PASS, provisional |

Both are provisional: stub SIM data, staged banners, and a placeholder photo.

## regolith_rag — round-25 fixes

| # | fix | result |
|---|---|---|
| 1 | Alerts panel | **Landed.** It folds. |
| 2 | 1280×720 | **Landed.** A 2-line lead, and the photo is in view. |
| 3 | Newsprint | **Landed.** A halftone on the photo, and a double rule. |
| 4 | Right column | **Landed.** Contents with page numbers. |
| 5 | Poll glyph | **Landed.** "– NO CHANGE". |
| 6 | Link hover | **Not verifiable** from stills. |
| 7 | Layouts | **Partly.** A SPECIAL EDITION layout exists. The quiet issue uses the normal layout. |
| 8 | Small ads | **Landed.** 4 ads. |

Fixes:
1. **UI: special edition.** Cap the red headline at 2 lines; at 1600×900 it pushes the photo below the
   fold.
2. **UI: quiet day.** A smaller lead, a "SLOW NEWS DAY" kicker, and a bigger gossip or puzzle box.
3. **SIM: content.** The stub stories are unchanged ("opens its doors" for cables, one-line bodies,
   the 61% poll every day).
4. **RENDER: photo.** `photo()` is still missing.

## social_ui — what works

- **Personnel file.** Satisfaction and attitude with named reasons ("No leisure lately", "Housing
  below what they expect", "Lonely"). You can find out *why* in one click.
- **Social tab.** A clear relationship star, with friend, enemy and rival colours.
- **Review tab.** Four grades and ten actions, each with an estimated effect, colour-coded.
- **Crew window.** The org chart reads as a command board. Housing flags "wants family / executive".
  The academy has a clear empty state.
- **Unrest banners.** The demand is quoted, with 7 responses. The top bar shows the stage.
- **Follow HUD card and dimming.** Good. The codex has People entries.

## social_ui — fixes (UI), most important first

1. **Glass behind text is too clear.** In the personnel file and the civic palette the colony scene
   shows sharply behind the lists. Use the darker reading well (about 88%) behind every list, table
   and graph.
2. **Two windows for one person.** The file opens beside the inspector. Open it in the inspector's
   place.
3. **Discipline confirm.** It is not in the evidence. Show the confirm with the effect on the person
   *and on others*, and the "unfair" warning.
4. **Riot vs protest.** The banners look the same. Give the riot a red frame, a pulse, and a
   damage and injuries line. Keep protest amber.
5. **Banner buttons.** Show each response's effect in a sub-label or tooltip.
6. **Crew window.** Names are about 10 px monospace, and the lower half is empty. Use 12 px body text,
   fill the height, and add a mood face per person.
7. **Satisfaction parts.** Give them a common 0–100 track with the value, sorted worst first.

**Tone check:** nothing explicit, and no child in any shot.
