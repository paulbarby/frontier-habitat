# Critic round 34 — `super_dome` in game and `follow_view` re-check

Date: 2026-09-29 · Critic · Pass ≥ 0.65. Finished under Paul's pause; nothing new was started. The full
detail is in `round_34_dome_ingame_follow.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| super_dome | 0.78 | 0.78 | 0.80 | **0.79** | 0.79 (Blender) | PASS, **not final** |
| follow_view | 0.74 | 0.70 | 0.74 | **0.73** | 0.67 | PASS, provisional |

## Why super_dome is not final

**The performance numbers conflict.**

| source | 250 m night | follow view inside the dome |
|---|---|---|
| RENDER | 53–59 fps | 56.7 fps |
| My run (`dome_v3.fhsave`, dust storm, same build) | 41.0 fps, 1,153 draws | 33.0 fps, 1,115 draws |

- The budget is ≥ 45 fps.
- If a clean run confirms my numbers, the rubric cap applies: consistency 0.60, subject about 0.72.
  That would be a performance fix, not an art fix.

- My method has known weaknesses: fps was read right after a screenshot and a few seconds after camera
  jumps, in a dust storm. The method and a shared protocol are in
  `docs/requests/CRITIC-to-RENDER.md` (2026-09-30).

**Correction (2026-09-30).** The pck budget is 200 MB soft and 300 MB hard (V5_DESIGN §0, commit
15e507e). The 101.6 MB pck is **not** a blocker; the earlier "build blocker" note is withdrawn.

## super_dome in game — what works

- **City under glass.** At 120 m by night: many lit windows in several colours, neon bands, a lit
  frame, a glowing atrium. By day the glass has a sky reflection.
- **Floor cutaway.** L5, L2 and L1 work, and the atrium reads from above.
- **Build stages.** All 9 read in game.
- **Prism Shift.** The attract-loop tunnel shader runs. The club and bar light up.
- **Follow view by the pool.** The resort mood holds.

## Fixes

1. **RENDER:** reconcile the fps on `dome_v3` and `dome_v5`, at 250 m by night and in the follow view,
   with the saves' weather.
2. **RENDER / UI:** POI labels draw through the dome walls into the arcade and club. Hide them.
3. **RENDER:** add the prism ship to the Prism Shift screen.
4. **RENDER:** in a dust storm the dome goes dim and brown. Exempt the windows and neon from the storm
   fog.
5. **ART-B:** a back-bar with bottle rows and a mirror.
6. **ART-B:** the RESTAURANT sign is still clipped in the follow view.
7. **ART-NPC:** the robot dancers.

## follow_view — round-29 fixes

| fix | result |
|---|---|
| Camera spec (1.9 m back, 0.55 m right, about 1.8 m up, 10° down) | **Landed.** |
| Left third | **Landed** in 153. In my run the person was centred. |
| Bubbles (size, rim, tail, 6 s line) | **Landed.** |
| Collision | **Dither only.** No pull-in. |
| Panels over the scene | **Still over the scene.** |

**Fixes.**
1. **RENDER:** pull the camera in when it is blocked.
2. **UI:** fold the hazard and alert panels while following.
3. **RENDER:** keep the left-third framing when the person stands still.
