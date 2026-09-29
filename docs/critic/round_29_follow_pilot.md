# Critic round 29 — v5.0 `follow_view` pilot (in game)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.4 · Pass ≥ 0.65.
The full detail is in `round_29_follow_pilot.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| follow_view (pilot, v3 models) | 0.66 | 0.64 | 0.70 | **0.67** | PASS, provisional |

## Evidence

- RENDER's sheet `art/critic_input/render/150_v5_follow_view_pilot.png`: 12 tiles.
- **My own unstaged run:** `build/web_render` (18:47), `showcase_v3_late`, speed 1.
  - 8 colonists followed, 5 frames each, with `followinfo` logged.
  - The files are in `art/critic/r29/` and `r29_grid.png`.

## What works

- **Following.** Smooth: 8 of 8 people followed through rooms, corridors and airlocks with no jump.
- **Cutaway.** It opens the person's and the camera's rooms.
- **Bubbles.** Glass style with a name, 1–2 lines and an emote. They are stacked, never overlap, and
  are readable. SIM's real talks drive them.
- **HUD.** The newer build already dims it and shows the follow card.
- **Performance.** 47.5 fps and 1,080 draw calls indoors (the target is ≥ 45 fps).

## Fixes (RENDER unless named), most important first

1. **Camera off spec.** It measures 3.0 m from the body and 2.25 m above the feet, so it looks down on
   the top of the head. Use 0.55 m right, 1.9 m back, eye + 0.15 m, and 8–12° down.
2. **Framing.** The person is centred and blocks the view. Put them on the left third with look room
   ahead.
3. **Collision.** In tile 4 the camera is pressed against a ship hull, and in tile 1 a stove wall fills
   half the view. Sphere-cast from head to camera, pull in, and hide props between them.
4. **RENDER / UI: screen space.** The inspector stays open on the right third, and toasts cover the
   scene. Collapse the inspector to the follow card, and move toasts to the top edge.
5. **Bubble text.** Lines to 14 px and names to 12 px, a 1 px metal rim, and the tail on the
   speaker's head (tile 8 misses).
6. **Silence.** 5 of 8 follows had no bubble for 4 s. Keep the followed person's last line for 6 s.
7. **RENDER / SIM: frame spikes.** 18 frames over 50 ms in 20 s. §0 allows none in 120 s.

## What waits for the new people models

- Close-up quality at 1.5 m (faces, hands, cloth). The v3 astronauts cap appeal now.
- The outfit rule in view (uniform on shift, casual off shift).
- Paired clips in the frame.

**Not yet shown:** floors, the dome gallery, a 30-person crowd.
