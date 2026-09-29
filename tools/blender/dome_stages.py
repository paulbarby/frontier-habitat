"""
Frontier Habitat 5.0 - super dome construction stages (V5 section 8: foundation ring -> structure per level ->
dome glass -> fit-out per venue, each stage visible). ART-B. Blender --background only:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_stages.py
Writes assets/models/dome_scaffold.glb (same origin as the other dome files):
  Site          site fence with hazard boards, two site cabins, stacks of beams and glass crates, 4 flood masts
                (visible from the foundation stage until the dome is finished)
  Scaffold_<n>  scaffold round the outer face and the atrium edge of level n (show it while level n is built)
  Crane         a tower crane in the atrium (foundation .. level 5); Crane_Jib (child) turns about local Z
                (Godot local Y); extras jib_length, hook_height
Show / hide table: assets/models/dome_manifest.json "build_stages".
"""
import os
import sys
from math import radians, cos, sin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dome_common as D                                    # noqa: E402
import dome_floors as F                                    # noqa: E402
from dome_common import Group, pol, T, RZ, GRAPHITE, WHITE   # noqa: E402
from vehicle_common import Node                            # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402

TUBE = "Palette:#b8c2cc"
PLANK = "Palette:#b08560"
NET = "Palette:#e07a3a"
CRANE_C = Vector((-9.0, -9.0, 0.0))
CRANE_H = 44.0
JIB = 30.0


def scaffold_ring(p, r_in, r_out, z0, z1, a_step=5.0, net_every=3, seed=0):
    """standards at two radii, ledgers every 2 m, a plank deck at each lift, some orange netting"""
    n = int(360.0 / a_step)
    lifts = []
    z = z0
    while z < z1 - 0.1:
        lifts.append(z)
        z += 2.0
    lifts.append(z1)
    for k in range(n):
        a = k * a_step
        for r in (r_in, r_out):
            c = pol(r, a)
            p.cyl((c.x, c.y, z0), (c.x, c.y, z1 + 1.0), 0.04, seg=4, mat=TUBE, cap0=False, cap1=False)
        for zz in lifts:
            p.cyl(pol(r_in, a, zz), pol(r_out, a, zz), 0.03, seg=4, mat=TUBE, cap0=False, cap1=False)
    for zz in lifts:
        for r in (r_in, r_out):
            pts = D.arc(r, 0.0, 360.0, n, zz + 1.0)
            for i in range(n):
                p.cyl(pts[i], pts[i + 1], 0.03, seg=4, mat=TUBE, cap0=False, cap1=False)
        for i in range(n):                                                    # plank deck
            a0, a1 = i * a_step, (i + 1) * a_step
            D.sector_prism(p, r_in, r_out, a0, a1, zz, zz + 0.05, PLANK, None, None, None, n=1)
    for i in range(n):                                                        # netting on the outer face
        if (i + seed) % net_every == 0:
            a0, a1 = i * a_step, (i + 1) * a_step
            pts0 = D.arc(r_out + 0.05, a0, a1, 1, z0 + 1.0)
            pts1 = D.arc(r_out + 0.05, a0, a1, 1, z1 + 0.9)
            D.quad(p, [pts0[0], pts0[1], pts1[1], pts1[0]], pol(1.0, (a0 + a1) / 2), NET)


def site(p, lt):
    # fence with hazard boards at r 53
    n = 72
    for k in range(n):
        a = k * 360.0 / n
        c = pol(53.0, a)
        p.cyl((c.x, c.y, 0), (c.x, c.y, 1.8), 0.05, seg=4, mat=GRAPHITE, cap0=False)
        pts = D.arc(53.0, a, a + 360.0 / n, 1, 0.0)
        for zz, col in ((0.6, "Palette:Hazard"), (1.3, WHITE)):
            D.quad(p, [pts[0] + Vector((0, 0, zz)), pts[1] + Vector((0, 0, zz)), pts[1] + Vector((0, 0, zz + 0.4)),
                       pts[0] + Vector((0, 0, zz + 0.4))], pol(1.0, a + 360.0 / n / 2), col)
    for k, a in enumerate((20.0, 200.0)):                                     # site cabins (containers)
        with p.at(T(*pol(56.5, a)), RZ(a)):
            p.box((0, 0, 1.3), (2.5, 6.0, 2.6), "Palette:#e07a3a", mats={"+z": GRAPHITE})
            p.box((-1.26, 1.5, 1.4), (0.02, 1.0, 0.9), "Palette:#1a2230")
            lt.box((-1.27, -1.5, 2.3), (0.02, 0.5, 0.1), "Light")
    for k, a in enumerate((70.0, 110.0, 250.0, 290.0)):                      # material stacks
        c = pol(57.0, a)
        with p.at(T(*c), RZ(a)):
            if k % 2:
                for j in range(4):
                    p.box((0, 0, 0.15 + j * 0.3), (0.3, 8.0, 0.25), "Palette:#8a929c")
            else:
                for j in range(3):
                    p.box((0, -2.2 + j * 2.2, 0.8), (1.4, 2.0, 1.6), D.WOOD)
                    p.box((-0.71, -2.2 + j * 2.2, 0.8), (0.02, 1.0, 0.3), "Palette:Hazard")
    for k in range(4):                                                        # flood masts
        a = 45.0 + 90.0 * k
        c = pol(55.0, a)
        p.cyl((c.x, c.y, 0), (c.x, c.y, 12.0), 0.15, seg=6, mat=GRAPHITE, cap0=False)
        with p.at(T(c.x, c.y, 12.0), RZ(a + 180.0)):
            p.box((0.2, 0, 0.2), (0.4, 1.6, 0.8), GRAPHITE)
        with lt.at(T(c.x, c.y, 12.0), RZ(a + 180.0)):
            lt.box((0.42, 0, 0.2), (0.02, 1.4, 0.6), "Light")


def crane(p, lt):
    c = CRANE_C
    s = 1.0
    for sx in (-1, 1):                                                        # lattice tower
        for sy in (-1, 1):
            p.cyl(c + Vector((sx * s, sy * s, 0)), c + Vector((sx * s, sy * s, CRANE_H)), 0.07, seg=4, mat="Palette:Hazard",
                  cap0=False, cap1=False)
    z = 0.0
    while z < CRANE_H - 1.0:
        for k in range(4):
            a0 = Vector((cos(radians(45 + 90 * k)), sin(radians(45 + 90 * k)), 0)) * (s * 1.414)
            a1 = Vector((cos(radians(135 + 90 * k)), sin(radians(135 + 90 * k)), 0)) * (s * 1.414)
            p.cyl(c + a0 + Vector((0, 0, z)), c + a1 + Vector((0, 0, z + 2.0)), 0.035, seg=3, mat="Palette:Hazard",
                  cap0=False, cap1=False)
        z += 2.0
    p.box(tuple(c + Vector((0, 0, 0.5))), (4.0, 4.0, 1.0), "Palette:#8a929c")
    jib = Node("Crane_Jib", Matrix.Translation(c + Vector((0, 0, CRANE_H))), "Crane",
               {"axis": "local Z (Godot local Y)", "jib_length": JIB, "hook_height": CRANE_H - 6.0})
    jib.box((0, 0, 0.6), (2.4, 2.4, 1.2), "Palette:Hazard", mats={"+z": GRAPHITE})        # slewing unit + cab
    jib.box((1.4, -1.1, 0.4), (1.2, 1.0, 1.4), "Palette:#e6e3dc")
    lt.box(tuple(c + Vector((2.01, -1.1, CRANE_H + 0.6))), (0.02, 0.8, 0.5), "WindowCream")
    for sy in (-0.6, 0.6):                                                     # jib and counter-jib
        jib.cyl((-9.0, sy, 1.2), (JIB, sy, 1.2), 0.08, seg=4, mat="Palette:Hazard", cap0=True, cap1=True)
    jib.cyl((-9.0, 0, 2.8), (JIB, 0, 2.2), 0.07, seg=4, mat="Palette:Hazard")
    for k in range(20):
        x = -9.0 + k * (JIB + 9.0) / 20
        jib.cyl((x, -0.6, 1.2), (x + 1.0, 0, 2.6), 0.03, seg=3, mat="Palette:Hazard", cap0=False, cap1=False)
        jib.cyl((x, 0.6, 1.2), (x + 1.0, 0, 2.6), 0.03, seg=3, mat="Palette:Hazard", cap0=False, cap1=False)
    jib.box((-8.0, 0, 0.6), (2.0, 2.0, 1.2), "Palette:#9aa0a6")                                              # counterweight
    jib.cyl((0, 0, 1.2), (0, 0, 6.5), 0.1, seg=4, mat="Palette:Hazard")                                    # A-frame
    jib.cyl((22.0, 0, 1.1), (22.0, 0, -6.0), 0.02, seg=3, mat=GRAPHITE, cap0=False, cap1=False)             # hoist rope
    jib.box((22.0, 0, -6.2), (0.5, 0.3, 0.4), "Palette:Hazard")                                            # hook block
    lt.cyl(c + Vector((0, 0, CRANE_H + 6.5)), c + Vector((0, 0, CRANE_H + 6.8)), 0.12, seg=6, mat="LightRed")
    return jib


def build():
    out = [Group("Site", None, {"floor": 1, "stage": "site"}), Group("Crane", None, {"floor": 1, "stage": "site"})]
    sp = Node("Site_Props", None, "Site", {"floor": 1, "stage": "site"})
    sl = Node("Site_Lamps", None, "Site", {"floor": 1, "stage": "site"})
    site(sp, sl)
    out += [sp, sl]
    for n in range(1, 6):
        g = "Scaffold_%d" % n
        out.append(Group(g, None, {"floor": n, "stage": "level_%d" % n}))
        sc = Node("Scaffold_%d_Tubes" % n, None, g, {"floor": n, "stage": "level_%d" % n})
        z0 = F.floor_z(n) - (0.0 if n == 1 else D.SLAB)
        z1 = F.floor_z(n + 1) - D.SLAB if n < 5 else D.ROOF_Z + 1.0
        scaffold_ring(sc, D.R_OUT + 0.6, D.R_OUT + 1.8, z0, z1, a_step=7.5, net_every=3, seed=n)
        scaffold_ring(sc, D.R_IN - 1.6, D.R_IN - 0.4, z0, z1, a_step=10.0, net_every=4, seed=n + 1)
        out.append(sc)
    cp = Node("Crane_Tower", None, "Crane", {"floor": 1, "stage": "site"})
    cl = Node("Crane_Lamps", None, "Crane", {"floor": 1, "stage": "site"})
    jib = crane(cp, cl)
    out += [cp, cl, jib]
    return out


def main():
    D.build_file("dome_scaffold.glb", build, ao={"dist": 1.0, "samples": 6,
                                                 "skip": ["Site_Lamps", "Crane_Lamps", "Crane_Jib"] + ["Scaffold_%d_Tubes" % n for n in range(1, 6)]})


if __name__ == "__main__":
    main()
