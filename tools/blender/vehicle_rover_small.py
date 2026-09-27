"""
Frontier Habitat 4.0 - small rover (V4_DESIGN section 5). ART-B. Blender 5.2, --background only.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_rover_small.py

Writes assets/models/vehicle_rover_small.glb (contract: vehicle_common.py docstring).
Design: a 6-wheel work rover in the fleet language - white faceted hood, graphite chassis and cage, amber
accent (fenders, springs, hub caps, stripes), hazard-yellow markings, stencilled code RV-01.
2 seats side by side in an open cab under a roll cage with a solar sunshade; low seat backs (the suit pack rests
above them, ART-NPC sit contract); cargo bed with a drop tailgate; 6 coil-over struts; front and rear axles steer.
"""
import os
import sys
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vehicle_common as V                                 # noqa: E402
from vehicle_common import Node, Anchor, T, RX, RY, RZ, S, GRAPHITE, PLATE, SOLAR, LENS, INK   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402
import ship_common as SC                                   # noqa: E402

VID = "rover_small"
R_W = 0.44            # tyre radius
HW = 0.17             # tyre half width
Y_HUB = 1.06          # hub centre |y|
Y_KP = 0.76           # strut / kingpin |y|
Z_HUB = R_W
FLOOR = 0.92          # cab floor = chassis top
WHEELS = [("FL", 1.75, 1, 1), ("FR", 1.75, -1, 1), ("ML", 0.0, 1, 0), ("MR", 0.0, -1, 0),
          ("RL", -1.40, 1, -1), ("RR", -1.40, -1, -1)]      # (id, x, side, steer_sign)
DROP = -0.10          # critic round 16 fix 2: the body sits 10 cm lower (hubs and wheels unchanged)
FW = FLOOR + DROP     # world floor height (0.82)
BOARD_Z = FW - 0.32   # running-board top = the door point height (0.50)
KIT = V.WheelKit(k=1.0, travel=(-0.15, 0.12), steer_max=25.0)
FX = 0.37             # the nose moved forward with the front axle (ART-NPC door gap)
SEAT_X = 0.66         # seat centre (anchor 0.30 ahead of it, at x 0.96)
SEAT_Y = 0.40
ANCHOR_X = SEAT_X + 0.30
# ART-NPC vehicle_seat contract, relative to the seat anchor: grips (0.235, +-0.19, 0.90), grab (0.25, 0.30, 0.76)
# Measured on ART-NPC's clips (vehicle_fit.py): the grip centres (prop.L/R) in drive_sit sit at (0.30, +-0.142, 0.925);
# the grab hand in board / alight at (0.261, 0.316, 0.725). The handles are placed there (not at the wrist points).
GRIP = (ANCHOR_X + 0.298, FLOOR + 0.925)       # pre-drop x, z of the two vertical driver handles (axis, centre)
GRIP_Y = 0.142
GRAB = (ANCHOR_X + 0.261, SEAT_Y + 0.316, FLOOR + 0.725)
DASH = 1.42           # dash / hood rear: clear of the door zone (ART-NPC: anchor x -0.60 ... +0.40)
PILLAR = (1.46, 0.0)
ROOF_Z = 2.58         # headroom: rails underside 1.62 m above the floor (contract >= 1.60)
REG = "RV-01"


def body_parts(b, lights):
    with b.at(T(0, 0, DROP)), lights.at(T(0, 0, DROP)):
        body_upper(b, lights)
    for wid, x, sy, st in WHEELS:
        KIT.strut_top(b, x, sy, Y_KP, Z_HUB)
    # skid plate (round 16 fix 2): bare metal under the chassis, sloping up at the nose
    b.box((0.085, 0, 0.43), (3.67, 1.16, 0.06), "Palette:#9aa3ad")
    b.beam((1.91, 0, 0.43), (2.33, 0, 0.64), 1.16, 0.06, "Palette:#9aa3ad", up=(-0.45, 0, 1))
    for y in (-0.40, 0.0, 0.40):
        b.beam((-1.60, y, 0.395), (1.85, y, 0.395), 0.05, 0.03, GRAPHITE)


def body_upper(b, lights):
    """pre-drop coordinates (the caller lowers all of it by DROP). Layout v3 (ART-NPC seat contract):
    front axle 1.75 so the side door gap (x 0.51-1.24) takes a standing colonist; dash at x 1.30."""
    F = FX
    # ---- chassis (graphite), hood (white, faceted), bumper ------------------------------------
    b.prism_y([(-1.95, 0.56), (1.60 + F, 0.56), (1.98 + F, 0.80), (1.98 + F, FLOOR), (-1.95, FLOOR)], -0.66, 0.66, GRAPHITE)
    hood = []
    for sy in (-1, 1):
        hood += [(DASH, sy * 0.68, FLOOR), (2.02 + F, sy * 0.62, FLOOR), (2.04 + F, sy * 0.54, 1.04),
                 (1.72 + F, sy * 0.66, 1.16), (DASH + 0.05, sy * 0.66, 1.34)]
    b.hull(hood, "Palette:Hull")
    b.beam_path([(2.045 + F, 0, 1.05), (1.72 + F, 0, 1.172), (DASH + 0.05, 0, 1.352)], 0.26, 0.02, "Accent")   # hood stripe
    for sy in (-1, 1):
        b.beam((DASH + 0.13, sy * 0.672, 1.02), (1.95 + F, sy * 0.63, 0.99), 0.02, 0.07, "Palette:Hazard", up=(0, sy, 0))
    b.beam((2.14 + F, -0.82, 0.70), (2.14 + F, 0.82, 0.70), 0.12, 0.16, GRAPHITE)
    for sy in (-1, 1):
        b.beam((1.96 + F, sy * 0.45, 0.70), (2.09 + F, sy * 0.45, 0.70), 0.10, 0.10, GRAPHITE)
        b.box((2.205 + F, sy * 0.58, 0.70), (0.012, 0.22, 0.12), "Palette:Hazard")
    b.box((2.205 + F, 0, 0.70), (0.012, 0.22, 0.12), "Palette:Hazard")
    for y in (-0.44, -0.28, 0.28, 0.44):                                    # headlights
        V.lens(b, lights, (2.035 + F, y, 0.975), (1, 0, 0), 0.05, housing=(0.05, 0.13, 0.10))
    # ---- cab: floor plate, dash screens, windscreen, grips, grab handles, seats ------------------
    b.box(((DASH - 0.45) / 2, 0, FLOOR + 0.006), (DASH + 0.45, 1.26, 0.012), PLATE)
    b.box((DASH - 0.005, SEAT_Y, 1.21), (0.02, 0.30, 0.16), "Screen")
    b.box((DASH - 0.005, -SEAT_Y, 1.21), (0.02, 0.20, 0.12), "Screen")
    gx, gz = GRIP
    b.cyl((DASH, SEAT_Y, 1.20), (gx + 0.07, SEAT_Y, gz - 0.13), 0.03, seg=6, mat=GRAPHITE)              # column
    b.beam((gx + 0.07, SEAT_Y - GRIP_Y - 0.02, gz - 0.13), (gx + 0.07, SEAT_Y + GRIP_Y + 0.02, gz - 0.13),
           0.04, 0.04, GRAPHITE)
    for sy_ in (-1, 1):                                                     # two vertical handles (drive_sit)
        y = SEAT_Y + sy_ * GRIP_Y
        b.beam((gx + 0.07, y, gz - 0.13), (gx, y, gz - 0.13), 0.03, 0.03, GRAPHITE)
        b.cyl((gx, y, gz - 0.14), (gx, y, gz + 0.09), 0.018, seg=6, mat="Accent")
    hx, hy, hz = GRAB
    for sy in (-1, 1):                                                      # grab handles on the front pillars
        b.cyl((hx, sy * hy, hz - 0.10), (hx, sy * hy, hz + 0.10), 0.018, seg=6, mat="Accent")
        for dz in (-0.10, 0.10):
            b.beam((hx, sy * hy, hz + dz), (PILLAR[0] + 0.04, sy * 0.63, hz + dz), 0.03, 0.03, GRAPHITE)
    ws0, ws1 = Vector((DASH + 0.06, 0, 1.34)), Vector((DASH + 0.03, 0, 1.62))     # low screen: under the hands
    q = [Vector((ws0.x, -0.60, ws0.z)), Vector((ws0.x, 0.60, ws0.z)), Vector((ws1.x, 0.58, ws1.z)), Vector((ws1.x, -0.58, ws1.z))]
    nrm = (q[1] - q[0]).cross(q[3] - q[0])
    SC.emit_oriented(b, q, nrm if nrm.x > 0 else -nrm, SC.DGLASS)
    SC.emit_oriented(b, [x - Vector((0.012, 0, 0)) for x in q], -(nrm if nrm.x > 0 else -nrm), SC.DGLASS)
    b.beam((ws1.x, -0.62, ws1.z + 0.02), (ws1.x, 0.62, ws1.z + 0.02), 0.06, 0.05, GRAPHITE)
    for sy in (-1, 1):
        c = Vector((SEAT_X, sy * SEAT_Y, 0))
        b.box((c.x, c.y, FLOOR + 0.20), (0.26, 0.30, 0.36), GRAPHITE)                          # pedestal
        b.box((c.x, c.y, FLOOR + 0.41), (0.44, 0.50, 0.10), "Palette:#3c4a5e", bevel=0.045)    # cushion (top 0.46), edges rounded 4.5 cm
        b.box((c.x - 0.25, c.y, FLOOR + 0.52), (0.07, 0.44, 0.16), "Palette:#3c4a5e")          # low back (<0.60)
    # ---- cage + sunshade + light bar + beacon + whip ------------------------------------------
    tube = GRAPHITE
    px = PILLAR[0]
    for sy in (-1, 1):
        b.cyl((px + 0.06, sy * 0.63, 1.30), (px, sy * 0.62, ROOF_Z), 0.04, seg=6, mat=tube)
        b.cyl((px, sy * 0.62, ROOF_Z), (-0.50, sy * 0.64, ROOF_Z), 0.04, seg=6, mat=tube)
    b.tube([(-0.50, 0.64, FLOOR), (-0.50, 0.64, ROOF_Z), (-0.50, -0.64, ROOF_Z), (-0.50, -0.64, FLOOR)], 0.045,
           seg=6, mat=tube, fillet=0.14, fillet_n=2)
    b.cyl((px, -0.62, ROOF_Z), (px, 0.62, ROOF_Z), 0.04, seg=6, mat=tube)
    rc, rl = (px - 0.50) / 2, px + 0.61
    with b.at(T(rc, 0, ROOF_Z + 0.06), RY(-3.0)):             # round 16 fix 5: tilted 3 deg, framed
        b.box((0, 0, 0), (rl, 1.44, 0.05), GRAPHITE, mats={"+z": SOLAR})
        for x in (-rl * 0.3, 0.0, rl * 0.3):
            b.box((x, 0, 0.027), (0.02, 1.36, 0.006), "Palette:#8a929c")
        b.box((0, 0, 0.027), (rl - 0.08, 0.02, 0.006), "Palette:#8a929c")
        for sy in (-1, 1):
            b.box((0, sy * 0.71, 0.035), (rl + 0.04, 0.05, 0.03), GRAPHITE)
            b.box((sy * (rl / 2 + 0.01), 0, 0.035), (0.05, 1.40, 0.03), GRAPHITE)
    b.box((px + 0.10, 0, ROOF_Z + 0.02), (0.06, 1.20, 0.06), GRAPHITE)
    for y in (-0.46, -0.16, 0.16, 0.46):
        V.lens(b, lights, (px + 0.15, y, ROOF_Z + 0.02), (1, 0, -0.25), 0.045, housing=(0.05, 0.12, 0.09))
    b.vcyl(-0.40, -0.52, ROOF_Z + 0.05, ROOF_Z + 0.11, 0.07, seg=8, mat=GRAPHITE)
    b.vcyl(-0.40, -0.52, ROOF_Z + 0.11, ROOF_Z + 0.20, 0.055, 0.045, seg=8, mat="BeaconAmber")
    b.vcyl(-0.40, 0.54, ROOF_Z + 0.05, ROOF_Z + 0.14, 0.04, seg=6, mat=GRAPHITE)
    b.vcyl(-0.40, 0.54, ROOF_Z + 0.14, ROOF_Z + 1.00, 0.012, 0.008, seg=4, mat="Palette:#2c3036")
    # ---- cargo bed, bulkhead, battery, tailgate posts, tail lights, registration ----------------
    b.box((-1.225, 0, FLOOR + 0.015), (1.40, 1.24, 0.03), PLATE)
    for y in (-0.42, -0.14, 0.14, 0.42):
        b.box((-1.24, y, FLOOR + 0.04), (1.30, 0.05, 0.03), GRAPHITE)
    for sy in (-1, 1):
        b.box((-1.225, sy * 0.66, FLOOR + 0.18), (1.46, 0.06, 0.36), "Palette:Hull")
        b.box((-1.225, sy * 0.66, FLOOR + 0.375), (1.50, 0.10, 0.04), GRAPHITE)
        b.box((-1.225, sy * 0.692, FLOOR + 0.31), (1.40, 0.006, 0.05), "Accent")
        b.box((-1.97, sy * 0.63, FLOOR + 0.16), (0.08, 0.12, 0.40), GRAPHITE)                     # tail posts
        b.box((-2.015, sy * 0.63, FLOOR + 0.26), (0.012, 0.09, 0.14), "LightRed")
    b.box((-0.50, 0, FLOOR + 0.33), (0.08, 1.38, 0.66), "Palette:Hull", mats={"-x": "Palette:HullDark"})
    b.box((-0.73, 0, FLOOR + 0.20), (0.36, 1.10, 0.34), "Palette:HullDark")                       # battery pack
    for y in (-0.36, -0.12, 0.12, 0.36):
        b.box((-0.915, y, FLOOR + 0.22), (0.012, 0.14, 0.20), GRAPHITE)                            # vents
    b.box((-0.915, 0, FLOOR + 0.06), (0.014, 1.06, 0.05), "Palette:Hazard")
    V.lens(b, lights, (-0.55, 0, FLOOR + 0.69), (-1, 0, -1.4), 0.045, housing=(0.05, 0.14, 0.09))  # bed lamp
    b.box((-2.02, 0, 0.60), (0.16, 0.14, 0.08), GRAPHITE)                                         # hitch
    for sy in (-1, 1):
        w = 5 * 1.55 * 0.09
        if sy > 0:
            o, r = (-0.94 + w / 2, 0.692, FLOOR + 0.06), (-1, 0, 0)
        else:
            o, r = (-0.94 - w / 2, -0.692, FLOOR + 0.06), (1, 0, 0)
        SC.stencil(b, REG, o, r, (0, 0, 1), 0.18, INK, (0, sy, 0), depth=0.012)
    # ---- mid-wheel B-posts, cab sills, side steps, amber corner markers (round 16 fix 4) ---------
    for sy in (-1, 1):
        b.box((0.0, sy * 0.66, 1.26), (0.08, 0.06, 0.36), GRAPHITE)
        b.box((1.99 + FX, sy * 0.652, FLOOR + 0.05), (0.10, 0.03, 0.05), "BeaconAmber")
        b.box((-1.97, sy * 0.694, FLOOR + 0.33), (0.08, 0.012, 0.05), "BeaconAmber")
    for sy in (-1, 1):
        # running board = the ART-NPC "ground" of the door frame: top 0.32 m under the cab floor, x 0.60-1.12
        b.box((0.86, sy * 0.88, BOARD_Z - 0.02 - DROP), (0.52, 0.44, 0.04), GRAPHITE, mats={"+z": "Palette:#6b7078"})
        b.box((0.86, sy * 1.098, BOARD_Z - 0.02 - DROP), (0.52, 0.006, 0.04), "Palette:Hazard")


def tailgate():
    hinge = (-1.95, 0.0, FW + 0.03)
    d = Node("Door_Tailgate", SC.place_frame(hinge, 180.0), None, {"stow_deg": 90.0})
    # open (rest): the leaf lies flat, going out along local +Y; closed: rotated +90 about local X -> upright
    d.box((0, 0.17, -0.025), (1.18, 0.34, 0.05), "Palette:Hull", mats={"-z": "Palette:Hull", "+z": PLATE})
    for x in (-0.36, 0.0, 0.36):
        d.box((x, 0.17, -0.052), (0.18, 0.26, 0.006), "Palette:Hazard")
    d.box((0, 0.335, -0.025), (1.20, 0.03, 0.06), GRAPHITE)
    return d


def cargo():
    c = Node("Cargo", None, None, {"role": "load"})
    z = FW + 0.03
    for (cx, cy, sx, sy, sz, col) in ((-1.55, 0.26, 0.56, 0.52, 0.44, "Palette:Cargo"),
                                      (-1.02, 0.30, 0.44, 0.44, 0.34, "Accent")):
        c.box((cx, cy, z + sz / 2), (sx, sy, sz), col)
        c.box((cx, cy, z + sz * 0.8), (sx + 0.02, sy + 0.02, 0.05), GRAPHITE)
        c.box((cx + sx / 2 + 0.004, cy, z + sz * 0.45), (0.006, sy * 0.5, 0.10), "Palette:Hazard")
    c.cyl((-1.86, -0.34, z + 0.16), (-0.98, -0.34, z + 0.16), 0.16, seg=8, mat="Palette:Hull")
    c.cyl((-1.60, -0.34, z + 0.16), (-1.50, -0.34, z + 0.16), 0.165, seg=8, mat="Palette:#5ee07a", cap0=False, cap1=False)
    c.beam((-1.55, 0.53, z + 0.46), (-1.55, -0.52, z + 0.46), 0.05, 0.012, "Palette:Hazard")          # strap
    return c


def build():
    b = Node("Body")
    lights = Node("Lights", None, None, {"role": "lamps"})
    body_parts(b, lights)
    out = [b]
    for wid, x, sy, st in WHEELS:
        out += KIT.assembly(wid, x, sy, st, Y_KP, Z_HUB)
    out += [tailgate(), cargo(), lights]
    A = []
    for i, sy in ((1, 1), (2, -1)):
        A.append((Anchor("Seat_%d" % i, (ANCHOR_X, sy * SEAT_Y, FW), forward=(1, 0, 0)),
                  {"role": "driver" if i == 1 else "passenger", "seat_top": round(FW + 0.46, 3)}, None))
        # door point (ART-NPC door frame): 0.52 m outboard of the seat anchor, 0.32 m below it, facing forward
        A.append((Anchor("Anchor_Board_%d" % i, (ANCHOR_X, sy * (SEAT_Y + 0.52), BOARD_Z), forward=(1, 0, 0)),
                  {"seat": i, "clip": "board" if sy > 0 else "board_r"}, None))
        A.append((Anchor("Anchor_Ground_%d" % i, (ANCHOR_X, sy * 1.45, 0.0), forward=(1, 0, 0)),
                  {"seat": i, "clip": "step_up" if sy > 0 else "step_up_r"}, None))
        A.append((Anchor("Anchor_Grab_%d" % i, (GRAB[0], sy * GRAB[1], GRAB[2] + DROP), forward=(1, 0, 0)), {"seat": i}, None))
    for k, sy_ in ((1, 1), (2, -1)):
        A.append((Anchor("Anchor_Grip_%d" % k, (GRIP[0], SEAT_Y + sy_ * GRIP_Y, GRIP[1] + DROP), forward=(1, 0, 0)),
                  {"seat": 1}, None))
    A.append((Anchor("Anchor_Cargo", (-2.60, 0.0, 0.0), forward=(1, 0, 0)), {}, None))
    for side, sy in (("L", 1), ("R", -1)):
        A.append((Anchor("Dust_" + side, (-1.40, sy * Y_HUB, 0.03), forward=(-1, 0, 0.35)), {"role": "dust"}, None))
    for y, nm in ((0.36, "HeadL"), (-0.36, "HeadR")):
        A.append(V.light_anchor("Light_" + nm, (2.06 + FX, y, 0.975 + DROP), (1, 0, -0.10), "head", cone=45.0, rng=25.0))
    for y, nm in ((0.31, "WorkL"), (-0.31, "WorkR")):
        A.append(V.light_anchor("Light_" + nm, (PILLAR[0] + 0.18, y, ROOF_Z + 0.02 + DROP), (1, 0, -0.35), "work", cone=70.0, rng=14.0))
    A.append(V.light_anchor("Light_Bed", (-0.57, 0, FW + 0.68), (-1, 0, -1.4), "bed", cone=80.0, rng=6.0))
    for y, nm in ((0.63, "TailL"), (-0.63, "TailR")):
        A.append(V.light_anchor("Light_" + nm, (-2.03, y, FW + 0.26), (-1, 0, 0), "tail", colour="#ff3b30",
                                cone=90.0, rng=3.0))
    A.append(V.light_anchor("Light_Beacon", (-0.40, -0.52, ROOF_Z + 0.16 + DROP), (0, 0, 1), "beacon", colour="#ffb020",
                            cone=360.0, rng=6.0))
    return out + A


def main():
    req = ("Body", "Wheel_*", "Susp_*", "Steer_*", "Seat_1", "Seat_2", "Cargo", "Light_*", "Lights", "Door_Tailgate")
    V.build_vehicle(VID, build, ao_dist=0.7, required=req)


if __name__ == "__main__":
    main()
