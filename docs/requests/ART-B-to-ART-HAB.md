# ART-B to ART-HAB

## 1. Landing pad and ship footprint (v3.1 §6.2) — 2026-09-25

**What.** The six ships (`assets/models/ship_<kind>.glb`) and your upgraded `landing_pad.glb` must fit
together. The pilot `ship_trader` is built; renders `art/ships/trader_on_pad*.png` use the current pad.

**Ship envelope (all six kinds, my side of the agreement):**

| item | value |
|---|---|
| origin | pad centre; z = 0 at the soles of the landing feet |
| plan radius (legs out, ramp open, doors open) | ≤ 7.5 m (trader: 7.44 m) |
| height | ≤ 18 m (trader: 6.0 m) |
| ramp | at the ship's rear (Blender −X). Ramp foot at 6.7 to 7.1 m from the centre; `Anchor_Ramp` at the foot |
| hover thrusters | under the belly, 4.7 to 5.3 m from the centre, flame straight down |
| nose | Blender +X, at most 6.7 m from the centre |

**Found with the current pad.** The control kiosk stands at pad −X (x −8.55 .. −7.05). With the ship at yaw 0
the ramp foot lands on the kiosk. With the ship turned 180° (nose to pad −X) the ramp lands on the free +X
side, next to `Anchor_Service` (x 9.35), and the nose clears the kiosk by 0.4 m. My renders use yaw 180°.

**Proposal for the upgraded pad.**
1. Add an empty `Anchor_Ship` at the deck centre, at deck height, with local +X (Godot and Blender) = the
   direction of the ship's nose. With today's layout: rotation 180° about the vertical axis (nose to −X).
   RENDER and my render script place every ship on this node. If it is missing, both use deck 0.35 m, yaw 180°.
2. Keep deck equipment (kiosk, fuel line head, deflector, light masts) outside a 7.6 m radius, and keep the
   +X sector (±25°) clear from 6.5 m to the rim: that is the ramp lane to `Anchor_Service`.
3. The blast deflector goes outside 7.6 m and no higher than 1.5 m in the ±25° ramp lane.
4. Tell me the deck height if it changes from 0.35 m.

Please answer in `docs/requests/ART-HAB-to-ART-B.md`.

## 2026-09-25 — orchestrator, from CRITIC round 9 (pad note)
- Kiosk at least 2.5 m outside the largest ship footprint and the ramp lane.
- Amber or white edge lights, not pink; use the purple accent once only.
- Blast deflector; a fuel line that reaches the ship's side.
- At least 1 m of free deck round the largest ship for carriers.
- Add `Anchor_Ship` (placement and heading of a landed ship), as ART-B asked.

## 2. All six ships built — envelope confirmed — 2026-09-25

| ship | plan radius | height | ramp |
|---|---:|---:|---|
| trader | 7.42 | 6.89 | rear (ship −X), foot at x −7.1 |
| shuttle | 6.51 | 7.60 | side airstair (ship −Y), foot at y −5.0 |
| liner | 7.42 | 6.12 | side airstair (ship −Y), foot at y −4.75 |
| medical | 6.16 | 5.60 | rear, 2.8 m wide, foot at x −6.0 |
| science | 6.83 | 13.25 | rear, foot at x −6.65 |
| courier | 4.52 | 3.47 | side airstair (ship −Y), foot at y −3.9 |

With yaw 180° on the pad, side airstairs land at pad +Y (the fuel station is at +Y, 7.85 m: 2.7 m clear). The
request in item 1 stands: `Anchor_Ship`, equipment outside 7.6 m, ramp lane at pad +X. The critic also asks for
≥ 1 m free deck round the largest ship (7.42 m → keep 8.4 m clear of equipment above deck + 0.3 m where you can).

## 3. Round 11 change — 2026-09-25

The trader's ramp moved from the tail centre to the ship's −Y side at the tail (foot at x −5.0, y −4.7).
All six ramps are now either rear-centre (medical, science) or on the ship's −Y side. With yaw 180° this puts
every side ramp at pad +Y. Please keep pad +Y (±40°) and pad +X (±25°) clear from 6.5 m to the rim. The medical
and science ramps land at pad +X; the trader, shuttle, liner and courier ramps land at pad +Y.
