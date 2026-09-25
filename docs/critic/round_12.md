# Critic round 12 — v3.1 art from Blender evidence

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9, V3_1 §3, §5, §6, §8 ·
Pass ≥ 0.65 · Same calibration as rounds 1–11. The full detail is in `round_12.json`.

## Scores

| subject | cons. | appeal | style | score | before | result |
|---|---|---|---|---|---|---|
| visitors | 0.78 | 0.74 | 0.76 | **0.76** | new | PASS, provisional |
| airlock | 0.80 | 0.76 | 0.80 | **0.79** | 0.76 | PASS, provisional |
| doors | 0.80 | 0.76 | 0.80 | **0.79** | 0.75 | PASS, provisional |
| doorway_decals | 0.82 | 0.76 | 0.80 | **0.79** | 0.77 | PASS, provisional |
| landing_pad (part of ships) | 0.78 | 0.72 | 0.76 | **0.75** | new | PASS |
| ships | 0.80 | 0.76 | 0.78 | **0.78** | 0.75 | PASS, provisional |

**No fails.** All are provisional until the in-game round.

## Claims checked

- **Visitors:** every kind reads apart from the colonist at 55 px. The `suit_swap` clip reads (hands to
  the helmet, hold, hands to the chest seals).
- **Airlock:**
  - **Landed:** the M/L sizes with 2.4 m and 3.6 m chambers, the amber beacon, the fairing and the
    porch grate.
  - **Not borne out:** "cut at 1.40 m". In the cutaway renders the chamber walls and door housings
    still stand well above the outer wall ring.
- **Doors:** the curved housing, hood, green strip, kick plates and chevrons landed.
- **Decals:** 13 room types show no decal on any opening, and the bands end with caps.
- **Ships:** round-11 fixes 1–4 and 6–8 landed. Fix 5: the night-ramp renders exist, but no belly or
  ramp flood is visible.

## Fixes by owner

**ART-HAB**
1. **Airlock cutaway.** Cut the chamber walls and door housings at 1.40 m with solid caps, or move
   their upper parts into the Roof group. Show one render.
2. **Door hood through a tank.** On water recycler M the hood cuts a wall tank (`r12_wr_roof.png`).
   Move or hide the tank with its segment.
3. **Flat-roof rooms.** Use a flat hood; the curved hood sits on the roof as a loose shell
   (`r12_ref_roof.png`).
4. **Upper wall patch.** Carry the band to the cap on podium and drum rooms.
5. **Airlock pressure lights.** Make them 8 cm lamps on a dark plate.
6. **Pad.**
   - An angled blast deflector with a top rail, scorch and a stripe.
   - A fuel station with a hose reel and a fuel stripe.
   - A kiosk with a lit window and a mast light.
   - Walkway lanes and tie-downs on the apron.

**ART-NPC**
1. **Tourists at 30 px.** The tourists and the scientist are all "white with a colour patch". Carry
   the tourist colour to the indoor lower legs and boots.
2. **Indoor trader.** A graphite vest with a hi-vis stripe, or a hat, so it does not read as an
   orange-role colonist.
3. **Inspector at night.** Gold reflective stripes on the black suit's legs and pack.
4. **Inspector cap.** A variant that fits the bun head, instead of skipping that head.

**ART-B / RENDER**
1. **Night floods.** Make the belly and ramp floods visible: a lens and a warm pool on the ramp and
   the deck.

**RENDER**
1. Run the in-game decal acceptance on every room type.
2. Merge the decal objects, about 90 per room.
3. Show the black inspector at night.

## Evidence

- `art/npc/visitors_lineup.png`, `visitors_turnaround.png`, `transitions.png` (suit_swap).
- `art/interiors/airlock*`, `door31_*`, the 13 `*_doorways*.png` pairs, `pad31_*`.
- `art/ships/*`, including `*_night_ramp.png`, `fleet_lineup.png` and `fleet_top.png`.
- My grids and crops: `art/critic/r12_*.png`.
