"""
Frontier Habitat 5.0 - ART-B super dome library (docs/V5_DESIGN.md section 8). Blender 5.2, --background only.

Files (assets/models/dome_*.glb, listed in assets/models/dome_manifest.json). All share one origin: the dome centre on
the ground, Blender Z up (Godot Y up), no rotation between files.
  dome_shell.glb    Foundation (base disc, plinth, promenade), Gates, Dome (glass, frame, node lights)
  dome_floor1.glb   Floor_1: the ground level ring (shops and businesses, colonnade, passages, facade)
  dome_floor2..5    Floor_2 .. Floor_5 (L2 businesses; L3-L5 accommodation), Floor_Roof in dome_floor5
  dome_atrium.glb   Atrium (plaza, pool, slide, fountain, park strip), Lifts (shafts) + Lift_<i> cabs
Top-level node contract (RENDER groups them by these names):
  Floor_<n>          everything of level n: its slab (the ceiling of level n-1), walls, fronts, venues, props.
                     Floor cutaway = hide Floor_<k> for k > viewed floor (and Dome, Floor_Roof).
  Floor_<n> children: Struct_<n> (slab, columns, facade frame: the "structure" build stage), Shell_<n>
                     (glazing, balustrades, unit fronts: fit-out), Venue_<id> (one venue's front, sign, interior)
  Dome / Foundation / Gates / Promenade / Atrium / Lifts / Lift_<i>
  Every node carries extras {"floor": n (0 = ground outside the ring), "stage": "<build stage>"}.
Anchors: Anchor_<Kind>_<id> with extras {"floor": n, "height": z (m, Blender Z = Godot Y), "venue": id, ...}.
"""
import bpy
import os
import sys
import json
import math
import time
from math import sin, cos, pi, radians, degrees, sqrt, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ship_common as SC                                   # noqa: E402
import vehicle_common as VC                                # noqa: E402
C = SC.C
from ext_common import Part, Anchor, T, RX, RY, RZ, S      # noqa: E402,F401
from mathutils import Vector, Matrix                       # noqa: E402

ROOT = C.ROOT
MODEL_DIR = C.MODEL_DIR
ART_DIR = os.path.join(ROOT, "art", "dome")
REPORT_JSON = os.path.join(ART_DIR, "dome_report.json")
MANIFEST = os.path.join(MODEL_DIR, "dome_manifest.json")

# ---- the dome in numbers (V5 section 8) ------------------------------------------------------------
R_BASE = 48.0                      # dome radius at the ground
DOME_H = 38.0                      # total height
RS = (R_BASE ** 2 + DOME_H ** 2) / (2 * DOME_H)          # sphere radius of the cap (49.32)
CZ = DOME_H - RS                   # sphere centre z (-11.32)
R_IN, R_OUT = 20.0, 34.0           # the ring building: atrium edge, outer wall (ring depth 14 m)
R_FRONT = 23.0                     # shop / unit fronts (behind the 3 m gallery)
R_WALL = 33.6                      # inner face of the outer wall
GROUND = 0.30                      # foundation top = L1 floor
FLOOR_Z = [GROUND, 5.30, 9.50, 13.70, 17.90]             # floor tops of L1..L5
ROOF_Z = 22.10                     # roof slab top
SLAB = 0.35                        # slab thickness
N_SEC = 24                         # ring sectors (15 deg each)
SEC = 360.0 / N_SEC
PASSAGES = (0, 6, 12, 18)          # L1 sectors that are open passages from the promenade to the atrium
LIFT_SECTORS = (3, 9, 15, 21)      # a glass lift stands in the atrium in front of these sectors
R_LIFT = 18.4
N_GATES = 12

GRAPHITE = "Palette:#3a3f47"
WHITE = "Palette:#e6e3dc"
CONCRETE = "Palette:#9aa0a6"
PAVING = "Palette:#b9b3a8"
TILE = "Palette:#d8d2c6"
SOFFIT = "Palette:#cfd2d6"
INK = "Palette:#2c3036"
PLANT = "Palette:#4f9a4a"
PLANT2 = "Palette:#3f7d3a"
TRUNK = "Palette:#6b4f3a"
WOOD = "Palette:#b08560"

SIGN_MATS = ("SignCyan", "SignMagenta", "SignAmber", "SignGreen")
DOME_SPEC = {
    # Glass is the name RENDER already treats as transparent; double-sided here (seen from inside and outside)
    "Glass": dict(color="#9cc9dc", rough=0.06, alpha=0.22, double_sided=True),
    "Water": dict(color="#1d78a8", rough=0.04, alpha=0.58, emit="#38d8ff", emit_strength=0.55, double_sided=True),
    # critic round 24 fix 1: several window tones (warm x3, cool x1); dark windows use dark glass (Palette)
    "WindowAmber": dict(color="#ffb45e", rough=0.4, emit="#ffb45e", emit_strength=0.75),
    "WindowCream": dict(color="#fff1d6", rough=0.4, emit="#fff1d6", emit_strength=0.6),
    "WindowCool": dict(color="#b8dcff", rough=0.4, emit="#b8dcff", emit_strength=0.6),
    # critic round 26: coloured lamps and TV-blue rooms break the even grid
    "WindowRose": dict(color="#ffb0d0", rough=0.4, emit="#ffb0d0", emit_strength=0.6),
    "WindowTV": dict(color="#5a8cff", rough=0.4, emit="#5a8cff", emit_strength=0.85),
    "Window": dict(color="#ffd9a0", rough=0.4, emit="#ffd9a0", emit_strength=0.9),
    "CabinWindow": dict(color="#ffd9a0", rough=0.4, emit="#ffd9a0", emit_strength=0.5),
    "Light": dict(color="#ffffff", rough=0.4, emit="#fff4e0", emit_strength=3.0),
    "SignCyan": dict(color="#39e6ff", rough=0.4, emit="#39e6ff", emit_strength=3.0),
    "SignMagenta": dict(color="#ff4fd8", rough=0.4, emit="#ff4fd8", emit_strength=3.0),
    "SignAmber": dict(color="#ffb020", rough=0.4, emit="#ffb020", emit_strength=3.0),
    "SignGreen": dict(color="#5ee07a", rough=0.4, emit="#5ee07a", emit_strength=3.0),
    "Screen": dict(color="#123c4c", rough=0.25, emit="#2fb8d8", emit_strength=0.45),
    # the PRISM SHIFT arcade screen (V5 4.5): RENDER replaces it with its attract-loop shader (UV 0..1)
    "ArcadeScreen": dict(color="#05060a", rough=0.2, emit="#ff4fd8", emit_strength=0.5),
}


class DomeMatSet(SC.ShipMatSet):
    def spec(self, name):
        if name in DOME_SPEC:
            return DOME_SPEC[name]
        return super().spec(name)


# ======================================================================================
# geometry helpers (polar)
# ======================================================================================
def pol(r, a_deg, z=0.0):
    a = radians(a_deg)
    return Vector((r * cos(a), r * sin(a), z))


def arc(r, a0, a1, n, z):
    return [pol(r, a0 + (a1 - a0) * i / n, z) for i in range(n + 1)]


def quad(p, q, nref, mat):
    SC.emit_oriented(p, q, nref, mat)


def sector_prism(p, r0, r1, a0, a1, z0, z1, top, bot=None, inner=None, outer=None, ends=None, n=3):
    """annulus sector solid; any face material None = not built"""
    I0, I1, O0, O1 = arc(r0, a0, a1, n, z0), arc(r0, a0, a1, n, z1), arc(r1, a0, a1, n, z0), arc(r1, a0, a1, n, z1)
    for i in range(n):
        am = a0 + (a1 - a0) * (i + 0.5) / n
        rad = pol(1.0, am)
        if top:
            quad(p, [I1[i], I1[i + 1], O1[i + 1], O1[i]], Vector((0, 0, 1)), top)
        if bot:
            quad(p, [I0[i], I0[i + 1], O0[i + 1], O0[i]], Vector((0, 0, -1)), bot)
        if inner:
            quad(p, [I0[i], I0[i + 1], I1[i + 1], I1[i]], -rad, inner)
        if outer:
            quad(p, [O0[i], O0[i + 1], O1[i + 1], O1[i]], rad, outer)
    if ends:
        for (A0, A1, B0, B1, a) in ((I0[0], I1[0], O0[0], O1[0], a0), (I0[-1], I1[-1], O0[-1], O1[-1], a1)):
            tan = pol(1.0, a + 90.0) * (1 if a == a1 else -1)
            quad(p, [A0, B0, B1, A1], tan, ends)


def chord_box(p, r, a, w, d, z0, z1, mat, mats=None):
    """a box standing on a chord at radius r (its centre), angle a deg: w along the tangent, d along the radius"""
    with p.at(RZ(a)):
        p.box((r, 0, (z0 + z1) / 2), (d, w, z1 - z0), mat, mats=mats)


def radial_wall(p, a, r0, r1, z0, z1, t, mat):
    with p.at(RZ(a)):
        p.box(((r0 + r1) / 2, 0, (z0 + z1) / 2), (r1 - r0, t, z1 - z0), mat)


DARK_GLASS = "Palette:#1a2230"
WINDOW_TONES = ("CabinWindow", "Window", "WindowAmber", "WindowCream", "WindowCool")


def hsh(*k):
    """a small deterministic hash in 0..1"""
    h = 2166136261
    for v in k:
        for ch in str(v):
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return (h % 10007) / 10007.0


def window_tone(*key, dark=0.25, cool=0.15, colour=0.0):
    """critic round 24 fix 1: 20-30 % dark, one cool tone, three warm tones; round 26: some TV-blue / rose rooms"""
    u = hsh(*key)
    if u < dark:
        return DARK_GLASS
    if u < dark + colour:
        return "WindowTV" if hsh("c", *key) < 0.6 else "WindowRose"
    if u < dark + colour + cool:
        return "WindowCool"
    return ("CabinWindow", "Window", "WindowAmber", "WindowCream")[int(hsh("t", *key) * 4) % 4]


def leaf_cluster(p, c, s=1.0, n=7, seed=0, tilt=0.45):
    """a crown of n bent leaves (Plant, double-sided), the look of the v4 greenhouse plants"""
    c = Vector(c)
    for k in range(n):
        a = 360.0 * k / n + (hsh(seed, k) - 0.5) * 30.0
        L = s * (0.7 + 0.4 * hsh(seed, k, "l"))
        w = 0.16 * s
        up = tilt + 0.3 * hsh(seed, k, "u")
        with p.at(T(*c), RZ(a)):
            mid = Vector((L * 0.55, 0, L * up * 0.9))
            tip = Vector((L, 0, L * up * 0.2))
            p.poly([Vector((0, -w * 0.4, 0)), Vector((0, w * 0.4, 0)), Vector((mid.x, w, mid.z)), Vector((mid.x, -w, mid.z))], "Plant")
            p.poly([Vector((mid.x, -w, mid.z)), Vector((mid.x, w, mid.z)), Vector((tip.x, w * 0.2, tip.z)),
                    Vector((tip.x, -w * 0.2, tip.z))], "Plant" if k % 2 else "PlantDark")


def tree(p, c, h=4.0, r=1.4, mat=None, seed=0):
    """broadleaf tree (critic round 24 fix 7): a tapered trunk with two forks and leaf crowns, no lumpy spheres"""
    c = Vector(c)
    top = c + Vector((0, 0, h * 0.62))
    p.cyl(c, top, 0.10 * h / 4, 0.06 * h / 4, seg=6, mat=TRUNK)
    p.cyl(c, c + Vector((0, 0, 0.04)), 0.22 * h / 4, 0.14 * h / 4, seg=6, mat=TRUNK, cap0=False)
    crowns = [(top + Vector((0, 0, h * 0.10)), r * 0.95)]
    for k in range(3):
        a = 120.0 * k + 360.0 * hsh(seed, "f")
        tip = top + pol(r * 0.55, a, h * 0.05 + 0.2 * k)
        p.cyl(top - Vector((0, 0, 0.3)), tip, 0.045 * h / 4, 0.03 * h / 4, seg=4, mat=TRUNK)
        crowns.append((tip, r * 0.75))
    for k, (cc, rr) in enumerate(crowns):
        leaf_cluster(p, cc, s=rr, n=8, seed=seed * 7 + k, tilt=0.35)
        leaf_cluster(p, cc + Vector((0, 0, 0.25 * rr)), s=rr * 0.7, n=6, seed=seed * 7 + k + 50, tilt=0.6)


def palm(p, c, h=5.5, seed=0):
    """a curved palm with long fronds (pool deck)"""
    c = Vector(c)
    lean = pol(0.9, 360.0 * hsh(seed, "p"))
    pts = [c + lean * (f * f) + Vector((0, 0, h * f)) for f in (0.0, 0.3, 0.6, 0.85, 1.0)]
    p.tube(pts, 0.14, seg=6, mat=TRUNK, caps=False)
    top = pts[-1]
    for k in range(9):
        a = 40.0 * k + 30.0 * hsh(seed, k)
        L, w = 2.4 + 0.5 * hsh(seed, k, "L"), 0.32
        with p.at(T(*top), RZ(a)):
            q = [Vector((0, 0, 0)), Vector((L * 0.45, 0, 0.35)), Vector((L * 0.8, 0, -0.1)), Vector((L, 0, -0.6))]
            for i in range(3):
                w0, w1 = w * (1.0 - i * 0.3), w * (1.0 - (i + 1) * 0.3) + 0.02
                p.poly([q[i] + Vector((0, -w0, 0)), q[i] + Vector((0, w0, 0)), q[i + 1] + Vector((0, w1, 0)),
                        q[i + 1] + Vector((0, -w1, 0))], "Plant" if (i + k) % 2 else "PlantDark")
    p.sphere(tuple(top), 0.22, TRUNK, seg=6, rings=3, smooth=False)


def colony_bench(p, c, yaw, L=1.8):
    """the colony bench (critic round 24 fix 7): three wooden slats, a slatted back, graphite frame; sitter faces +X"""
    with p.at(T(*Vector(c)), RZ(yaw)):
        zs = 0.45
        for sy in (-1, 1):
            p.box((0.0, sy * (L / 2 - 0.12), zs / 2), (0.44, 0.06, zs), GRAPHITE, mats={"-z": None})
            p.box((-0.22, sy * (L / 2 - 0.12), zs + 0.22), (0.05, 0.06, 0.5), GRAPHITE)
        for k in range(3):
            p.box((-0.14 + 0.14 * k, 0, zs), (0.11, L, 0.04), WOOD)
        for k in range(2):
            p.box((-0.23, 0, zs + 0.2 + 0.16 * k), (0.03, L, 0.1), WOOD)


def mannequin(p, c, yaw=0.0, col="#e85d75", pants="#2c3036"):
    with p.at(T(*Vector(c)), RZ(yaw)):
        p.cyl((0, 0, 0), (0, 0, 0.03), 0.22, seg=8, mat=GRAPHITE)
        p.cyl((0, 0, 0.03), (0, 0, 0.9), 0.025, seg=4, mat=GRAPHITE, cap0=False)
        p.cyl((0, 0, 0.75), (0, 0, 1.05), 0.15, 0.13, seg=8, mat="Palette:" + pants)
        p.cyl((0, 0, 1.05), (0, 0, 1.5), 0.17, 0.2, seg=8, mat="Palette:" + col)
        p.sphere((0, 0, 1.64), 0.1, "Palette:#e8e4dc", seg=8, rings=4)


def lamp_post(p, lights, c, h=4.2):
    c = Vector(c)
    p.cyl(c, c + Vector((0, 0, h)), 0.07, 0.05, seg=6, mat=GRAPHITE)
    p.cyl(c + Vector((0, 0, h)), c + Vector((0, 0, h + 0.25)), 0.22, 0.10, seg=8, mat=GRAPHITE)
    lights.cyl(c + Vector((0, 0, h - 0.02)), c + Vector((0, 0, h + 0.03)), 0.18, seg=8, mat="Light")


def sign_text(p, text, centre, right, height, mat, normal, depth=0.03, plate=None, pad=0.18):
    """centred stencil text on a plane; optional dark plate behind it"""
    right, normal = Vector(right).normalized(), Vector(normal).normalized()
    up = normal.cross(right).normalized()
    if up.z < 0:
        up = -up
    length = (len(text) * 1.55 - 0.55) * height / 2
    centre = Vector(centre)
    if plate:
        c = centre - normal * 0.02
        pts = [c + right * sx * (length / 2 + pad) + up * sz * (height / 2 + pad) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        quad(p, pts, normal, plate)
    o = centre - right * (length / 2) - up * (height / 2)
    SC.stencil(p, text, o, right, up, height, mat, normal, depth=depth)
    return length


# ======================================================================================
# build: nodes (groups, meshes, anchors) -> AO -> palette -> export -> checks
# ======================================================================================
class Group:
    def __init__(self, name, parent=None, props=None):
        self.name, self.parent, self.props = name, parent, props or {}


def flat_ao(ob):
    me = ob.data
    attr = me.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    data = [1.0] * (len(attr.data) * 4)
    attr.data.foreach_set("color", data)
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
    except Exception:
        pass


def build_file(fname, builder, ao=None, report_key=None):
    """builder() -> list of Group, VC.Node (mesh, parent = a group name or None) and (Anchor, props, parent).
    ao: {"dist": m, "samples": n, "skip": [node names that get a flat AO]}"""
    t0 = time.time()
    C.reset_scene()
    out = builder()
    groups = [g for g in out if isinstance(g, Group)]
    nodes = [n for n in out if isinstance(n, Part)]
    anchors = [a for a in out if isinstance(a, tuple)]
    mset = DomeMatSet("#e07a3a")
    gobs = {}
    for g in groups:
        e = bpy.data.objects.new(g.name, None)
        e.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(e)
        for k, v in g.props.items():
            e[k] = v
        gobs[g.name] = e
    for g in groups:
        if g.parent:
            VC.set_parent(gobs[g.name], gobs[g.parent])
    objs = {}
    for n in nodes:
        if not n.faces:
            continue
        ob = VC.node_obj(n, mset)
        objs[n.name] = ob
    for ob in objs.values():                                  # UV 0..1 on every ArcadeScreen quad (loop order)
        me = ob.data
        idx = [i for i, m in enumerate(me.materials) if m and m.name.split(".")[0] == "ArcadeScreen"]
        if idx:
            uv = me.uv_layers.new(name="UVMap")
            for poly in me.polygons:
                if poly.material_index in idx and poly.loop_total == 4:
                    for j, li in enumerate(poly.loop_indices):
                        uv.data[li].uv = ((0, 0), (1, 0), (1, 1), (0, 1))[j]
    bpy.context.view_layer.update()
    for n in nodes:
        if n.faces and n.parent:
            VC.set_parent(objs[n.name], gobs[n.parent] if n.parent in gobs else objs[n.parent])
    for a, props, parent in anchors:
        e = SC.anchor_obj(a, props)
        if parent:
            VC.set_parent(e, gobs[parent] if parent in gobs else objs[parent])
    bpy.context.view_layer.update()
    ao = ao or {}
    skip = set(ao.get("skip", []))
    bake = {k: o for k, o in objs.items() if k not in skip}
    for k in skip:
        if k in objs:
            flat_ao(objs[k])
    if bake:
        names = list(bake)
        C.bake_ao(bake, {k: names for k in names}, dist=ao.get("dist", 1.2), samples=ao.get("samples", 16),
                  min_ao=0.3, ground=True)
    for ob in objs.values():
        SC.apply_palette(ob)
    os.makedirs(MODEL_DIR, exist_ok=True)
    path = os.path.join(MODEL_DIR, fname)
    SC.export_glb(path)
    return check_file(path, time.time() - t0, report_key or fname[:-4])


def check_file(path, secs, key):
    g, _ = C.read_glb(path)
    nodes = g["nodes"]
    tris_by, mats = {}, set()
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []):
            parent[c] = i

    def top(i):
        while i in parent:
            i = parent[i]
        return nodes[i].get("name")
    for i, nd in enumerate(nodes):
        if "mesh" not in nd:
            continue
        cnt = 0
        for prim in g["meshes"][nd["mesh"]]["primitives"]:
            acc = g["accessors"][prim["indices"]] if "indices" in prim else g["accessors"][prim["attributes"]["POSITION"]]
            cnt += acc["count"] // 3
            if "material" in prim:
                mats.add(g["materials"][prim["material"]]["name"])
        t = top(i)
        tris_by[t] = tris_by.get(t, 0) + cnt
    tris = sum(tris_by.values())
    anchors = [nd["name"] for nd in nodes if nd.get("name", "").startswith("Anchor_")]
    row = dict(file=os.path.basename(path), tris=tris, tris_by_top=tris_by, materials=sorted(mats),
               n_materials=len(mats), n_nodes=len(nodes), n_mesh_nodes=sum(1 for nd in nodes if "mesh" in nd),
               anchors=len(anchors), kb=os.path.getsize(path) // 1024, seconds=round(secs, 1))
    print("  %-18s %7d tris  %2d mats  %3d mesh nodes  %3d anchors  %5d KB  %s" % (
        row["file"], tris, len(mats), row["n_mesh_nodes"], len(anchors), row["kb"],
        ", ".join("%s %d" % kv for kv in sorted(tris_by.items()))))
    os.makedirs(ART_DIR, exist_ok=True)
    rep = {}
    if os.path.exists(REPORT_JSON):
        try:
            rep = json.load(open(REPORT_JSON, encoding="utf-8"))
        except Exception:
            rep = {}
    rep[key] = row
    json.dump(rep, open(REPORT_JSON, "w", encoding="utf-8"), indent=1)
    return row


def light_anchor(name, pos, aim, role, colour="#ffd9a0", cone=70.0, rng=10.0, floor=1):
    a = Vector(aim).normalized()
    return (Anchor(name, Vector(pos), forward=a, up=(0, 0, 1) if abs(a.z) < 0.95 else (1, 0, 0)),
            {"role": role, "colour": colour, "cone_deg": cone, "range_m": rng, "floor": floor, "height": round(Vector(pos).z, 3)},
            None)


def anchor(name, pos, forward=(1, 0, 0), floor=1, **props):
    p = Vector(pos)
    d = dict(floor=floor, height=round(p.z, 3))
    d.update(props)
    fw = Vector(forward)
    return (Anchor(name, p, forward=fw, up=(0, 0, 1) if abs(fw.normalized().z) < 0.95 else (1, 0, 0)), d, None)


def facing_in(a_deg):
    """unit vector from a ring point towards the atrium centre"""
    return -pol(1.0, a_deg)


# ---- round 26 fix 5: goods, menus and screen content ----
SIGNS4 = ("SignMagenta", "SignCyan", "SignAmber", "SignGreen")
WORDS = ("SALE", "NEW", "OPEN", "DEALS", "PLAY", "TOP 10", "HOT", "LIVE")


def screen_content(lt, c, right, normal, w, h, seed=0):
    """bars, a block and a word on a screen plane (c = screen centre, just in front of it)"""
    right, normal = Vector(right).normalized(), Vector(normal).normalized()
    up = normal.cross(right).normalized()
    if up.z < 0:
        up = -up
    c = Vector(c) + normal * 0.012
    for k in range(3):
        L = w * (0.35 + 0.4 * hsh(seed, k))
        y = h * (0.22 - 0.16 * k)
        o = c - right * (w * 0.42) + up * y
        quad(lt, [o, o + right * L, o + right * L + up * h * 0.07, o + up * h * 0.07], normal, SIGNS4[(seed + k) % 4])
    b = c + right * (w * 0.22) - up * (h * 0.3)
    quad(lt, [b, b + right * w * 0.18, b + right * w * 0.18 + up * h * 0.22, b + up * h * 0.22], normal, SIGNS4[(seed + 3) % 4])
    word = WORDS[seed % len(WORDS)]
    sign_text(lt, word, c - right * (w * 0.2) - up * (h * 0.22), right, h * 0.16, "WindowCream", normal, depth=0.004)


def menu_board(p, lt, c, right, normal, w=1.2, h=0.8, seed=0):
    right, normal = Vector(right).normalized(), Vector(normal).normalized()
    up = normal.cross(right).normalized()
    if up.z < 0:
        up = -up
    c = Vector(c)
    quad(p, [c - right * w / 2 - up * h / 2, c + right * w / 2 - up * h / 2, c + right * w / 2 + up * h / 2,
             c - right * w / 2 + up * h / 2], normal, "Palette:#1c2026")
    sign_text(lt, "MENU", c + normal * 0.01 + up * (h * 0.34), right, h * 0.12, "SignAmber", normal, depth=0.006)
    for k in range(5):
        y = h * (0.16 - 0.1 * k)
        L = w * (0.35 + 0.25 * hsh(seed, k))
        o = c + normal * 0.012 - right * (w * 0.42) + up * y
        quad(lt, [o, o + right * L, o + right * L + up * 0.025, o + up * 0.025], normal, "WindowCream")
        q = c + normal * 0.012 + right * (w * 0.34) + up * y
        quad(lt, [q, q + right * 0.08, q + right * 0.08 + up * 0.03, q + up * 0.03], normal, "SignAmber")


def cups(p, c, n=4, seed=0):
    c = Vector(c)
    for k in range(n):
        q = c + Vector((0.14 * (k - n / 2), 0.05 * (k % 2), 0))
        p.cyl(q, q + Vector((0, 0, 0.1)), 0.04, 0.045, seg=6, mat=("Palette:#e6e3dc", "Palette:#e07a3a", "Palette:#2c3036")[(k + seed) % 3],
              cap1=False)
