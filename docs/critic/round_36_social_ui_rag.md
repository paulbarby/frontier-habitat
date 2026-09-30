# Critic round 36 — `social_ui` and `regolith_rag` after the round-29/30 fixes

Date: 2026-09-30 · Critic · Rubric: `docs/critic/v5_rubrics.md` §3.5, §3.6 · Pass ≥ 0.65. The full
detail is in `round_36_social_ui_rag.json`.

## Scores

| subject | cons. | appeal | style | score | round 30 | result |
|---|---|---|---|---|---|---|
| social_ui | 0.78 | 0.74 | 0.76 | **0.76** | 0.71 | PASS, provisional |
| regolith_rag | 0.78 | 0.74 | 0.76 | **0.76** | 0.75 | PASS, provisional |

Both are provisional: the SIM systems are not wired, and the Rag content is a stub.

## social_ui — round-30 fixes, all 7 landed

| # | fix | result |
|---|---|---|
| 1 | Reading well | **Landed.** A dark well behind every list, and the scene no longer distracts. |
| 2 | One window per person | **Landed.** |
| 3 | Discipline confirm | **Landed.** "Ration cut: Asha Verrin?" shows the effect on Asha, on others (by name), the risk, and an UNFAIR warning with its reason. |
| 4 | Riot vs protest | **Landed.** Riot is red with damage and injury lines; protest is amber. |
| 5 | Button effects | **Landed.** A sub-label on every response. |
| 6 | Crew window | **Landed.** Body font, mood faces, a "waiting for a better home" list, a skill matrix. |
| 7 | Satisfaction parts | **Landed.** One 0–100 track each, worst first, with the reason. |

**Fixes (UI).**
1. **Cut reason.** "Housing below what they ex…" is cut. Wrap it; a cut reason defeats "find out
   why".
2. **Raw ids.** "Wears: uniform command" shows a raw id. Show "Command uniform", and the same for
   every outfit.
3. **Org chart.** The lower half of each column is empty. Fit the height, or show each person's top
   skills.
4. **Skill matrix.** About 10 px digits and cut headers ("Farmin"). Use 12 px, standard abbreviations
   with a tooltip, and colour by level.
5. **Toast.** A test toast covers the top of the follow view. Confirm that toasts sit on the top edge.

## regolith_rag

| fix | result |
|---|---|
| Special edition headline | **Landed.** 2 lines, and the photo is in view. |
| Quiet day | **Partly.** A SLOW NEWS DAY kicker and a smaller lead; the bottom half is still the normal layout. |
| Poll | **New.** A "61% say yes, 39% say no" line. |

**Fixes.**
1. **UI:** the quiet-day bottom needs a larger gossip column and a puzzle or "photo of the day" box.
2. **SIM:** the content is still the stub.
3. **RENDER:** `photo()` is still missing.

**Tone check:** nothing explicit, and no child in any shot.
