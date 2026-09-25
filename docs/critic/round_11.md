# Critic round 11 — ships: the full fleet (Blender renders)

Date: 2026-09-25 · Critic (did not build the work) · Rubric: V3_DESIGN §9 and V3_1 §6.2 / §8 ·
Pass ≥ 0.65 · Same calibration as rounds 1–10. The full detail is in `round_11.json`.

## Score

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| ships (6 ships) | 0.78 | 0.72 | 0.74 | **0.75** | PASS, provisional (in-game landing round to come) |

| ship | alone | note |
|---|---|---|
| trader | 0.76 | The round-9 fixes landed. It is the most detailed ship. |
| shuttle | 0.70 | From the top it is a plain white capsule. It is the weakest. |
| liner | 0.72 | It has fins and a pink band, but it is not a dart. The pink does not show from the top. |
| medical | 0.74 | The red roof cross reads at any distance. |
| science | 0.74 | The dish mast is a unique silhouette. |
| courier | 0.74 | A black-gold wedge, clearly the smallest. |

**No single ship is below 0.65.**

## Evidence

- `art/ships/`: all 30 per-ship renders, `fleet_lineup.png`, `fleet_top.png`.
- The maker's log: `docs/progress/ART-B.md`, newest section.
- My own: `art/critic/r11_night.png`, `r11_pad.png`, `r11_flight.png`, and `r11_top_gamedist.png`
  (the top view at 25% scale).

## Round-9 fixes

| fix | result |
|---|---|
| 1 Faceted bridge, dark glass by day | **Landed.** |
| 2 Hazard frames, flank insets, rails, ladder, `TR-07` | **Landed.** |
| 3 Thicker legs, ram, foot | **Landed.** |
| 4 Engine bells with glowing cone | **Landed.** |
| 5 Night lights | **Nav lights, strobe and windows landed.** No render shows the belly floods. |
| 6 Ribbed containers | **Landed.** |
| 7 Ramp clear of the engines | **Partly.** The engines are raised, but the ramp still lands between the two bells. |
| 8 File names | **Landed.** |

## What works

- **One fleet.** The ships share legs, engines, bridge frames, rails, hazard frames, registration
  codes and palette, and they sit well with the colony.
- **From the side.** Each ship has one colour and one cue: pods, window rows, fins, cross, dish,
  wedge.
- **At night.** Every ship can be found.

## Fixes (ART-B), most important first

1. **Top view.** Five ships share one capsule plan, and the shuttle is a plain white capsule from
   above. Give the shuttle a graphite roof with a yellow stripe and a raised passenger deck, 0.6 m high
   along the rear two thirds.
2. **Liner as a dart.** Give it a 2.5 m tapered nose instead of the shared bridge, a plan 0.8 × the
   trader's width, swept fins visible from above, and the pink band along the roof spine.
3. **Different cockpits.** The same bridge on all six gives six identical yellow windscreens at night.
   Use a bus windscreen on the shuttle, a wraparound band on the liner and a canopy on the courier.
4. **Night windows.** They are flat saturated yellow. Use #FFD9A0 at about 60% of the current
   strength, with dark mullions. Passenger windows are dimmer than the bridge.
5. **Night renders.** Add one night render per ship from the ramp side, to show the belly floods.
6. **Trader ramp.** Move it to one side of the tail.
7. **Flight renders.** Centre the ship over the pad. The shuttle and the science ship now intersect
   the kiosk.
8. **Flank panels.** Add 2–3 flat panel insets per flank on the shuttle, medical and science ships,
   to match the colony's detail density.

## Pad (note only, ART-HAB)

- The kiosk stands 1–2 m from the nose of every ship. Place it outside the largest footprint and ramp
  lane.
- Use amber or white edge lights, not pink.
