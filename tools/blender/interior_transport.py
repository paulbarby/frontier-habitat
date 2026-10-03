"""
Frontier Habitat 5.0 - ART-HAB: package transport models (docs/V5_DESIGN.md section 18.5, end game).

Run from the project root:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/interior_transport.py -- [--only transport_tube,transport_hub_m]

Capsules are RENDER's.  Every height is in the frame of the piece it goes with (z 0 = the room ground; the room floor
top is 0.14 m).  Contract (docs/requests/ART-HAB-to-RENDER.md, ART-HAB-to-SIM.md, 2026-10-04):

assets/models/transport_tube.glb      the corridor upgrade, like corridor.glb: 1.0 m on X (x -0.5 .. 0.5), the game
    scales it on X and places it with the corridor's own transform.  Object Roof (hidden in the cutaway with the
    corridor roof): a clear tube under the corridor's glass ridge, centre line y 0, z TUBE_Z (2.255 in the corridor
    frame = 2.305 over the room ground, the corridor sits 5 cm up), outer radius 0.09, inside radius 0.078 (a capsule
    up to 0.065 m radius fits), a lit strip under it.  At a room end it plugs into the doorway collar and header
    (above the 2.24 m opening, under the 2.46 m collar top); at a junction mouth it goes through the upper patch.
assets/models/transport_bracket.glb   not scaled (x -0.07 .. 0.07): the coupling sleeve and the hanger up to the
    glass ridge.  Place one with every corridor_rib (first 1.25 m from the start, every 2.5 m).  Object Roof.
assets/models/transport_junction.glb  the junction piece: origin = the junction centre on the ground, scaled with the
    junction like its other parts.  A manifold drum on the wayfinding totem (z 2.14 .. 2.47, radius 0.30) with a
    socket band at the tube height (z 2.305): the game draws a straight transport_tube from each mouth (radius Rw)
    to radius 0.31, along the mouth's direction.  Object Roof (hidden in the cutaway).
assets/models/transport_port.glb      at each doorway of a room with a Transport hub, with the doorway's transform
    (origin on the wall line, +X out along the corridor): the parcel port on the room side over the door housing,
    x -0.47 .. -0.21, y -0.34 .. 0.34, z 2.60 .. 2.90 (over the door top 2.24 + 0.25 m).  Object PortTop: hide it in the
    cutaway like FrameTop.  Anchor_Port = the port mouth (x -0.48, y 0, z 2.73), facing -X (into the room).
assets/models/transport_hub_<s|m|l|xl>.glb   the sorter, placed at Anchor_Hub of storehouse_* / cold_storage_* (a
    reserved, marked pad in every size; origin = the room ground, local +X = the front with the in-feed conveyor).
    Footprint x -0.70 .. 1.00 (with the in-feed tray), y -0.50 .. 0.50; the machine is 1.80 m high and two clear tube
    risers go up to the deck (2.90 / 2.90 / 3.10 / 3.30 m for S / M / L / XL: both storage types use these decks).
    Object Interior (drawn in the cutaway like the furniture).  Anchor_HubIn = the in-feed tray (x 0.85, z 0.95).
"""
import bpy
import os
import sys
import json
import time
from math import cos, sin, radians, pi

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K               # noqa: E402
import interior_links as L          # noqa: E402
import interior_props as PR         # noqa: E402
from rooms_kit import P, T, RX, RY, RZ, FLOOR_Z  # noqa: E402
from interior_kit import bbox, plate_x, plate_y, plate_z  # noqa: E402

F = FLOOR_Z
CORR_Z = 0.05                     # the corridor model sits 5 cm over the room ground (fx_doors / interior_render)
TUBE_Z = 2.255                    # tube centre in the corridor frame
TUBE_W = TUBE_Z + CORR_Z          # 2.305 over the room ground
TUBE_R = 0.09
TUBE_RI = 0.078
RIDGE_Z = L.WALL_H + 1.355        # 2.355: the inside of the corridor's glass ridge
DECKS = {"s": 2.90, "m": 2.90, "l": 3.10, "xl": 3.30}
REPORT = os.path.join(HERE, "transport_report.json")


def plate_down(p, z, x0, x1, y0, y1, mat):
    """Flat quad at height z facing down."""
    p.quad((x0, y0, z), (x0, y1, z), (x1, y1, z), (x1, y0, z), mat)


def build_tube():
    r = P("Roof")
    seg = 10
    r.cyl((-0.5, 0.0, TUBE_Z), (0.5, 0.0, TUBE_Z), TUBE_R, seg=seg, mat="Glass", smooth=True, cap0=False, cap1=False)
    # the track inside (a capsule runs on it) and a lit strip under the tube (reads at night)
    bbox(r, -0.5, 0.5, -0.015, 0.015, TUBE_Z - TUBE_RI, TUBE_Z - TUBE_RI + 0.012, "Frame", mats={"+x": None, "-x": None})
    plate_down(r, TUBE_Z - TUBE_R - 0.004, -0.5, 0.5, -0.012, 0.012, "LightStrip")
    # the spine the hangers clip on (under the glass ridge)
    bbox(r, -0.5, 0.5, -0.02, 0.02, TUBE_Z + TUBE_R + 0.005, TUBE_Z + TUBE_R + 0.025, "Frame",
         mats={"+x": None, "-x": None, "-z": None})
    return {"Roof": r}, []


def build_bracket():
    r = P("Roof")
    # a coupling sleeve over the tube, two rings
    r.cyl((-0.06, 0.0, TUBE_Z), (0.06, 0.0, TUBE_Z), TUBE_R + 0.018, seg=12, mat="Frame", cap0=True, cap1=True)
    for x in (-0.065, 0.065):
        r.cyl((x - 0.008, 0.0, TUBE_Z), (x + 0.008, 0.0, TUBE_Z), TUBE_R + 0.026, seg=12, mat="Metal", cap0=True,
              cap1=True)
    # hanger to the ridge
    bbox(r, -0.02, 0.02, -0.02, 0.02, TUBE_Z + TUBE_R + 0.018, RIDGE_Z + 0.01, "Metal", mats={"-z": None})
    bbox(r, -0.06, 0.06, -0.09, 0.09, RIDGE_Z - 0.02, RIDGE_Z + 0.01, "Frame", mats={"+z": None})
    # a status lamp on the sleeve (green: the line is up)
    bbox(r, -0.02, 0.02, -0.015, 0.015, TUBE_Z - TUBE_R - 0.034, TUBE_Z - TUBE_R - 0.016, "StatusGreen")
    return {"Roof": r}, []


def build_junction():
    r = P("Roof")
    z0, z1 = TUBE_W - 0.165, TUBE_W + 0.165
    r.vcyl(0, 0, z0, z1, 0.30, seg=16, mat="Hull", cap0=True)
    # the socket band at the tube height (the radial tubes plug in anywhere round it)
    r.vcyl(0, 0, TUBE_W - TUBE_R - 0.02, TUBE_W + TUBE_R + 0.02, 0.315, seg=16, mat="Frame", cap0=False, cap1=False)
    # a clear sorting window over the band with a carousel inside, a lit disc on top (as the totem's screen)
    r.vcyl(0, 0, z1, z1 + 0.10, 0.24, seg=16, mat="Glass", cap0=False, cap1=False)
    r.vcyl(0, 0, z1 + 0.10, z1 + 0.13, 0.26, seg=16, mat="Frame")
    with r.at(T(0, 0, z1 + 0.131)):
        r.cap_disc(0.17, 0.0, "Screen", seg=12)
    for k in range(6):
        a = radians(60.0 * k + 15.0)
        x, y = 0.15 * cos(a), 0.15 * sin(a)
        bbox(r, x - 0.035, x + 0.035, y - 0.035, y + 0.035, z1 + 0.005, z1 + 0.06, "Hazard")
    plate_down(r, z0 - 0.003, -0.22, 0.22, -0.012, 0.012, "LightStrip")
    r.torus(0.29, 0.012, "LightStrip", seg=16, tseg=4, z=z0 + 0.012)
    return {"Roof": r}, []


def build_port():
    p = P("PortTop")
    x0, x1 = -0.47, -0.21
    zb, zt = 2.60, 2.88
    bbox(p, x0, x1, -0.34, 0.34, zb, zt, "Hull", bevel=0.02)
    bbox(p, x0 - 0.004, x0, -0.34, 0.34, zb + 0.20, zb + 0.235, "Hazard")
    # the mouth: a ring and a clear cap facing the room
    with p.at(T(x0, 0.0, 2.73), RY(-90.0)):
        p.cyl((0, 0, 0.0), (0, 0, 0.045), TUBE_R + 0.03, seg=12, mat="Frame", cap0=False, cap1=True)
    with p.at(T(x0 - 0.046, 0.0, 2.73), RY(-90.0)):
        p.cap_disc(TUBE_R - 0.005, 0.0, "Glass", seg=12)
    # status lamps and a stub into the deck over it
    for y in (-0.25, 0.25):
        bbox(p, x0 - 0.012, x0, y - 0.025, y + 0.025, 2.80, 2.84, "StatusGreen")
    p.vcyl(-0.34, 0.0, zt, zt + 0.04, 0.06, seg=8, mat="Frame", cap0=False)
    with p.at(T(x0 - 0.001, 0.0, 0.0)):
        with p.at(RZ(180.0)):
            PR.text(p, "PARCELS", 0.0, 2.645, 0.032, "HullDark", x=0.0)
    return {"PortTop": p}, [("Anchor_Port", (-0.48, 0.0, 2.73), 180.0)]


def build_hub(size):
    deck = DECKS[size]
    n = P("Interior")
    # cabinet
    bbox(n, -0.70, 0.70, -0.50, 0.50, F, F + 0.12, "HullDark")
    bbox(n, -0.68, 0.68, -0.48, 0.48, F + 0.12, F + 0.95, "Hull", bevel=0.02)
    for sy in (-1, 1):
        plate_y(n, sy * 0.481, -0.6, 0.6, F + 0.70, F + 0.76, "Accent", facing=sy)
    # in-feed conveyor on the front (+X), rollers, a parcel on it
    bbox(n, 0.68, 1.00, -0.30, 0.30, F + 0.70, F + 0.80, "Frame")
    for k in range(4):
        x = 0.72 + 0.075 * k
        n.cyl((x, -0.28, F + 0.815), (x, 0.28, F + 0.815), 0.02, seg=6, mat="Metal", cap0=False, cap1=False)
    for sy in (-1, 1):
        bbox(n, 0.90, 0.96, sy * 0.24 - 0.03, sy * 0.24 + 0.03, F, F + 0.70, "Frame")
    bbox(n, 0.74, 0.94, -0.13, 0.13, F + 0.835, F + 0.995, "Wood", bevel=0.01)
    plate_z(n, F + 0.996, 0.80, 0.88, -0.13, 0.13, "Hazard")
    # front panel: screen, name and the joke
    plate_x(n, 0.681, -0.40, 0.40, F + 0.30, F + 0.62, "HullDark")
    plate_x(n, 0.683, -0.34, 0.06, F + 0.36, F + 0.58, "Screen")
    PR.text(n, "SORT-O-MATIC", 0.20, F + 0.53, 0.035, "Hazard", x=0.684)
    PR.text(n, "IF IT FITS", 0.20, F + 0.45, 0.026, "Hull", x=0.684)
    PR.text(n, "IT SHIPS", 0.20, F + 0.40, 0.026, "Hull", x=0.684)
    for k, m in enumerate(("StatusGreen", "StatusGreen", "Hazard")):
        bbox(n, 0.681, 0.70, -0.38 + 0.06 * k - 0.02, -0.38 + 0.06 * k + 0.02, F + 0.66, F + 0.69, m)
    # the clear sorting drum with a carousel and parcels
    n.vcyl(0, 0, F + 0.95, F + 1.00, 0.46, seg=16, mat="Frame")
    n.vcyl(0, 0, F + 1.00, F + 1.62, 0.42, seg=16, mat="Glass", cap0=False, cap1=False)
    n.vcyl(0, 0, F + 1.62, F + 1.70, 0.46, seg=16, mat="Frame")
    n.vcyl(0, 0, F + 1.70, F + 1.80, 0.30, seg=12, mat="Hull")
    n.vcyl(0, 0, F + 1.00, F + 1.60, 0.04, seg=8, mat="Metal", cap0=False)
    for lvl, zz in enumerate((F + 1.12, F + 1.38)):
        n.vcyl(0, 0, zz - 0.015, zz, 0.32, seg=12, mat="Frame")
        for k in range(5):
            a = radians(72.0 * k + 30.0 * lvl)
            x, y = 0.22 * cos(a), 0.22 * sin(a)
            bbox(n, x - 0.06, x + 0.06, y - 0.05, y + 0.05, zz, zz + 0.09, ("Wood", "Accent", "Hazard")[(k + lvl) % 3])
    n.torus(0.44, 0.015, "LightStrip", seg=16, tseg=4, z=F + 1.66)
    # two clear risers to the deck, with couplings
    for sy in (-1, 1):
        y = sy * 0.16
        n.vcyl(0, y, F + 1.80, deck, TUBE_R, seg=10, mat="Glass", cap0=False, cap1=False)
        for zz in (F + 1.82, (F + 1.80 + deck) / 2.0, deck - 0.06):
            n.vcyl(0, y, zz, zz + 0.05, TUBE_R + 0.02, seg=10, mat="Frame")
        n.vcyl(0, y, deck - 0.02, deck, TUBE_R + 0.06, seg=10, mat="Frame", cap0=False)
    # side label
    with n.at(RZ(90.0)):
        PR.text(n, "TRANSPORT HUB", 0.0, F + 0.86, 0.045, "HullDark", x=0.481)
    with n.at(RZ(-90.0)):
        PR.text(n, "NO RIDING", 0.0, F + 0.86, 0.040, "HullDark", x=0.481)
    return {"Interior": n}, [("Anchor_HubIn", (0.85, 0.0, F + 0.81), 0.0)]


BUILDS = {
    "transport_tube": (build_tube, 200),
    "transport_bracket": (build_bracket, 300),
    "transport_junction": (build_junction, 500),
    "transport_port": (build_port, 700),
}
for _s in DECKS:
    BUILDS["transport_hub_%s" % _s] = ((lambda s_=_s: build_hub(s_)), 3200)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    rows = []
    for name, (fn, budget) in BUILDS.items():
        if only and name not in only:
            continue
        t0 = time.time()
        parts, anchors = fn()
        path = L.export_parts(name, parts, anchors)
        row = L.check_file(name, path, parts, budget)
        row["seconds"] = round(time.time() - t0, 1)
        rows.append(row)
        print("TRANSPORT %-22s %5d/%-5d tris  %s  %s" % (name, row["tris"], budget, row["materials"],
                                                         "; ".join(row["flags"]) or "ok"))
    json.dump(dict(generator="interior_transport.py", models=rows), open(REPORT, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
