"""
Frontier Habitat 2.0 - colonists (AAA_DESIGN.md section 11).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_colonists.py

Output: assets/models/colonist_suit.glb (outdoor EVA suit; also written as colonist.glb, the v1 name) and
assets/models/colonist_indoor.glb (jumpsuit, head and hair).
Objects: Body (origin on the ground), ArmL / ArmR (origin at the shoulder joint), LegL / LegR (origin at the
hip joint). Left = +Y (the figure faces +X). The game swings the limbs about Godot local Z (= Blender -Y).
SuitAccent is recoloured per role by the game. Skin and Hair (indoor only) may be tinted per colonist.
"""
import os
import sys
from math import sin, cos, pi, radians

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S              # noqa: E402
from mathutils import Vector                               # noqa: E402

HIP_Z, HIP_Y = 0.90, 0.125
SH_Z, SH_Y = 1.36, 0.305


def helmet(body):
    """large round helmet with a wide dark visor, a rim and two lamps"""
    c = Vector((0.015, 0.0, 1.615))
    R = 0.205
    prof = [(0.105, -0.16), (0.16, -0.135), (0.195, -0.075), (0.205, 0.0), (0.195, 0.07), (0.165, 0.125),
            (0.115, 0.17), (0.055, 0.197), (0.0, 0.205)]
    with body.at(T(*c)):
        body.lathe(prof, "SuitMain", seg=12, smooth=True)
    # visor: a spherical patch in front, with a slightly larger rim patch under it
    for (rr, a0, a1, l0, l1, mat) in ((R + 0.006, -70.0, 70.0, -40.0, 36.0, "Pack"),
                                       (R + 0.013, -62.0, 62.0, -33.0, 29.0, "Visor")):
        na, nl = 5, 3
        ids = []
        for i in range(na + 1):
            row = []
            a = radians(a0 + (a1 - a0) * i / na)
            for j in range(nl + 1):
                lat = radians(l0 + (l1 - l0) * j / nl)
                row.append(body.v(c + Vector((rr * cos(lat) * cos(a), rr * cos(lat) * sin(a), rr * sin(lat)))))
            ids.append(row)
        for i in range(na):
            for j in range(nl):
                body.f([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, True)
    # helmet lamps on both sides (role colour) and a small brow ridge
    for sy in (-1, 1):
        body.box((c.x + 0.05, sy * 0.19, c.z + 0.07), (0.10, 0.05, 0.07), "SuitAccent", mats={"-y" if sy > 0 else "+y": None})
    body.vcyl(0.0, 0.0, 1.40, 1.46, 0.135, seg=10, mat="Pack", cap0=False)              # neck ring


def suit_torso(body):
    with body.at(S(0.78, 1.0, 1.0)):
        body.lathe([(0.0, 0.90), (0.20, 0.90), (0.235, 0.98), (0.255, 1.12), (0.262, 1.26), (0.245, 1.36),
                    (0.19, 1.425), (0.10, 1.45), (0.0, 1.455)],
                   lambda k, i: "SuitAccent" if k == 4 else "SuitMain", seg=10, smooth=True)
    body.box((0.175, 0.0, 1.13), (0.07, 0.20, 0.13), "Pack", mats={"-x": None})     # chest control unit
    body.box((0.212, 0.05, 1.15), (0.01, 0.06, 0.035), "SuitAccent", mats={"-x": None})
    body.box((0.212, -0.05, 1.15), (0.01, 0.05, 0.035), "Light", mats={"-x": None})
    body.box((0.0, 0.0, 0.955), (0.33, 0.47, 0.07), "Frame", mats={"+z": None, "-z": None})   # belt
    body.box((0.0, 0.0, 0.875), (0.27, 0.40, 0.16), "SuitMain", bevel=0.05)         # pelvis
    for sy in (-1, 1):                                                               # shoulder pads
        with body.at(T(0.0, sy * 0.27, 1.405)):
            body.lathe([(0.11, -0.02), (0.115, 0.03), (0.07, 0.085), (0.0, 0.095)], "SuitAccent", seg=8,
                       smooth=True)


def life_pack(body):
    body.box((-0.285, 0.0, 1.17), (0.21, 0.44, 0.56), "Pack", bevel=0.05)
    body.box((-0.395, 0.0, 1.30), (0.012, 0.30, 0.07), "SuitAccent", mats={"+x": None})
    body.box((-0.395, 0.0, 1.05), (0.012, 0.18, 0.12), "Frame", mats={"+x": None})
    for sy in (-1, 1):                                                               # side bottles
        body.vcyl(-0.30, sy * 0.25, 0.94, 1.36, 0.055, seg=6, mat="SuitMain", cap0=False)
        body.vcyl(-0.30, sy * 0.25, 1.36, 1.40, 0.035, seg=5, mat="Frame", cap0=False)
    body.vcyl(-0.33, 0.16, 1.44, 1.78, 0.011, seg=4, mat="Frame", smooth=False)      # antenna
    body.sphere((-0.33, 0.16, 1.785), 0.022, "SuitAccent", seg=5, rings=2)
    body.tube([(-0.18, -0.16, 1.40), (-0.10, -0.20, 1.50), (0.0, -0.14, 1.47)], 0.022, seg=4, mat="Frame")


def arm(name, sy, glove="Pack", sleeve="SuitMain", cuff="SuitAccent", skin=False):
    a = Part(name, origin=(0.0, sy * SH_Y, SH_Z))
    sh = Vector((0.0, sy * SH_Y, SH_Z))
    el = Vector((0.025, sy * (SH_Y + 0.035), 1.09))
    wr = Vector((0.06, sy * (SH_Y + 0.04), 0.85))
    a.sphere(tuple(sh), 0.098, sleeve, seg=8, rings=4)
    a.cyl(sh, el, 0.088, 0.078, seg=8, mat=sleeve, cap0=False, cap1=False)
    a.sphere(tuple(el), 0.080, sleeve, seg=7, rings=3)
    a.cyl(el, wr, 0.078, 0.066, seg=8, mat=sleeve, cap0=False, cap1=True)
    a.cyl(wr + Vector((-0.004, 0, 0.035)), wr - Vector((-0.004, 0, 0.012)), 0.074, seg=8, mat=cuff, cap0=False)
    if skin:
        a.sphere(tuple(wr - Vector((-0.012, 0, 0.055))), 0.058, "Skin", seg=8, rings=4, scale=(0.9, 0.8, 1.1))
    else:
        a.sphere(tuple(wr - Vector((-0.015, 0, 0.06))), 0.068, glove, seg=7, rings=4, scale=(1.0, 0.85, 1.1))
    return a


def leg(name, sy, suit=True):
    g = Part(name, origin=(0.0, sy * HIP_Y, HIP_Z))
    hip = Vector((0.0, sy * HIP_Y, HIP_Z))
    kn = Vector((0.025, sy * (HIP_Y + 0.01), 0.49))
    an = Vector((-0.005, sy * (HIP_Y + 0.012), 0.15))
    main = "SuitMain" if suit else "Pack"
    r0, r1, r2 = (0.118, 0.098, 0.084) if suit else (0.100, 0.082, 0.070)
    g.cyl(hip + Vector((0, 0, 0.03)), kn, r0, r1, seg=8, mat=main, cap1=False)
    g.sphere(tuple(kn), r1, main, seg=8, rings=3)
    g.cyl(kn, an, r1, r2, seg=8, mat=main, cap0=False)
    if suit:
        g.box((kn.x + 0.085, kn.y, kn.z + 0.01), (0.05, 0.14, 0.15), "SuitAccent", mats={"-x": None})  # knee pad
        g.box((0.045, an.y, 0.085), (0.31, 0.18, 0.17), "Pack", bevel=0.045)                       # boot
        g.box((0.045, an.y, 0.018), (0.32, 0.19, 0.036), "Rubber")
        g.cyl(an + Vector((0, 0, 0.05)), an + Vector((0, 0, 0.13)), r2 + 0.012, seg=8, mat="SuitAccent", cap0=False)
    else:
        g.box((0.04, an.y, 0.075), (0.27, 0.13, 0.15), "Rubber", bevel=0.04)                       # shoe
    return g


def build_suit(spec):
    body = Part("Body")
    helmet(body)
    suit_torso(body)
    life_pack(body)
    return [body, arm("ArmL", 1), arm("ArmR", -1), leg("LegL", 1), leg("LegR", -1)]


def build_indoor(spec):
    body = Part("Body")
    # torso: jumpsuit top in the role colour, white collar and chest panel
    with body.at(S(0.74, 1.0, 1.0)):
        body.lathe([(0.0, 0.88), (0.18, 0.88), (0.205, 0.97), (0.22, 1.12), (0.225, 1.26), (0.21, 1.35), (0.16, 1.41),
                    (0.08, 1.435), (0.0, 1.44)],
                   lambda k, i: "SuitMain" if k >= 6 else "SuitAccent", seg=12, smooth=True)
    body.box((0.0, 0.0, 0.93), (0.30, 0.41, 0.06), "Frame", bevel=0.02)             # belt
    body.box((0.152, 0.0, 0.93), (0.02, 0.07, 0.05), "Trim")                        # buckle
    body.box((0.0, 0.0, 0.855), (0.24, 0.36, 0.14), "Pack", bevel=0.05)             # trousers top
    body.box((0.16, 0.07, 1.25), (0.02, 0.09, 0.06), "SuitMain", mats={"-x": None})  # name patch
    # neck, head, hair (bob with a fringe)
    body.vcyl(0.005, 0.0, 1.40, 1.50, 0.058, seg=8, mat="Skin")
    hc = Vector((0.015, 0.0, 1.615))
    body.sphere(tuple(hc), 0.128, "Skin", seg=12, rings=7, scale=(1.0, 0.92, 1.08))
    body.sphere(tuple(hc + Vector((0.115, 0.0, -0.01))), 0.022, "Skin", seg=6, rings=3)        # nose

    def hair_mat(k, i):
        # lathe rings k (bottom -> top), segments i (0 = +X front)
        a = 360.0 * (i + 0.5) / 14
        front = a < 55 or a > 305
        if front and k < 4:
            return None
        return "Hair"
    prof = []
    for j in range(7):
        lat = radians(-30 + 120 * j / 6) if j < 6 else radians(90)
        prof.append((0.142 * cos(lat) if j < 6 else 0.0, 0.142 * sin(lat) * 1.05))
    with body.at(T(hc.x - 0.012, 0.0, hc.z + 0.012), S(1.0, 0.95, 1.0)):
        body.lathe(prof, hair_mat, seg=14, smooth=True)
    # eyes: two small dark dots
    for sy in (-1, 1):
        body.sphere(tuple(hc + Vector((0.112, sy * 0.042, 0.022))), 0.014, "Rubber", seg=5, rings=3)
    parts = [body]
    parts += [arm("ArmL", 1, sleeve="SuitAccent", cuff="SuitMain", skin=True),
              arm("ArmR", -1, sleeve="SuitAccent", cuff="SuitMain", skin=True)]
    parts += [leg("LegL", 1, suit=False), leg("LegR", -1, suit=False)]
    return parts


MODELS = [
    dict(id="colonist_suit", kind="unit", footprint=None, accent=None, budget=1500,
         objects=["Body", "ArmL", "ArmR", "LegL", "LegR"], zmin=-0.01, also=["colonist"],
         ao=dict(dist=0.14, samples=48, min_ao=0.5), builder=build_suit),
    dict(id="colonist_indoor", kind="unit", footprint=None, accent=None, budget=1500,
         objects=["Body", "ArmL", "ArmR", "LegL", "LegR"], zmin=-0.01,
         ao=dict(dist=0.14, samples=48, min_ao=0.5), builder=build_indoor),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for spec in MODELS:
        if only and spec["id"] not in only:
            continue
        print("building", spec["id"], "...")
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)


if __name__ == "__main__":
    main()
