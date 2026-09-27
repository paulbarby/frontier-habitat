# Critic round 18 — v4.0 `terrain_v4` pilot

Date: 2026-09-27 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V4_DESIGN §1, §1.1 · Pass ≥ 0.65 ·
Same calibration as rounds 1–17. Judged on look and light, not placement. The full detail is in
`round_18.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| terrain_v4 (pilot) | 0.62 | 0.56 | 0.62 | **0.60** | **FAIL** |

## Evidence

- `art/critic_input/render/121–124`.
- My crops: `art/critic/r18_range_crop.png`, `r18_plateau_crop.png`.

## What works

- **Horizon shadows move with the sun.** The crater floor is dark early and at dusk and lit at noon.
  At noon it reads as a bowl.
- **The crevice** reads as a deep, dark crack.
- **The crater base** stays visible at night through its bands.

## Why it fails

At the game cameras, haze and flat shading hide the drama Paul asked for. The overview is brown
stains on a flat plane. At dusk the crater disappears. The mountains show stretched spikes, and the
boulders read as blobs.

## Fixes, most important first

1. **RENDER — haze.** Scale the fog with camera height (start at 1.5 × the camera distance, at most
   35% density at the far edge). Never fog the ground under the focus.
2. **RENDER — shadow.**
   - Keep sun shading and add the horizon term on top of it.
   - Soften the shadow edge (a 2–4 m penumbra).
   - Give shadowed ground a cool blue-grey ambient, so crater floors read cold, not warm brown.
3. **RENDER / SIM — mountains.** Remove the stretched cliff triangles and spikes: more resolution on
   steep cells or triplanar cliffs. Use SIM's generator heights.
4. **RENDER — crater form.** A rim lip with a lit edge, slumped or terraced walls, an ejecta apron,
   and floor boulders.
5. **RENDER / ART-HAB — boulders.** Real rock meshes with lit tops and cast shadows, in fields of
   30–80 with 3–4 giants. Put a scale cue in the shot.
6. **RENDER — detail texture.** Extend the detail layers to the whole map.
7. **RENDER — weather.** The rain-like streaks in 123 should read as dust, or be hidden in critic
   shots.
8. **RENDER — base lights.** Brighter lamp pools, so the base reads as an island of light in a dark
   bowl.

Re-rate on SIM's generator with fixes 1–4.
