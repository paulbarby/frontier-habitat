"""
Frontier Habitat 4.0 - ART-B vehicle library (docs/V4_DESIGN.md section 5). Blender 5.2, --background only.

Uses ext_common.py READ-ONLY (ART-HAB's) and ship_common.py (ART-B's: palette method, materials, stencil, export).

Vehicle file contract (assets/models/vehicle_<id>.glb). Front = +X, left = +Y (Blender); origin = centre of the
wheelbase on the ground, z = 0 at the tyre contact at rest. glTF: Blender (x, y, z) -> Godot (x, z, -y).
  Body            the fixed body (static detail). Top level.
  Susp_<w>        suspension, one per wheel. Top level. Origin on the strut axis at wheel-centre height.
                  Motion = TRANSLATION along the node's local Z (up): travel in [extras.travel_min, travel_max] m.
  Steer_<w>       (steering wheels only) child of Susp_<w>, same origin (the kingpin = the strut axis).
                  Motion = rotation about local Z (up), +deg = nose of the wheel to the left, |deg| <= steer_max_deg.
                  extras.steer_sign: +1 front axle, -1 rear axle (the rear wheels turn the other way).
  Wheel_<w>       child of Steer_<w> (or of Susp_<w> when it does not steer). Origin = hub centre.
                  Spin axis = the node's LOCAL X (for every wheel it points to the vehicle's left).
                  Rolling forward by d metres = rotate about local X by +d / extras.radius radians.
  Door_<name>     hinged leaves. Origin on the hinge, axis local X; extras.stow_deg: rotate about local X by
                  stow_deg * s degrees, s = 0 open (rest pose), 1 closed (as the ships).
  Cargo           mesh node: the load. Show it when the vehicle carries cargo, hide it when empty.
  Lights          mesh node: emissive lamp lenses (headlights, work lights). Show at dusk / when driving.
  Light_<name>    empties where RENDER puts a light: local +X = beam direction; extras role, colour, cone_deg,
                  range_m.
  Seat_<i>        empties: the colonist's stand point for the sit pose (ART-NPC contract: seat top 0.46 m above,
                  seat centre 0.30 m behind). Local +X = the way the colonist faces. extras.role driver/passenger.
  Anchor_<name>   empties: Anchor_Board_<i> (ground point to walk to before boarding seat i, +X faces the
                  vehicle), Anchor_Cargo (ground point for loading), Anchor_Controls (the driver's hand grip).
  Dust_<side>     empties at the rear tyre contact; local +X = the dust direction when driving forward.
Materials: Palette (white; paint colour x baked AO in COLOR_0) + named materials, <= 8 per file.
"""
import bpy
import os
import sys
import json
import math
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ship_common as SC                                   # noqa: E402
C = SC.C
from ext_common import Part, Anchor, T, RX, RY, RZ, S      # noqa: E402,F401
from mathutils import Vector, Matrix                       # noqa: E402

ROOT = C.ROOT
MODEL_DIR = C.MODEL_DIR
ART_DIR = os.path.join(ROOT, "art", "vehicles")
REPORT_JSON = os.path.join(ART_DIR, "vehicle_report.json")

ACCENT = {"rover_small": "#e07a3a", "rover_medium": "#e07a3a", "hopper": "#4a90d9", "satellite": "#c9a54a",
          "launch_pad": "#e07a3a"}
MAX_TRIS = {"rover_small": 6000, "rover_medium": 12000, "hopper": 10000, "satellite": 4000, "launch_pad": 10000}
MAX_MATS = 8
GRAPHITE = "Palette:#3a3f47"
PLATE = "Palette:#6b7078"
SOLAR = "Palette:#1b2a55"
LENS = "Palette:#e6edf3"
INK = "Palette:#2c3036"


class Node(Part):
    """a Part whose vertices are in local coordinates; place = local -> WORLD (rest pose); parent = node name"""

    def __init__(self, name, place=None, parent=None, props=None):
        super().__init__(name)
        self.place = place if place is not None else Matrix.Identity(4)
        self.parent = parent
        self.props = props or {}


def node_obj(node, mset):
    ob = SC.part_to_obj(node, mset)
    ob.matrix_world = node.place
    for k, v in node.props.items():
        ob[k] = v
    return ob


def set_parent(ob, parent_ob):
    """keep the world matrix; matrix_parent_inverse = identity so the glTF node transform is the plain local one"""
    bpy.context.view_layer.update()
    W = ob.matrix_world.copy()
    ob.parent = parent_ob
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = parent_ob.matrix_world.inverted() @ W


def build_vehicle(vid, builder, ao_dist=0.7, required=(), fname=None, ao_samples=32, ground=True):
    """builder() -> list of Node and (Anchor, props, parent_name_or_None)"""
    t0 = time.time()
    C.reset_scene()
    out = builder()
    nodes = [n for n in out if isinstance(n, Part)]
    anchors = [a for a in out if isinstance(a, tuple)]
    mset = SC.ShipMatSet(ACCENT[vid])
    objs = {}
    for n in nodes:                                  # parents are listed before their children
        if not n.faces:
            continue
        ob = node_obj(n, mset)
        objs[n.name] = ob
    bpy.context.view_layer.update()
    for n in nodes:
        if n.faces and n.parent:
            set_parent(objs[n.name], objs[n.parent])
    for a, props, parent in anchors:
        e = SC.anchor_obj(a, props)
        if parent:
            set_parent(e, objs[parent])
    bpy.context.view_layer.update()
    # AO: the wheels spin, so they get self-shadow only (no ground, no body) - a dark patch would turn with them
    wheels = [k for k in objs if k.startswith("Wheel_")]
    optional = [k for k in objs if k.startswith(("Door_", "Cargo", "Ramp", "Leg_", "Rocket", "Arm_", "Wing_", "Dish"))
                or k == "Lights"]
    main = [k for k in objs if k not in wheels and k not in optional]
    rest = {k: objs[k] for k in objs if k not in wheels}
    occ = {k: (main + wheels if k in main else main + wheels + [k]) for k in rest}
    C.bake_ao(rest, occ, dist=ao_dist, samples=ao_samples, min_ao=0.22, ground=ground)
    if wheels:
        C.bake_ao({k: objs[k] for k in wheels}, {k: [k] for k in wheels}, dist=ao_dist * 0.5, samples=24,
                  min_ao=0.4, ground=False)
    for ob in objs.values():
        SC.apply_palette(ob)
    os.makedirs(MODEL_DIR, exist_ok=True)
    path = os.path.join(MODEL_DIR, fname or ("vehicle_%s.glb" % vid))
    SC.export_glb(path)
    return check_vehicle(vid, path, time.time() - t0, required, ground)


def check_vehicle(vid, path, secs, required=(), ground=True):
    g, _ = C.read_glb(path)
    nodes = g["nodes"]
    names = [n.get("name", "") for n in nodes]
    tris_by, mats, flags = {}, set(), []
    no_c0 = []
    for n in nodes:
        if "mesh" not in n:
            continue
        cnt = 0
        for prim in g["meshes"][n["mesh"]]["primitives"]:
            acc = g["accessors"][prim["indices"]] if "indices" in prim else g["accessors"][prim["attributes"]["POSITION"]]
            cnt += acc["count"] // 3
            if "material" in prim:
                mats.add(g["materials"][prim["material"]]["name"])
            if "COLOR_0" not in prim["attributes"]:
                no_c0.append(n.get("name"))
        tris_by[n.get("name")] = cnt
    tris = sum(tris_by.values())
    if tris > MAX_TRIS[vid]:
        flags.append("triangles %d > %d" % (tris, MAX_TRIS[vid]))
    if len(mats) > MAX_MATS:
        flags.append("materials %d > %d" % (len(mats), MAX_MATS))
    if no_c0:
        flags.append("COLOR_0 missing on " + ", ".join(sorted(set(no_c0))))
    for need in required:
        if not any(nm == need or (need.endswith("*") and nm.startswith(need[:-1])) for nm in names):
            flags.append("no %s node" % need)
    for n in nodes:
        nm = n.get("name", "")
        ex = n.get("extras", {})
        if nm.startswith(("Door_", "Leg_", "Ramp")) and "stow_deg" not in ex:
            flags.append("%s has no stow_deg" % nm)
        if nm.startswith("Wheel_") and "radius" not in ex:
            flags.append("%s has no radius" % nm)
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            q = mw @ v.co
            lo = Vector((min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z)))
            hi = Vector((max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z)))
    if ground and lo.z < -0.02:
        flags.append("below the ground: z %.2f" % lo.z)
    row = dict(id=os.path.basename(path)[:-4], tris=tris, tris_by=tris_by, materials=sorted(mats), n_materials=len(mats),
               length=round(hi.x - lo.x, 2), width=round(hi.y - lo.y, 2), height=round(hi.z, 2),
               x=[round(lo.x, 2), round(hi.x, 2)], y=[round(lo.y, 2), round(hi.y, 2)], zmin=round(lo.z, 3),
               nodes=names, kb=os.path.getsize(path) // 1024, flags=flags, seconds=round(secs, 1))
    print("  %-20s %6d tris  %d mats  L %.2f W %.2f H %.2f  %d KB  %s" % (
        row["id"], tris, len(mats), row["length"], row["width"], row["height"], row["kb"], "; ".join(flags) or "ok"))
    os.makedirs(ART_DIR, exist_ok=True)
    rep = {}
    if os.path.exists(REPORT_JSON):
        try:
            rep = json.load(open(REPORT_JSON, encoding="utf-8"))
        except Exception:
            rep = {}
    rep[row["id"]] = row
    json.dump(rep, open(REPORT_JSON, "w", encoding="utf-8"), indent=1)
    return row


# ======================================================================================
# shared vehicle parts
# ======================================================================================
def helix(p, c, r, z0, z1, turns, wire, mat, per_turn=5, seg=3):
    pts = []
    n = int(turns * per_turn)
    for i in range(n + 1):
        a = 2 * math.pi * i / per_turn
        pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z0 + (z1 - z0) * i / n))
    p.tube(pts, wire, seg=seg, mat=mat, smooth=True, caps=False)


def lens(body, lights, pos, normal, r, housing=(0.06, 0.15, 0.10), seg=8, lit="Light"):
    """a lamp: dark housing box, pale lens (day), emissive lens in `lights` (night)"""
    n = Vector(normal).normalized()
    pos = Vector(pos)
    if housing:
        body.beam(pos - n * housing[0], pos, housing[1], housing[2], GRAPHITE, up=(0, 0, 1) if abs(n.z) < 0.9 else (1, 0, 0))
    u = Vector((0, 0, 1)).cross(n) if abs(n.z) < 0.9 else Vector((1, 0, 0)).cross(n)
    u.normalize()
    v = n.cross(u)

    def disc(part, off, rr, mat):
        part.poly([pos + n * off + (u * math.cos(2 * math.pi * i / seg) + v * math.sin(2 * math.pi * i / seg)) * rr
                   for i in range(seg)], mat)
    disc(body, 0.004, r, LENS)
    if lights is not None:
        disc(lights, 0.008, r * 0.92, lit)


def light_anchor(name, pos, aim, role, colour="#fff4e0", cone=50.0, rng=18.0):
    aim = Vector(aim).normalized()
    return (Anchor(name, pos, forward=aim, up=(0, 0, 1) if abs(aim.z) < 0.95 else (1, 0, 0)),
            {"role": role, "colour": colour, "cone_deg": cone, "range_m": rng}, None)


RUBBER = "Palette:#1c1e22"


def tyre(p, r, half_w, side, n=14, lugs=16, lug_h=None, rim_r=None, seg_rim=8, bolts=5):
    """wheel in its node frame: spin axis = local X; side = +1 if the outer face is at local +X, else -1.
    Critic round 16 fix 3: dark carcass + `lugs` chunky block lugs, staggered left/right (16 on the silhouette),
    deep recessed rim, graphite hub boss with bolts."""
    k = r / 0.44
    lug_h = lug_h or 0.045 * k
    rim_r = rim_r or r * 0.60
    w = half_w
    rb = r - lug_h
    lathe_to_node = RY(90) if side > 0 else RY(90) @ S(1, 1, -1)
    with p.at(lathe_to_node):
        p.lathe([(rim_r, -w), (rb - 0.035 * k, -w), (rb, -w * 0.6), (rb, w * 0.6), (rb - 0.035 * k, w), (rim_r, w)],
                RUBBER, seg=n)
        t = 2 * math.pi * rb / lugs * 0.5
        for j in range(lugs):
            a = 360.0 * j / lugs
            zc = w * 0.30 if j % 2 == 0 else -w * 0.30
            with p.at(RZ(a), T(rb + lug_h / 2 - 0.006, 0, zc)):
                p.box((0, 0, 0), (lug_h + 0.012, t, w * 1.25), RUBBER, mats={"-x": None})
        p.lathe([(rim_r, w), (rim_r * 0.88, w * 0.05), (rim_r * 0.42, 0.0), (rim_r * 0.38, w * 0.42), (0.0, w * 0.46)],
                lambda kk, i: "Palette:Trim" if kk == 0 else ("Palette:#9aa3ad" if kk == 1 else GRAPHITE), seg=seg_rim)
        zb = w * 0.46 + 0.004
        s = 0.018 * k
        for j in range(bolts):
            a = 2 * math.pi * j / bolts
            c = Vector((rim_r * 0.24 * math.cos(a), rim_r * 0.24 * math.sin(a), zb))
            p.poly([c + Vector((-s, -s, 0)), c + Vector((s, -s, 0)), c + Vector((s, s, 0)), c + Vector((-s, s, 0))],
                   "Palette:Trim")
        p.lathe([(0.0, -w * 0.5), (rim_r, -w)], "Palette:HullDark", seg=seg_rim)


class WheelKit:
    """the wheel + strut + cycle fender set; every length scales with k (small rover k = 1, medium 1.3)"""

    def __init__(self, k=1.0, travel=(-0.15, 0.12), steer_max=25.0, accent="Accent"):
        self.k = k
        self.r = 0.44 * k
        self.hw = 0.17 * k
        self.off = 0.30 * k            # kingpin -> hub centre, laterally
        self.travel = (travel[0] * k, travel[1] * k)
        self.steer_max = steer_max
        self.accent = accent
        self.sleeve = (0.60 * k, 0.90 * k)     # strut sleeve (body part), above hub height

    def strut_top(self, b, x, sy, y_kp, z_hub):
        """the fixed upper strut sleeve and its bracket (on the Body)"""
        k = self.k
        b.vcyl(x, sy * y_kp, z_hub + self.sleeve[0], z_hub + self.sleeve[1], 0.05 * k, seg=8, mat="Palette:Frame")
        b.box((x, sy * (y_kp - 0.06 * k), z_hub + self.sleeve[1] + 0.01 * k), (0.14 * k, 0.18 * k, 0.05 * k), GRAPHITE)

    def assembly(self, wid, x, sy, st, y_kp, z_hub):
        """Susp_<w> (+ Steer_<w>) + Wheel_<w> nodes; the fender rides on the steering node (cycle fender)"""
        k = self.k
        out = []
        place = T(x, sy * y_kp, z_hub)
        su = Node("Susp_" + wid, place, None, {"axis": "local Z (translate)", "travel_min": round(self.travel[0], 3),
                                               "travel_max": round(self.travel[1], 3), "wheel": wid})
        su.cyl((0, 0, 0.05 * k), (0, 0, 0.80 * k), 0.028 * k, seg=6, mat="Palette:Trim")
        su.vcyl(0, 0, 0.31 * k, 0.34 * k, 0.095 * k, seg=8, mat="Palette:Frame")
        helix(su, (0, 0, 0), 0.08 * k, 0.34 * k, 0.72 * k, 3.0, 0.018 * k, self.accent, per_turn=4)
        out.append(su)
        carrier = su
        if st:
            stn = Node("Steer_" + wid, place, su.name, {"axis": "local Z (rotate)", "steer_max_deg": self.steer_max,
                                                         "steer_sign": st})
            out.append(stn)
            carrier = stn
        carrier.box((0, sy * 0.03 * k, 0.0), (0.16 * k, 0.12 * k, 0.18 * k), "Palette:Frame")          # knuckle
        carrier.cyl((0, sy * 0.06 * k, 0), (0, sy * (self.off - 0.10 * k), 0), 0.05 * k, seg=6, mat="Palette:Trim",
                    cap0=False, cap1=False)
        if st:
            carrier.beam((0, sy * 0.05 * k, -0.06 * k), (-0.20 * k * st, sy * 0.05 * k, -0.06 * k), 0.05 * k, 0.04 * k,
                         "Palette:Frame")
        # cycle fender (round 16 fixes 1-2): graphite, 7 cm over the tyre, 3 cm thick, thin accent lip outside
        r_in, r_out = self.r + 0.07 * k, self.r + 0.10 * k
        y0, y1 = self.off - self.hw - 0.03 * k, self.off + self.hw + 0.03 * k
        lo, hi = sorted((-sy * y0, -sy * y1))
        outer_band = 0 if sy > 0 else 2

        def fmat(kk, i):
            return self.accent if kk == outer_band else GRAPHITE
        with carrier.at(RX(90)):
            carrier.lathe([(r_in, lo), (r_out, lo), (r_out, hi), (r_in, hi)], fmat, seg=8, a0=18.0, a1=162.0,
                          wrap=True, smooth=False, cap_mat=GRAPHITE)
        for a in (90.0,):
            ar = math.radians(a)
            top = Vector((r_in * math.cos(ar), sy * (y0 + 0.02 * k), r_in * math.sin(ar)))
            carrier.beam((0, sy * 0.08 * k, 0.08 * k), top, 0.035 * k, 0.035 * k, "Palette:Frame")
        wheel_place = T(x, sy * (y_kp + self.off), z_hub) @ RZ(90)
        wh = Node("Wheel_" + wid, wheel_place, carrier.name, {"radius": round(self.r, 3), "spin_axis": "local X",
                                                               "wheel": wid})
        tyre(wh, self.r, self.hw, side=sy)
        out.append(wh)
        return out


# ======================================================================================
# colony door kit for vehicle hatches (critic round 16: "a hatch that matches the airlock doors")
# the door faces -X; x_face = the body face the frame stands on
# ======================================================================================
def door_frame(b, x_face, half_w, z0, z1, colour, depth=0.14, stripes=6):
    xf = x_face - depth / 2
    for sy in (-1, 1):
        b.box((xf, sy * (half_w + 0.06), (z0 + z1) / 2 - 0.02), (depth, 0.12, z1 - z0 + 0.14), colour)
        step = (z1 - z0 - 0.2) / stripes
        for k in range(stripes):                                           # hazard diagonals on the post face
            za = z0 + 0.10 + k * step
            y0, y1 = sy * (half_w + 0.005), sy * (half_w + 0.115)
            q = [Vector((xf - depth / 2 - 0.002, y0, za)), Vector((xf - depth / 2 - 0.002, y1, za + step / 3)),
                 Vector((xf - depth / 2 - 0.002, y1, za + 2 * step / 3)), Vector((xf - depth / 2 - 0.002, y0, za + step / 3))]
            SC.emit_oriented(b, q, Vector((-1, 0, 0)), "Palette:Hazard")
    b.box((xf, 0, z1 + 0.07), (depth, 2 * half_w + 0.24, 0.14), colour)
    b.box((xf - depth / 2 - 0.005, 0, z1 + 0.07), (0.01, min(0.60, 1.4 * half_w), 0.04), "StatusGreen")
    b.box((xf, 0, z0 - 0.03), (depth + 0.02, 2 * half_w + 0.24, 0.06), GRAPHITE)
    b.box((x_face - 0.015, 0, (z0 + z1) / 2), (0.02, 2 * half_w, z1 - z0), "Palette:#2c3036")


def door_leaf(name, hinge, w, h, side, colour, t=0.05):
    """one leaf in the door-kit look; side +1 = hinge on the +Y edge. Rest = open (swung out, pointing -X);
    stow_deg = 90 * side closes it (rotation about the vertical hinge = local X)."""
    Mx = Matrix(((0, -1, 0, 0), (0, 0, -1, 0), (1, 0, 0, 0), (0, 0, 0, 1)))      # cols: X=(0,0,1) Y=(-1,0,0) Z=(0,-1,0)
    d = Node(name, Matrix.Translation(Vector(hinge)) @ Mx, None, {"stow_deg": 90.0 * side})
    oz = -1 if side > 0 else 1                         # the outside face when closed
    d.box((h / 2, w / 2, 0), (h, w, t), colour)
    z_out = oz * (t / 2 + 0.003)
    nref = Vector((0, 0, oz))

    def plate(x0, x1, y0, y1, mat, lift=0.0):
        zz = z_out + oz * lift
        SC.emit_oriented(d, [Vector((x0, y0, zz)), Vector((x1, y0, zz)), Vector((x1, y1, zz)), Vector((x0, y1, zz))], nref, mat)
    wy0, wy1 = (w - 0.25, w - 0.16) if w < 0.6 else (w * 0.5 - 0.05, w * 0.5 + 0.05)
    plate(h * 0.53, h * 0.94, wy0, wy1, SC.DGLASS)                                   # window strip
    plate(h * 0.52, h * 0.95, wy0 - 0.02, wy1 + 0.02, GRAPHITE, -0.001)
    plate(0.02, 0.50, 0.04, w - 0.04, "Palette:HullDark")                           # kick plate
    for z in (h * 0.50, h * 0.69, h * 0.99):
        plate(z, z + 0.015, 0.06, w - 0.12, GRAPHITE)
    for k in range(int((h * 0.55) / 0.13)):                                        # chevrons at the meeting edge
        za = 0.54 + 0.13 * k
        m = "Palette:Hazard" if k % 2 == 0 else "Palette:Rubber"
        zz = z_out + oz * 0.001
        q = [Vector((za, w - 0.10, zz)), Vector((za + 0.04, w - 0.02, zz)), Vector((za + 0.105, w - 0.02, zz)),
             Vector((za + 0.065, w - 0.10, zz))]
        SC.emit_oriented(d, q, nref, m)
    d.box((h / 2, w - 0.004, 0), (h, 0.012, t + 0.012), "Palette:Rubber")               # seal line
    return d
