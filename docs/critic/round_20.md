# Critic round 20 — `terrain_v4` on SIM's generator

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §1, §1.1 · Pass ≥ 0.65 ·
Same calibration as rounds 1–19. The full detail is in `round_20.json`.

## Score

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| terrain_v4 | 0.72 | 0.70 | 0.72 | **0.71** | 0.60 FAIL | PASS |

## Evidence

- **RENDER:** `art/critic_input/render/125–128`.
- **My own:** `build/web_render` (14:06), `seed=1001&scenario=frontier`, unstaged. Overview, deep crater
  (675, 1586), two mountains, two crevices, a boulder field, a plateau and the start area, by day, dusk
  and night. The files are in `art/critic/r20/` and `r20_grid.png`.

## Round-18 fixes

| fix | result |
|---|---|
| 1 Haze | **Landed.** Crisp at 1,300 m. |
| 2 Shadow | **Mostly landed.** A shadowed crater floor is near pure black by day (`r20_floor_crop.png`). |
| 3 Mountains | **Landed** for mountains and plateaus. **Not** for crevices. |
| 4 Crater form | **Landed.** The best feature: rim lip, terraces, rays, debris. |
| 5 Boulders | **Partly.** Scaled faceted rocks; the scale figures sell the size. |
| 6 Detail texture | **Landed.** The gravel patches tile visibly. |
| 7 Weather | **Landed.** |
| 8 Base lights | **Landed.** An island of light in a dark bowl. |

Paul's asks now read: massive deep craters with little sun and proper shadows, mountains to go
around, plateaus, crevices and big boulders.

## Fixes, most important first

1. **RENDER — crater floor by day.** Keep 12–18% of the lit brightness with a cold blue-grey tint.
   It is about 2% now, so nothing on the floor can be seen without lamps.
2. **RENDER — crevices.** The walls are stretched triangle sheets with spikes. Build them as their own
   lofted wall mesh along SIM's line, not from the 4 m grid.
3. **RENDER — tiling.** Break the repeating hex-blotch gravel pattern with a large-scale noise and
   random rotation.
4. **RENDER / SIM — deposit rings.** The dashed orange rings show everywhere without an overlay. Show
   them only with the resource overlay or after a survey.
5. **ART-HAB — boulders.** Real eroded meshes (in progress).
6. **RENDER — camera range.** In my build `zoom` stops at about 200 m. Confirm the 1,300 m view is
   reachable in normal play.
