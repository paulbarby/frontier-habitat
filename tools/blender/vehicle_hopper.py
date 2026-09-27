"""
Frontier Habitat 4.0 - hopper (V4_DESIGN section 5; critic round 16 steering). ART-B. Blender 5.2, --background only.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_hopper.py

Writes assets/models/vehicle_hopper.glb. Contract: vehicle_common.py docstring, plus the ship leg / thruster rules:
  Leg_<FL|FR|RL|RR>  rest = deployed; rotate about local X by stow_deg * s (s = 1 folded for flight)
  Thruster_Hover_<n> empties at the nozzle exits, local +X = the flame direction (down); extras role "hover"
  Door_Hatch         the airlock-style leaf on the rear vestibule (rest open, stow_deg closes it)
Design: lander-derived capsule (white, one accent band, utilities blue #4A90D9), cockpit bubble at the front top,
4 folding legs, 4 hover thrusters under the belly (the ships' hover-thruster part), two spherical tanks and two
cylinder tanks in view, a rear airlock vestibule with ladder, code HP-03, hazard stripes. 3 seats inside.
"""
import os
import sys
import math
from math import radians, degrees, atan, cos, sin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vehicle_common as V                                 # noqa: E402
from vehicle_common import Node, Anchor, T, RX, RY, RZ, S, GRAPHITE, INK   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402
import ship_common as SC                                   # noqa: E402

VID = "hopper"
HULL_C = "Palette:#e6e3dc"
FLOOR = 1.00
X_FACE = -1.62                    # vestibule outer face (door faces -X)
DOOR_W, DOOR_Z0, DOOR_Z1 = 0.40, 1.02, 2.84
LEG_R, LEG_Z, LEG_H = 1.25, 1.05, 0.85
PANELS, PHASE = 10, 18.0          # critic round 19 fix 3: a 10-panel faceted body; facets face 0, 36, 72 ... deg
FACET = cos(radians(180.0 / PANELS))      # facet-centre radius / vertex radius
PROFILE = [(0.0, 0.86), (1.15, 0.88), (1.36, 0.96), (1.40, 1.22), (1.40, 1.40), (1.30, 2.00), (1.02, 2.62),
           (0.58, 3.00), (0.0, 3.08)]


def body_mat(k, i):
    return {0: GRAPHITE, 1: GRAPHITE, 3: "Accent", 7: "Palette:#8a929c"}.get(k, HULL_C)


def radial_r(z):
    """body radius at height z (for placing parts on the skin)"""
    for (r0, z0), (r1, z1) in zip(PROFILE[1:], PROFILE[2:]):
        if z0 <= z <= z1:
            return (r0 + (r1 - r0) * (z - z0) / (z1 - z0)) * FACET
    return 1.3 * FACET


def reg_plate(b, ang, z=1.62, text="HP-03", hgt=0.20):
    a = radians(ang)
    n = Vector((cos(a), sin(a), 0))
    r = radial_r(z) + 0.02
    right = (-n).cross(Vector((0, 0, 1)))
    c = n * r + Vector((0, 0, z))
    length = (len(text) * 1.55 - 0.55) * hgt / 2
    b.box(tuple(c), (0.01, length + 0.24, hgt + 0.14), HULL_C)
    # the plate is a box in world axes; turn it to face n
    b.verts[-8:] = [c + (Matrix.Rotation(a, 3, "Z") @ (v - c)) for v in b.verts[-8:]]
    o = c + n * 0.006 - right * (length / 2) - Vector((0, 0, hgt / 2))
    SC.stencil(b, text, o, right, (0, 0, 1), hgt, INK, n, depth=0.012)


def body_parts(b, lights):
    b.lathe(PROFILE, body_mat, seg=PANELS, phase=PHASE, smooth=False)
    for k in range(PANELS):                                                   # panel seams along the vertex lines
        a = radians(PHASE + 360.0 * k / PANELS)
        pts = [Vector(((r + 0.012) * cos(a), (r + 0.012) * sin(a), z)) for r, z in PROFILE[2:7]]
        b.beam_path(pts, 0.035, 0.025, GRAPHITE, up=(cos(a), sin(a), 0))
    b.lathe([(1.34, 0.90), (1.50, 0.93), (1.50, 1.14), (1.37, 1.18)], GRAPHITE, seg=PANELS, phase=PHASE,
            smooth=False)                                                     # hard belly ring
    for ang in (144.0, 216.0, 36.0, 324.0):                                   # access plates on the facets
        z = 2.25 if ang in (36.0, 324.0) else 1.68
        r = radial_r(z)
        with b.at(RZ(ang), T(r + 0.01, 0, z), RY(-12.0)):
            b.box((0, 0, 0), (0.02, 0.40, 0.30), "Palette:#c3c9d1")
            for dy in (-0.16, 0.16):
                for dz in (-0.11, 0.11):
                    b.box((0.012, dy, dz), (0.01, 0.03, 0.03), GRAPHITE)
    SC.bubble_canopy(b, lights, (0.42, 0.0, 2.62), 0.72, 0.64, 0.52, ribs=4)
    ring = [Vector((0.42 + 0.74 * cos(radians(a)), 0.66 * sin(radians(a)), 2.64)) for a in range(0, 361, 30)]
    b.beam_path(ring, 0.07, 0.06, GRAPHITE)                                  # canopy frame
    spine = [Vector((0.42 + 0.74 * cos(radians(a)), 0.0, 2.64 + 0.54 * sin(radians(a)))) for a in range(0, 181, 30)]
    b.beam_path(spine, 0.05, 0.05, GRAPHITE, up=(0, 1, 0))
    with lights.at(T(0.42, 0.0, 2.62), S(0.73, 0.65, 0.53)):          # lit shell just outside the dark glass (night)
        lights.lathe([(0.96, 0.3), (0.82, 0.62), (0.55, 0.88)], "Window", seg=16)
    # rear airlock vestibule (colony door kit)
    # vestibule faired into the hull (fix 3 "collar"): one convex shell from the door face to the body skin
    pts = [Vector((X_FACE, sy * 0.55, z)) for sy in (-1, 1) for z in (0.96, 2.98)]
    for z in (0.96, 1.45, 2.05, 2.60, 2.95):
        r = radial_r(z) - 0.03
        for sy in (-1, 1):
            a = radians(180.0 - sy * 24.0)
            pts.append(Vector((r * cos(a), r * sin(a), z)))
    b.hull(pts, HULL_C, face_mat=lambda c, n: GRAPHITE if n.z > 0.6 else None)
    b.beam_path([Vector((X_FACE + 0.14, 0.575, 0.96)), Vector((X_FACE + 0.14, 0.575, 3.00)),
                 Vector((X_FACE + 0.14, -0.575, 3.00)), Vector((X_FACE + 0.14, -0.575, 0.96))], 0.08, 0.05, GRAPHITE,
                up=(1, 0, 0))                                                 # collar frame behind the door kit
    seam = []
    for z in (0.96, 1.45, 2.05, 2.60, 2.95):
        r = radial_r(z) + 0.005
        seam.append(Vector((r * cos(radians(156.0)), r * sin(radians(156.0)), z)))
    for sy in (-1, 1):                                                        # junction seams where it meets the hull
        b.beam_path([Vector((q.x, sy * abs(q.y), q.z)) for q in seam], 0.05, 0.04, GRAPHITE, up=(-1, 0, 0))
    V.door_frame(b, X_FACE, DOOR_W, DOOR_Z0, DOOR_Z1, HULL_C, stripes=5)
    b.box((X_FACE - 0.17, 0, FLOOR - 0.04), (0.34, 0.80, 0.04), GRAPHITE, mats={"+z": "Palette:#6b7078"})   # porch
    for sy in (-1, 1):
        b.box((X_FACE - 0.005, sy * 0.53, 2.80), (0.012, 0.05, 0.12), "LightRed")        # red rear
    # bell nozzles like the ships' (fix 3), under the belly at the four cardinal points
    exits = []
    for name, a in (("F", 0.0), ("L", 90.0), ("B", 180.0), ("R", 270.0)):
        x, y = 0.80 * cos(radians(a)), 0.80 * sin(radians(a))
        exits.append((name, SC.engine_bell(b, (x, y, 0.96), 180.0, r=0.24, L=0.60, ring_mat="Accent")))
    # tanks in view: two spheres at +-Y, two upright cylinders at +-30 deg (front)
    for sy in (-1, 1):
        c = Vector((0.0, sy * 1.62, 1.50))
        b.sphere(tuple(c), 0.40, "Palette:#d9dde2", seg=12, rings=6)
        b.cyl(c + Vector((0, 0, -0.03)), c + Vector((0, 0, 0.03)), 0.41, seg=12, mat="Palette:Hazard", cap0=False, cap1=False)
        for dx in (-0.22, 0.22):
            b.beam((dx, sy * 1.30, 1.18), (dx, sy * 1.62, 1.12), 0.05, 0.05, GRAPHITE)
            b.beam((dx, sy * 1.30, 1.84), (dx, sy * 1.62, 1.88), 0.05, 0.05, GRAPHITE)
        a = radians(62.0 * sy)
        cx, cy = 1.52 * cos(a), 1.52 * sin(a)
        b.vcyl(cx, cy, 1.18, 1.92, 0.17, seg=10, mat="Palette:#c3c9d1")
        b.vcyl(cx, cy, 1.92, 1.99, 0.12, seg=10, mat=GRAPHITE)
        b.beam((cx * 0.86, cy * 0.86, 1.55), (cx, cy, 1.55), 0.04, 0.04, GRAPHITE)
        b.box((0.0, sy * 1.395, 1.31), (0.20, 0.03, 0.06), "BeaconAmber")                # amber side markers
    for ang in (36.0, 324.0):
        reg_plate(b, ang, z=1.60)
    # RCS quads, top beacon, dish, whip, front lamps, landing lamps
    for ang in (54.0, 126.0, 234.0, 306.0):
        a = radians(ang)
        z = 2.40
        r = radial_r(z)
        c = Vector((r * cos(a), r * sin(a), z))
        b.box(tuple(c), (0.16, 0.16, 0.16), GRAPHITE)
    b.vcyl(0, 0, 3.06, 3.12, 0.08, seg=8, mat=GRAPHITE)
    b.vcyl(0, 0, 3.12, 3.22, 0.06, 0.05, seg=8, mat="BeaconAmber")
    b.vcyl(-0.45, 0.0, 2.85, 3.12, 0.03, seg=6, mat=GRAPHITE)
    with b.at(T(-0.45, 0, 3.14), RY(-30.0)):
        b.lathe([(0.0, 0.0), (0.18, 0.03), (0.30, 0.09), (0.31, 0.10), (0.15, 0.05), (0.0, 0.03)],
                lambda k, i: "Palette:#eef0f2" if k < 3 else GRAPHITE, seg=10)
    b.vcyl(-0.30, -0.45, 2.90, 3.70, 0.012, 0.008, seg=4, mat="Palette:#2c3036")
    for y in (-0.26, 0.26):
        p = Vector((radial_r(1.72) + 0.02, y, 1.72))
        V.lens(b, lights, p, (1, 0, -0.1), 0.06, housing=(0.05, 0.15, 0.12))
    for ang in (45.0, 135.0, 225.0, 315.0):
        a = radians(ang)
        V.lens(b, lights, (1.0 * cos(a), 1.0 * sin(a), 0.865), (0, 0, -1), 0.06, housing=None)
    return exits


def ladder():
    """the boarding ladder = node Ramp (ship contract): rest = down, stow_deg folds it up flat against the door"""
    hinge = (X_FACE - 0.30, 0.0, FLOOR - 0.04)
    run, drop = 0.34, FLOOR - 0.04
    slope = degrees(math.atan2(drop, run))
    L = math.hypot(run, drop)
    r = Node("Ramp", SC.place_frame(hinge, 180.0), None, {"stow_deg": round(slope + 90.0, 2), "kind": "ladder"})
    d = Vector((0, math.cos(radians(slope)), -math.sin(radians(slope))))
    for sx in (-1, 1):
        r.beam((sx * 0.28, 0, 0), d * L + Vector((sx * 0.28, 0, 0)), 0.05, 0.05, "Palette:Hazard")
    for k in range(4):
        f = (k + 1) / 5.0
        r.beam(d * (L * f) + Vector((-0.28, 0, 0)), d * (L * f) + Vector((0.28, 0, 0)), 0.05, 0.03, GRAPHITE)
    return r


def legs():
    out = []
    ld = LEG_Z - 0.02
    for name, ang in (("FL", 45.0), ("RL", 135.0), ("RR", 225.0), ("FR", 315.0)):
        a = radians(ang)
        stow = -(90.0 + degrees(atan(LEG_H / ld)))
        n = Node("Leg_" + name, SC.place_frame(Vector((LEG_R * cos(a), LEG_R * sin(a), LEG_Z)), ang), None,
                 {"stow_deg": round(stow, 2)})
        SC.leg_geometry(n, LEG_H, ld, foot_r=0.42, strut=0.20, accent=False)      # graphite running gear
        out.append(n)
    return out


def build():
    b = Node("Body")
    lights = Node("Lights", None, None, {"role": "lamps"})
    exits = body_parts(b, lights)
    out = [b] + legs() + [ladder()]
    out.append(V.door_leaf("Door_Hatch", (X_FACE - 0.14, DOOR_W, DOOR_Z0), 2 * DOOR_W - 0.005, DOOR_Z1 - DOOR_Z0 - 0.01,
                           1, HULL_C))
    out.append(lights)
    A = []
    for name, e in exits:
        A.append((Anchor("Thruster_Hover_" + name, e, forward=(0, 0, -1), up=(1, 0, 0)), {"role": "hover"}, None))
    seats = [(0.70, 0.0, "pilot"), (-0.35, 0.40, "passenger"), (-0.35, -0.40, "passenger")]
    for i, (x, y, role) in enumerate(seats):
        A.append((Anchor("Seat_%d" % (i + 1), (x, y, FLOOR), forward=(1, 0, 0)),
                  {"role": role, "seat_top": round(FLOOR + 0.46, 3), "pressurised": True}, None))
    A.append((Anchor("Anchor_Board", (X_FACE - 0.80, 0, 0.0), forward=(1, 0, 0)), {"role": "ladder foot"}, None))
    A.append((Anchor("Anchor_Hatch", (X_FACE + 0.35, 0, FLOOR), forward=(1, 0, 0)), {"role": "fade point inside"}, None))
    for y, nm in ((0.26, "HeadL"), (-0.26, "HeadR")):
        A.append(V.light_anchor("Light_" + nm, (radial_r(1.72) + 0.03, y, 1.72), (1, 0, -0.1), "head", cone=45.0, rng=25.0))
    for k, ang in enumerate((45.0, 135.0, 225.0, 315.0)):
        a = radians(ang)
        A.append(V.light_anchor("Light_Land_%d" % (k + 1), (1.0 * cos(a), 1.0 * sin(a), 0.85), (0.15 * cos(a), 0.15 * sin(a), -1),
                                "landing", cone=70.0, rng=15.0))
    A.append(V.light_anchor("Light_Hatch", (X_FACE - 0.16, 0, DOOR_Z1 + 0.22), (-1, 0, -1.0), "hatch", cone=80.0, rng=6.0))
    A.append(V.light_anchor("Light_Beacon", (0, 0, 3.20), (0, 0, 1), "beacon", colour="#ffb020", cone=360.0, rng=8.0))
    return out + A


def main():
    req = ("Body", "Leg_*", "Thruster_*", "Door_Hatch", "Ramp", "Seat_1", "Lights", "Light_*", "Anchor_Board")
    V.build_vehicle(VID, build, ao_dist=0.8, required=req)


if __name__ == "__main__":
    main()
