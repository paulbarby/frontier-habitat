# Critic round 39 — in-game evidence: dome fps settled, dome / civic / residences / Rag photos

Date: 2026-09-30 · Critic · Pass ≥ 0.65. The full detail is in `round_39_ingame.json`.

## (a) The fps question — settled

**Method.** RENDER's agreed method: `tools/render_perf.mjs`, presets in `tools/perf/`, 10 s settle,
30 s sampling with no capture, vsync, CPU load recorded. My outputs are in
`art/critic/critic_r39/critic_perf_*.json`.

| case | CPU load | median fps | mean fps | lowest 0.5 s | frames > 50 ms | draws | people |
|---|---|---|---|---|---|---|---|
| dome_v3 250 m night (storm) | 19.7 % | 59.9 | 52.7 | 35 | 1 | 1,378 | 66 |
| dome_v5 250 m night | 15.4 % | 59.9 | 57.9 | 47 | 0 | 1,281 | 20 |
| dome_v3 follow by pool, run 1 | **31.3 %** | **30.0** | **37.6** | 31 | 6 | 1,375 | 66 |
| dome_v3 follow by pool, run 2 | 13.8 % | 59.9 | 53.6 | 49 | 1 | 1,374 | 66 |
| dome_v5 follow by pool | 10.3 % | 59.9 | 59.8 | 55 | 1 | 595 | 20 |

**Verdict: RENDER is right for the budget.**
- At low PC load every case meets ≥ 45 fps.
- My round-34 figures of 41 and 33 fps came from my method plus other agents' load.
- **Caveat on record:** the 66-person storm follow case fell to median 30 at 31% CPU load, so it is
  close to the edge on a busy PC.
- No cap is applied.

## (b) Scores

| subject | cons. | appeal | style | score | before | status |
|---|---|---|---|---|---|---|
| super_dome | 0.82 | 0.80 | 0.80 | **0.81** | 0.79 | **FINAL** |
| civic_modules | 0.78 | 0.74 | 0.76 | **0.76** | 0.75 | **FINAL** |
| residences | 0.78 | 0.74 | 0.78 | **0.77** | 0.79 | not final |
| regolith_rag | 0.78 | 0.74 | 0.76 | **0.76** | 0.76 | not final |

### super_dome — FINAL 0.81

- **Glass.** It reads as glass by day (a sky reflection at the rim) and as a warm-rimmed shell at
  night.
- **Night at 250 m.** The multicoloured ring under the lit shell is the brightest thing in the
  colony. **"A glittering city under glass" is met.**
- **Dust storm.** The windows and signs stay bright.
- **Prism Shift.** The prism ship shows over the tunnel.
- **Performance.** Within budget.

Carry-over items that do not block:
- **UI / RENDER:** POI labels still draw through the arcade walls.
- **ART-B:** the club-door bouncer and sign.
- **ART-NPC:** the robot fixes from round 38.

### civic_modules — FINAL 0.76

- **Outside.** In game, all 5 read by silhouette and badge.
- **Cutaways.** Furnished.
- **Night.** The group reads by badge.
- **Apartment-block floor hiding.** It works.

Carry-over, not blocking: the retail L and academy M empty patches.

### residences — 0.77, not final (down from 0.79)

- **In game.** The block and the tubes work, including the floor cutaway and the variant lookup.
- **The follow view inside the tube fails.**
  - One tile is almost black: the camera is under or behind geometry.
  - The other shows the person as a black silhouette with no room light.

**RENDER:** keep the camera inside the unit, light the person with the room lights, and supply a
family-unit and a penthouse follow shot.

### regolith_rag — 0.76, not final

`photo()` works: named people, place, pose, grain, portraits. With the v3 stand-ins it is a
placeholder:
- flat backdrops;
- hug and argue fall back to idle, so the pair stand apart;
- a grey breathing-mask shape on every indoor face;
- a suited astronaut in the club photo.

Fixes:
1. **RENDER:** paired poses in contact, once the MPFB people land.
2. **RENDER:** backdrops with depth, or the real 3D spot.
3. **RENDER / ART-NPC:** no mask on indoor faces, and no suits in the club.
4. **SIM:** the content is still the stub.
