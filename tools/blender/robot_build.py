"""
Frontier Habitat 5.0 - ART-NPC: the club robot dancer (V5 section 1, section 8).  Blender --background only.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/robot_build.py

assets/models/robot_dancer.glb = the v3 rig (24 bones, 1.80 m, the same names and bind as the astronauts) and one
skinned mesh Robot_dancer: a slim chrome humanoid machine built from rigid parts (every vertex on one bone), ball
joints in graphite, a dark visor with a light bar for a face, light strips on the forearms and shins, a chest light.
No human anatomy.  Clips (robot_anims.py): robot_idle, robot_dance_a/b/c, robot_pole.  Every clip starts and ends on
the same pose, so RENDER can chain them at the loop ends with no blend.  Writes assets/models/robot_manifest.json.
"""
import bpy
import os
import sys
import json
import time
from math import sin, cos, pi, radians, copysign
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C          # noqa: E402
import npc_common as N          # noqa: E402
import people_mesh as PM        # noqa: E402

PATH = os.path.join(N.MODEL_DIR, "robot_dancer.glb")
MANIFEST = os.path.join(N.MODEL_DIR, "robot_manifest.json")

# name: (base colour, roughness, metallic, texture, emission)
ROBOT_MATERIALS = {
    "RobotChrome": ("#dfe4ea", 0.13, 1.0, None, None),
    "RobotJoint":  ("#2a2d33", 0.38, 0.65, None, None),
    "RobotVisor":  ("#07080b", 0.06, 0.30, None, None),
    "RobotTrim":   ("#8f96a0", 0.28, 0.90, None, None),
    "RobotLight":  ("#57f2ff", 0.30, 0.0, None, "#57f2ff"),
}
PM.PEOPLE_MATERIALS.update(ROBOT_MATERIALS)
LIGHT_STRENGTH = 3.0


def mirror_bone(b):
    return b[:-2] + ".R" if b.endswith(".L") else b


# ------------------------------------------------------------------------------------------------------------------
# geometry helpers (all write into a MeshData; every vertex gets one bone)
# ------------------------------------------------------------------------------------------------------------------
def se(c, n):
    """Superellipse profile value for cos/sin c with exponent n."""
    return copysign(abs(c) ** (2.0 / n), c)


def ring(center, u, v, ap, an, bp, bn=None, n=2.0, seg=20):
    """Superellipse ring: +u half axis ap, -u an, +v bp, -v bn; counter-clockwise about w = u x v."""
    bn = bp if bn is None else bn
    out = []
    for k in range(seg):
        t = 2 * pi * k / seg
        c, s = cos(t), sin(t)
        a = ap if c >= 0 else an
        b = bp if s >= 0 else bn
        out.append(Vector(center) + Vector(u) * (a * se(c, n)) + Vector(v) * (b * se(s, n)))
    return out


def loft(md, rings, bone, mat, cap0=True, cap1=True, smooth=True):
    """Quads between consecutive rings (they progress along +w), fans at the ends."""
    idx = [[md.v(p, bone) for p in r] for r in rings]
    seg = len(rings[0])
    for i in range(len(idx) - 1):
        a, b = idx[i], idx[i + 1]
        for j in range(seg):
            k = (j + 1) % seg
            md.f((a[j], a[k], b[k], b[j]), mat, smooth)
    if cap0:
        c = md.v(sum(rings[0], Vector()) / seg, bone)
        for j in range(seg):
            md.f((c, idx[0][(j + 1) % seg], idx[0][j]), mat, smooth)
    if cap1:
        c = md.v(sum(rings[-1], Vector()) / seg, bone)
        for j in range(seg):
            md.f((c, idx[-1][j], idx[-1][(j + 1) % seg]), mat, smooth)


def axis_frame(w, ref=(1.0, 0.0, 0.0)):
    u, v, w = N.frame_from(w, ref)
    return u, v, w


def tube(md, a, b, radii, bone, mat, seg=18, ref=(1.0, 0.0, 0.0), n=2.0, squash=1.0):
    """Tapered round tube from a to b; radii at evenly spaced stations (the first and last close the ends)."""
    a, b = Vector(a), Vector(b)
    u, v, w = axis_frame(b - a, ref)
    L = (b - a).length
    rings = []
    m = len(radii)
    for i, r in enumerate(radii):
        t = i / (m - 1)
        rings.append(ring(a + w * (L * t), u, v, r, r, r * squash, r * squash, n=n, seg=seg))
    loft(md, rings, bone, mat)


def sphere(md, c, r, bone, mat, seg=14, rows=8, scale=(1.0, 1.0, 1.0)):
    c = Vector(c)
    rings = []
    for i in range(1, rows):
        th = pi * i / rows
        z = -cos(th)
        rr = sin(th)
        rings.append([c + Vector((r * rr * cos(2 * pi * k / seg) * scale[0], r * rr * sin(2 * pi * k / seg) * scale[1],
                                  r * z * scale[2])) for k in range(seg)])
    loft(md, rings, bone, mat)


def lathe_axis(md, c, axis, profile, bone, mat, seg=20, ref=(1.0, 0.0, 0.0)):
    """profile: [(offset along axis, radius)], increasing offsets."""
    u, v, w = axis_frame(axis, ref)
    rings = [ring(Vector(c) + w * t, u, v, r, r, r, r, seg=seg) for t, r in profile]
    loft(md, rings, bone, mat)


def stations(md, sts, bone, mat, n=2.4, seg=24, u=(1, 0, 0), v=(0, 1, 0)):
    """Vertical loft: sts = [(z, cx, a_front, a_back, half_width)] bottom to top."""
    rings = [ring(Vector((cx, 0.0, z)), u, v, af, ab, hw, hw, n=n, seg=seg) for z, cx, af, ab, hw in sts]
    loft(md, rings, bone, mat)


def lerp_st(sts, z):
    for i in range(len(sts) - 1):
        z0, z1 = sts[i][0], sts[i + 1][0]
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return tuple(sts[i][k] + (sts[i + 1][k] - sts[i][k]) * t for k in range(5))
    return sts[0] if z < sts[0][0] else sts[-1]


def surf_pt(sts, z, th, off, n=2.4):
    """A point on a vertical loft surface at height z and angle th (0 = front, +y at 90), pushed out by off."""
    _, cx, af, ab, hw = lerp_st(sts, z)
    c, s = cos(th), sin(th)
    x = cx + (af if c >= 0 else ab) * se(c, n)
    y = hw * se(s, n)
    # outward normal of the superellipse, approximately the radial direction scaled by the axes
    nrm = Vector((x - cx, y, 0.0))
    nrm = nrm.normalized() if nrm.length > 1e-6 else Vector((1, 0, 0))
    return Vector((x, y, z)) + nrm * off


def patch(md, sts, z0, z1, th0, th1, off, bone, mat, rows=4, cols=12, n=2.4):
    """A raised skin patch on a vertical loft (visor, light bar): outer surface + side walls down to the surface."""
    outer, inner = [], []
    for i in range(rows + 1):
        z = z0 + (z1 - z0) * i / rows
        ro, ri = [], []
        for j in range(cols + 1):
            th = th0 + (th1 - th0) * j / cols
            ro.append(md.v(surf_pt(sts, z, th, off, n), bone))
            ri.append(md.v(surf_pt(sts, z, th, -0.002, n), bone))
        outer.append(ro)
        inner.append(ri)
    for i in range(rows):
        for j in range(cols):
            md.f((outer[i][j], outer[i][j + 1], outer[i + 1][j + 1], outer[i + 1][j]), mat, True)
    for j in range(cols):          # bottom and top walls
        md.f((inner[0][j], inner[0][j + 1], outer[0][j + 1], outer[0][j]), mat, True)
        md.f((outer[rows][j], outer[rows][j + 1], inner[rows][j + 1], inner[rows][j]), mat, True)
    for i in range(rows):          # side walls
        md.f((inner[i][0], outer[i][0], outer[i + 1][0], inner[i + 1][0]), mat, True)
        md.f((outer[i][cols], inner[i][cols], inner[i + 1][cols], outer[i + 1][cols]), mat, True)


# ------------------------------------------------------------------------------------------------------------------
# the parts (bind pose, 1.80 m frame; left side built once and mirrored)
# ------------------------------------------------------------------------------------------------------------------
PELVIS = [(0.855, 0.0, 0.040, 0.036, 0.060), (0.872, 0.0, 0.064, 0.056, 0.112), (0.925, 0.0, 0.076, 0.062, 0.132),
          (0.985, 0.0, 0.074, 0.060, 0.128), (1.035, 0.0, 0.064, 0.056, 0.110), (1.062, 0.0, 0.045, 0.040, 0.078)]
CHEST = [(1.180, 0.000, 0.055, 0.058, 0.085), (1.215, 0.004, 0.078, 0.074, 0.118), (1.275, 0.010, 0.098, 0.084, 0.142),
         (1.335, 0.014, 0.108, 0.089, 0.158), (1.390, 0.012, 0.104, 0.086, 0.160), (1.432, 0.008, 0.086, 0.076, 0.138),
         (1.462, 0.006, 0.058, 0.052, 0.080), (1.478, 0.005, 0.028, 0.028, 0.040)]
HEAD = [(1.583, 0.020, 0.028, 0.034, 0.030), (1.600, 0.020, 0.068, 0.064, 0.060), (1.630, 0.020, 0.090, 0.086, 0.075),
        (1.670, 0.020, 0.100, 0.096, 0.085), (1.712, 0.020, 0.100, 0.097, 0.087), (1.752, 0.020, 0.090, 0.090, 0.080),
        (1.782, 0.020, 0.064, 0.068, 0.060), (1.800, 0.020, 0.030, 0.034, 0.030), (1.806, 0.020, 0.008, 0.010, 0.008)]


def build_core(md):
    """Pelvis, waist column, chest shell with its light, neck, head with visor and light bar, ear pods."""
    stations(md, PELVIS, "hips", "RobotChrome", n=4.5, seg=32)            # a block: flat sides and back
    patch(md, PELVIS, 0.950, 0.958, -3.05, 3.05, 0.003, "hips", "RobotJoint", rows=1, cols=40, n=4.5)   # panel line
    patch(md, PELVIS, 0.880, 1.030, 3.02, 3.26, 0.003, "hips", "RobotJoint", rows=4, cols=2, n=4.5)     # back seam
    for sg in (1.0, -1.0):                                                   # joint caps over the hip joints
        c = Vector((0.0, sg * 0.128, 0.935))
        lathe_axis(md, c, (0, sg, 0), [(0.0, 0.052), (0.010, 0.056), (0.020, 0.050), (0.024, 0.030)], "hips",
                   "RobotTrim", seg=20, ref=(1, 0, 0))
        lathe_axis(md, c + Vector((0, sg * 0.024, 0)), (0, sg, 0), [(0.0, 0.020), (0.002, 0.021), (0.004, 0.010)],
                   "hips", "RobotLight", seg=16, ref=(1, 0, 0))
    lathe_axis(md, (0, 0, 1.030), (0, 0, 1), [(0.0, 0.040), (0.005, 0.050), (0.19, 0.050), (0.195, 0.040)], "spine",
               "RobotJoint", seg=16)
    for k, z in enumerate((1.068, 1.100, 1.132, 1.164)):          # waist discs
        r = 0.072 if k % 2 == 0 else 0.078
        lathe_axis(md, (0, 0, z), (0, 0, 1), [(0.0, r - 0.006), (0.003, r), (0.019, r), (0.022, r - 0.006)],
                   "spine", "RobotTrim", seg=22)
    lathe_axis(md, (0, 0, 1.052), (0, 0, 1), [(0.0, 0.074), (0.006, 0.080), (0.010, 0.080), (0.016, 0.074)], "hips",
               "RobotLight", seg=22)                                  # waist light ring
    stations(md, CHEST, "chest", "RobotChrome", n=2.3, seg=24)
    # chest light: a lens in a graphite bezel on the front
    front = surf_pt(CHEST, 1.335, 0.0, 0.0, 2.3)
    lathe_axis(md, front + Vector((-0.012, 0, 0)), (1, 0, 0), [(0.0, 0.040), (0.014, 0.044), (0.020, 0.038)],
               "chest", "RobotJoint", seg=20, ref=(0, 0, 1))
    lathe_axis(md, front + Vector((0.002, 0, 0)), (1, 0, 0), [(0.0, 0.028), (0.008, 0.026), (0.011, 0.012)],
               "chest", "RobotLight", seg=20, ref=(0, 0, 1))
    # panel line across the chest (a graphite band)
    patch(md, CHEST, 1.246, 1.256, -1.3, 1.3, 0.003, "chest", "RobotJoint", rows=1, cols=20, n=2.3)
    # neck: ribbed graphite column
    nb, nt = Vector((0.005, 0, 1.455)), Vector((0.016, 0, 1.600))
    tube(md, nb, nt, [0.024, 0.032, 0.036, 0.031, 0.036, 0.031, 0.036, 0.032, 0.024], "neck", "RobotJoint", seg=16)
    # head: chrome shell, visor, light bar, ear pods
    stations(md, HEAD, "head", "RobotChrome", n=2.2, seg=26)
    patch(md, HEAD, 1.648, 1.724, -1.25, 1.25, 0.004, "head", "RobotVisor", rows=5, cols=18, n=2.2)
    patch(md, HEAD, 1.679, 1.695, -0.95, 0.95, 0.0075, "head", "RobotLight", rows=1, cols=16, n=2.2)
    for sg in (1.0, -1.0):
        c = Vector((0.018, sg * 0.084, 1.690))
        lathe_axis(md, c, (0, sg, 0), [(0.0, 0.030), (0.012, 0.031), (0.020, 0.026), (0.022, 0.012)], "head",
                   "RobotJoint", seg=18, ref=(1, 0, 0))
        lathe_axis(md, c + Vector((0, sg * 0.021, 0)), (0, sg, 0), [(0.0, 0.020), (0.002, 0.021), (0.004, 0.016)],
                   "head", "RobotLight", seg=18, ref=(1, 0, 0))
    # a trim crest along the top of the head (front to back)
    patch(md, HEAD, 1.795, 1.803, -0.12, 0.12, 0.004, "head", "RobotTrim", rows=1, cols=2, n=2.2)


def build_arm_left(md):
    sh, el, wr = N.SH_JOINT, N.EL_JOINT, N.WR_JOINT
    ua = (el - sh).normalized()
    fa = (wr - el).normalized()
    # shoulder cap (shoulder bone) and ball joint
    sphere(md, sh + Vector((0.0, -0.008, 0.022)), 0.066, "shoulder.L", "RobotChrome", seg=18, rows=10,
           scale=(1.05, 1.0, 0.82))
    sphere(md, sh, 0.047, "upper_arm.L", "RobotJoint", seg=14, rows=8)
    tube(md, sh + ua * 0.035, el - ua * 0.028, [0.020, 0.040, 0.045, 0.043, 0.040, 0.036, 0.020], "upper_arm.L",
         "RobotChrome", seg=18)
    tube(md, sh + ua * 0.120, sh + ua * 0.140, [0.044, 0.047, 0.047, 0.044], "upper_arm.L", "RobotTrim", seg=18)
    sphere(md, el, 0.036, "forearm.L", "RobotJoint", seg=14, rows=8)
    tube(md, el + fa * 0.028, wr - fa * 0.018, [0.018, 0.035, 0.037, 0.034, 0.030, 0.026, 0.016], "forearm.L",
         "RobotChrome", seg=18)
    # light strip along the back of the forearm (the side away from the palm)
    back = -N.PALM_N
    tube(md, el + fa * 0.07 + back * 0.030, wr - fa * 0.06 + back * 0.024, [0.003, 0.0062, 0.0062, 0.0062, 0.003],
         "forearm.L", "RobotLight", seg=8)
    sphere(md, wr, 0.023, "hand.L", "RobotJoint", seg=12, rows=7)
    build_hand_left(md)


HAND_GRIP = dict(d=0.060, n=0.059)      # a 4.5 cm pole axis in the hand frame: along the fingers, off the palm


def build_hand_left(md):
    """A mechanical hand in a loose grip (it closes round a 4.5 cm pole: HAND_GRIP)."""
    wr = N.WR_JOINT
    d = N._FA.normalized()
    n = N.PALM_N.normalized()
    s = n.cross(d).normalized()                     # thumb side (left hand: thumb = n x d)
    # palm block
    rings = []
    for t, hw, ht in ((0.006, 0.020, 0.010), (0.016, 0.034, 0.015), (0.050, 0.039, 0.016), (0.080, 0.038, 0.014),
                      (0.090, 0.030, 0.010)):
        rings.append(ring(wr + d * t, s, n, hw, hw, ht, ht, n=3.2, seg=16))
    loft(md, rings, "hand.L", "RobotChrome")
    # fingers: three phalanges curled towards the palm (angles from the finger direction towards the palm normal)
    for k, (off, sc) in enumerate(((-0.027, 0.88), (-0.009, 1.0), (0.009, 0.97), (0.027, 0.84))):
        p = wr + d * 0.084 + s * off + n * 0.004
        for L, ang, r0, r1 in ((0.036, 20.0, 0.0088, 0.0082), (0.030, 80.0, 0.0080, 0.0074), (0.022, 122.0, 0.0072, 0.0060)):
            a = radians(ang)
            dirv = (d * cos(a) + n * sin(a)).normalized()
            q = p + dirv * (L * sc)
            tube(md, p, q, [r0 * 0.7, r0, r1, r1 * 0.7], "hand.L", "RobotChrome", seg=8, ref=tuple(s))
            sphere(md, p, r0 * 0.95, "hand.L", "RobotJoint", seg=8, rows=5)
            p = q
    # thumb: two phalanges from the palm's thumb side, along the pole axis (clear of a 4.5 cm pole in the grip)
    p = wr + d * 0.024 + s * 0.032 + n * 0.006
    for L, dv in ((0.034, s * 0.80 + n * 0.40 - d * 0.20), (0.027, s * 0.80 + n * 0.35 - d * 0.30)):   # along the pole
        q = p + dv.normalized() * L
        tube(md, p, q, [0.0065, 0.0095, 0.0088, 0.0065], "hand.L", "RobotChrome", seg=8, ref=tuple(n))
        sphere(md, p, 0.0092, "hand.L", "RobotJoint", seg=8, rows=5)
        p = q


def build_leg_left(md):
    hip, knee, ank = N.HIP_JOINT, N.KNEE_JOINT, N.ANKLE_JOINT
    th = (knee - hip).normalized()
    sh = (ank - knee).normalized()
    sphere(md, hip, 0.058, "thigh.L", "RobotJoint", seg=16, rows=9)
    tube(md, hip + th * 0.045, knee - th * 0.034, [0.034, 0.078, 0.084, 0.080, 0.072, 0.062, 0.052, 0.032],
         "thigh.L", "RobotChrome", seg=22)
    tube(md, hip + th * 0.20, hip + th * 0.22, [0.074, 0.078, 0.078, 0.074], "thigh.L", "RobotTrim", seg=22)
    sphere(md, knee, 0.044, "shin.L", "RobotJoint", seg=14, rows=8)
    sphere(md, knee + Vector((0.040, 0.0, 0.006)), 0.034, "shin.L", "RobotTrim", seg=16, rows=8,
           scale=(0.45, 1.25, 1.45))                                         # knee plate
    tube(md, knee + Vector((0.052, 0.0, -0.012)), knee + Vector((0.052, 0.0, 0.024)), [0.003, 0.005, 0.005, 0.003],
         "shin.L", "RobotLight", seg=8, ref=(0, 1, 0))
    tube(md, knee + sh * 0.036, ank - sh * 0.030, [0.024, 0.050, 0.052, 0.047, 0.041, 0.035, 0.030, 0.018],
         "shin.L", "RobotChrome", seg=20)
    tube(md, knee + sh * 0.09 + Vector((0.049, 0, 0)), ank - sh * 0.11 + Vector((0.034, 0, 0)),
         [0.003, 0.0065, 0.0065, 0.0065, 0.003], "shin.L", "RobotLight", seg=8, ref=(0, 1, 0))
    sphere(md, ank, 0.031, "foot.L", "RobotJoint", seg=12, rows=7)
    # foot and toe: lofts along +x at y = ankle y; (x, zc, half width, half height)
    y = ank.y
    foot = [(-0.110, 0.046, 0.028, 0.030), (-0.092, 0.050, 0.041, 0.044), (-0.030, 0.054, 0.045, 0.050),
            (0.040, 0.046, 0.048, 0.041), (0.114, 0.036, 0.045, 0.033)]
    toe = [(0.122, 0.034, 0.044, 0.031), (0.165, 0.031, 0.042, 0.028), (0.196, 0.029, 0.034, 0.022),
           (0.206, 0.028, 0.016, 0.012)]
    for part, bone in ((foot, "foot.L"), (toe, "toe.L")):
        rings = [ring(Vector((x, y, zc)), Vector((0, 1, 0)), Vector((0, 0, 1)), hw, hw, hh, hh, n=2.8, seg=16)
                 for x, zc, hw, hh in part]
        # the ring's w = u x v = +x, so the stations progress along +x
        loft(md, rings, bone, "RobotChrome")
    # a graphite sole plate
    rings = [ring(Vector((x, y, 0.009)), Vector((0, 1, 0)), Vector((0, 0, 1)), hw * 0.96, hw * 0.96, 0.009, 0.009,
                  n=3.0, seg=12) for x, _, hw, _ in foot[1:]]
    loft(md, rings, "foot.L", "RobotJoint")


def mirrored(md_left, name):
    out = PM.MeshData(name)
    for p, r in zip(md_left.verts, md_left.rules):
        out.v(Vector((p.x, -p.y, p.z)), mirror_bone(r))
    for f, m, s_, uv in zip(md_left.faces, md_left.fmat, md_left.fsmooth, md_left.fuv):
        out.f(tuple(reversed(f)), m, s_, None)
    return out


def build_mesh():
    md = PM.MeshData("Robot_dancer")
    build_core(md)
    left = PM.MeshData("left")
    build_arm_left(left)
    build_leg_left(left)
    md.append(left)
    md.append(mirrored(left, "right"))
    return md


def build(clips=True):
    import robot_anims as RA
    t0 = time.time()
    C.reset_scene()
    sc = bpy.context.scene
    sc.render.fps = N.FPS
    sc.render.fps_base = 1.0
    rig = N.build_rig("Rig")
    md = build_mesh()
    tris = md.tris()
    ob = PM.to_object(md, rig)
    for m in ob.data.materials:
        if m.name.split(".")[0] == "RobotLight":
            bsdf = next(n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
            bsdf.inputs["Emission Strength"].default_value = LIGHT_STRENGTH
    bpy.context.view_layer.update()
    C.bake_ao({ob.name: ob}, {ob.name: [ob.name]}, dist=0.10, samples=48, min_ao=0.45, strength=1.0, verbose=False)
    N.smooth_ao(ob, iterations=2, floor={"RobotChrome": 0.60, "RobotJoint": 0.50, "RobotTrim": 0.55,
                                         "RobotVisor": 0.60, "RobotLight": 1.0})
    meta = {}
    if clips:
        solver = N.Solver()
        solver.set_rest_from_rig(rig)
        for name, fn, frames, info in RA.robot_clips():
            N.bake_clip(rig, solver, name, fn, frames)
            meta[name] = dict(frames=frames, duration_s=round(frames / N.FPS, 4), loop=True, **info)
    N.reset_pose(rig)
    N.export_glb_skinned(PATH)
    print("  robot_dancer: %d tris, %d clips, %.1f s" % (tris, len(meta), time.time() - t0))
    return dict(tris=tris, clips=meta)


def write_manifest(res):
    import robot_anims as RA
    M = {
        "version": "5.0",
        "file": "robot_dancer.glb",
        "mesh": "Robot_dancer",
        "triangles": res["tris"],
        "skeleton": {"bones": N.BONE_NAMES[:24], "note": "The v3 skeleton at 1.80 m (the astronaut rig: same names, "
                     "parents and bind).  The v3 astronaut clips also play on it."},
        "materials": {
            "RobotChrome": "plain chrome (metallic 1, roughness 0.13): needs the room's reflection probe / sky",
            "RobotJoint": "plain graphite", "RobotTrim": "plain", "RobotVisor": "plain, black glass",
            "RobotLight": "emissive (strength %.1f): tint per dancer / pulse with the club light show if you like "
                          "(a mode-1 style tint on the emission)" % LIGHT_STRENGTH},
        "vertex_color": "COLOR_0.r = baked ambient occlusion (as v3)",
        "clips": res["clips"],
        "chain": "Every robot clip is a loop that starts and ends on the same pose (the stand pose at the origin, "
                 "facing +X).  Play any clip after any other at a loop end with no blend (cut); within one clip the "
                 "seam is exact.",
        "anchor": {"name": "Anchor_Dancer_* (ART-B, the Club)", "origin": "the stand point on the podium top, 0.35 m "
                   "in front of the pole, facing the room (+X)", "pole_local": list(RA.POLE_LOCAL),
                   "pole_radius_m": RA.POLE_R, "podium_top_local_z": 0.0,
                   "note": "robot_pole needs the pole at pole_local (the anchor extras 'pole' is the pole axis in "
                           "world x, y; it is 0.35 m behind the stand point).  The other clips stay within 0.6 m of "
                           "the origin (the podium radius is 0.80 m)."},
        "style": "A machine: chrome, visible ball joints, a light-bar face, no human anatomy.  Performance and "
                 "acrobatic dance moves; nothing sexual.",
    }
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(M, fh, indent=1)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    res = build(clips="--no-clips" not in argv)
    if res["clips"]:
        write_manifest(res)


if __name__ == "__main__":
    main()
