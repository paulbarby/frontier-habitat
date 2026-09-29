"""
Frontier Habitat 5.0 - super dome: the shell (dome glass + frame, foundation, promenade, 12 gates). ART-B.
Blender 5.2, --background only:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_shell.py
Writes assets/models/dome_shell.glb. Contract: dome_common.py docstring.
"""
import os
import sys
import math
from math import sin, cos, radians

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy                                                 # noqa: E402
import bmesh                                               # noqa: E402
import dome_common as D                                    # noqa: E402
from dome_common import Group, pol, T, RZ, RX, RY, S, GRAPHITE, WHITE, CONCRETE, PAVING   # noqa: E402
from vehicle_common import Node                            # noqa: E402
from mathutils import Vector                               # noqa: E402

FRAME = "Palette:#5f666f"              # critic round 24 fix 2: graphite / brushed metal, not white
R_PLINTH0, R_PLINTH1, PLINTH_H = 47.6, 49.6, 1.3
GATE_W, GATE_H = 6.0, 4.6
GATE_R0, GATE_R1 = 47.0, 51.0


def geodesic(freq=10):
    """class-I geodesic sphere of frequency `freq` (each icosahedron face split into freq^2 triangles), cut to the
    cap above the ground: (verts, faces, edges, used vertex indices)"""
    t = (1.0 + 5 ** 0.5) / 2.0
    iv = [Vector(v).normalized() for v in ((-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
                                           (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
    iface = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
             (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
             (8, 6, 7), (9, 8, 1)]
    verts, index = [], {}

    def vid(p):
        q = p.normalized() * D.RS + Vector((0, 0, D.CZ))
        key = (round(q.x, 3), round(q.y, 3), round(q.z, 3))
        if key not in index:
            index[key] = len(verts)
            verts.append(q)
        return index[key]
    faces = []
    for (a_, b_, c_) in iface:
        A, B, Cc = iv[a_], iv[b_], iv[c_]
        grid = {}
        for i in range(freq + 1):
            for j in range(freq + 1 - i):
                k = freq - i - j
                grid[(i, j)] = vid(A * (i / freq) + B * (j / freq) + Cc * (k / freq))
        for i in range(freq):
            for j in range(freq - i):
                faces.append([grid[(i, j)], grid[(i + 1, j)], grid[(i, j + 1)]])
                if i + j < freq - 1:
                    faces.append([grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]])
    keep = [f for f in faces if sum(verts[i].z for i in f) / 3 > -0.6 and max(verts[i].z for i in f) > 0.2]
    edges = set()
    for f in keep:
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            edges.add((min(a, b), max(a, b)))
    used = sorted({i for f in keep for i in f})
    return verts, keep, sorted(edges), used


def gate_angle(i):
    return i * 360.0 / D.N_GATES


def in_gate(a_deg, half=4.2):
    for i in range(D.N_GATES):
        d = (a_deg - gate_angle(i) + 180.0) % 360.0 - 180.0
        if abs(d) < half:
            return True
    return False


def build():
    out = [Group("Foundation", None, {"floor": 1, "stage": "foundation"}),
           Group("Promenade", None, {"floor": 1, "stage": "fitout"}),
           Group("Gates", None, {"floor": 1, "stage": "structure"}),
           Group("Dome", None, {"floor": 6, "stage": "dome"})]
    # ---- foundation: ring base slab (under the ring building), promenade slab, plinth wall with gate gaps ----
    f = Node("Foundation_Slab", None, "Foundation", {"floor": 1, "stage": "foundation"})
    f.lathe([(D.R_IN, D.GROUND), (D.R_IN, 0.0)], CONCRETE, seg=96, caps=False)                # faces the atrium
    f.lathe([(D.R_OUT, D.GROUND), (D.R_IN, D.GROUND)], CONCRETE, seg=96, caps=False)            # under the ring
    for k, (r0, r1, col) in enumerate(((D.R_OUT, 36.0, "Palette:#a9a397"), (36.0, 40.5, D.PAVING),
                                       (40.5, 41.5, "Palette:#8e887d"), (41.5, R_PLINTH0, D.PAVING))):
        f.lathe([(r1, D.GROUND), (r0, D.GROUND)], col, seg=96, caps=False)                   # top faces up
    hw = math.degrees((GATE_W / 2 + 0.9) / R_PLINTH1)                    # the plinth, open at the 12 gates
    for i in range(D.N_GATES):
        b0, b1 = gate_angle(i) + hw, gate_angle(i + 1) - hw
        D.sector_prism(f, R_PLINTH0, R_PLINTH1, b0, b1, 0.0, PLINTH_H, CONCRETE, None, CONCRETE, CONCRETE,
                       ends=CONCRETE, n=8)
        D.sector_prism(f, R_PLINTH1 - 0.01, R_PLINTH1 + 0.02, b0, b1, 0.85, 1.05, None, None, None, "Accent", n=8)
    out.append(f)
    # ---- promenade: planters with trees between the gates, lamp posts, benches ----
    pr = Node("Promenade_Props", None, "Promenade", {"floor": 1, "stage": "fitout"})
    lights = Node("Promenade_Lamps", None, "Promenade", {"floor": 1, "stage": "fitout"})
    for i in range(D.N_GATES):
        a = gate_angle(i) + 15.0
        c = D.pol(42.0, a, D.GROUND)
        with pr.at(T(*c), RZ(a)):
            pr.box((0, 0, 0.35), (2.6, 6.0, 0.7), WHITE)
            pr.box((0, 0, 0.71), (2.3, 5.7, 0.02), "Palette:#5a3d2b")
        D.tree(pr, c + Vector((0, 0, 0.7)) + D.pol(1.2, a + 90.0), h=5.0, r=1.7, seed=i)
        D.tree(pr, c + Vector((0, 0, 0.7)) + D.pol(1.8, a - 90.0), h=3.2, r=1.0, mat=D.PLANT2, seed=i + 1)
        for side in (-1, 1):                                            # benches facing the ring
            b = D.pol(39.2, a + side * 4.0, D.GROUND)
            D.colony_bench(pr, b, a + side * 4.0 + 180.0)
    for s in range(D.N_SEC):
        D.lamp_post(pr, lights, D.pol(37.2, s * D.SEC + 7.5, D.GROUND), h=4.4)
        out.append(D.light_anchor("Light_Lamp_P%d" % s, D.pol(37.2, s * D.SEC + 7.5, D.GROUND + 4.3), (0, 0, -1), "lamp"))
    out += [pr, lights]
    # ---- 12 gates: vestibule blocks through the plinth, door on the outer face ----
    g = Node("Gates_Body", None, "Gates", {"floor": 1, "stage": "structure"})
    gl = Node("Gates_Lights", None, "Gates", {"floor": 1, "stage": "structure"})
    for i in range(D.N_GATES):
        a = gate_angle(i)
        with g.at(RZ(a)):
            depth = GATE_R1 - GATE_R0
            xc = (GATE_R0 + GATE_R1) / 2
            for sy in (-1, 1):
                g.box((xc, sy * (GATE_W / 2 + 0.45), GATE_H / 2 + 0.3), (depth, 0.9, GATE_H + 0.6), WHITE)
                g.box((GATE_R1 + 0.01, sy * (GATE_W / 2 + 0.45), 1.6), (0.02, 0.9, 2.4), "Palette:Hazard")
            g.box((xc, 0, GATE_H + 0.75), (depth + 0.3, GATE_W + 2.1, 0.9), WHITE, mats={"+z": GRAPHITE})
            g.box((GATE_R1 + 0.16, 0, GATE_H + 0.75), (0.02, GATE_W + 1.6, 0.35), "Accent")
            g.box((GATE_R1 - 0.1, 0, GATE_H / 2 + 0.3), (0.12, GATE_W, GATE_H), "Palette:#2c3036")   # door leaves
            g.box((GATE_R1 - 0.03, 0, GATE_H / 2 + 0.3), (0.02, 0.06, GATE_H), GRAPHITE)
            for sy in (-1, 1):
                g.box((GATE_R1 - 0.02, sy * GATE_W / 4, GATE_H * 0.62), (0.02, GATE_W * 0.3, 1.1), "Glass")
            g.box((xc, 0, 0.16), (depth, GATE_W, 0.32), GRAPHITE)
            g.box((GATE_R1 + 0.02, 0, GATE_H + 0.42), (0.02, 3.0, 0.1), "StatusGreen")
            gl.box((GATE_R1 + 0.35, 0, GATE_H + 0.25), (0.25, 2.4, 0.06), "Light")
        out.append(D.anchor("Anchor_Gate_%d" % i, D.pol(GATE_R1 + 0.6, a, D.GROUND), forward=D.pol(1.0, a),
                            floor=1, gate=i))
        out.append(D.anchor("Anchor_GateIn_%d" % i, D.pol(GATE_R0 - 1.0, a, D.GROUND), forward=-D.pol(1.0, a),
                            floor=1, gate=i))
    out += [g, gl]
    # ---- the dome: geodesic glass, white frame, node lights, crown ----
    verts, faces, edges, used = geodesic(10)
    glass = Node("Dome_Glass", None, "Dome", {"floor": 6, "stage": "dome_glass"})
    for fc in faces:
        glass.poly([verts[i] for i in fc], "Glass")
    frame = Node("Dome_Frame", None, "Dome", {"floor": 6, "stage": "dome_frame"})
    for (a, b) in edges:
        pa, pb = verts[a], verts[b]
        if pa.z < -0.6 and pb.z < -0.6:
            continue
        frame.cyl(pa, pb, 0.09, seg=3, mat=FRAME, smooth=False, cap0=False, cap1=False)
    dl = Node("Dome_Lights", None, "Dome", {"floor": 6, "stage": "dome_glass"})
    centre = Vector((0, 0, D.CZ))
    for i in used:
        p = verts[i]
        if p.z < 1.5 or D.hsh("node", i) < 0.5:                 # fix 2: lights at about every second node
            continue
        n = (p - centre).normalized()
        u = n.cross(Vector((0, 0, 1)))
        u = u.normalized() if u.length > 1e-4 else Vector((1, 0, 0))
        v = n.cross(u)
        c = p + n * 0.12
        s = 0.13
        dl.poly([c + u * s, c + v * s, c - u * s, c - v * s], "WindowAmber")      # smaller and warmer
    top = Vector((0, 0, D.DOME_H))
    frame.lathe([(3.2, D.DOME_H - 0.35), (3.4, D.DOME_H + 0.05), (2.6, D.DOME_H + 0.35), (2.4, D.DOME_H - 0.1)],
                FRAME, seg=16)
    frame.vcyl(0, 0, D.DOME_H + 0.3, D.DOME_H + 2.2, 0.08, seg=6, mat=GRAPHITE)
    dl.vcyl(0, 0, D.DOME_H + 2.2, D.DOME_H + 2.45, 0.14, seg=8, mat="LightRed")
    # round 26 fix 2: a faint lit rim at the dome foot and round the crown, so the shell reads at night
    dl.lathe([(3.45, D.DOME_H - 0.05), (3.45, D.DOME_H + 0.08), (3.4, D.DOME_H + 0.08)], "LightStrip", seg=24, smooth=False)
    dl.lathe([(R_PLINTH1 + 0.03, PLINTH_H - 0.14), (R_PLINTH1 + 0.03, PLINTH_H - 0.05), (R_PLINTH1, PLINTH_H - 0.05)],
             "LightStrip", seg=96, smooth=False)
    out += [glass, frame, dl]
    out.append(D.anchor("Anchor_Crown", top, floor=6))
    return out


def main():
    D.build_file("dome_shell.glb", build, ao={"dist": 1.5, "samples": 12,
                                              "skip": ["Dome_Glass", "Dome_Frame", "Dome_Lights", "Promenade_Lamps", "Gates_Lights"]})


if __name__ == "__main__":
    main()
