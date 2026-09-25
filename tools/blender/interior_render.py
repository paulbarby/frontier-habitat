"""
Frontier Habitat 3.0 - ART-HAB interior renders (Blender 5.2, --background only).

Renders top-down 3/4 cutaway pictures of the EXPORTED files (what the game receives) to art/interiors/:
  <id>_<size>.png              roof and L2..L5 hidden, no corridors, day light
  <id>_<size>_night.png        the same at night (interior lamps only + moon)
  <id>_<size>_doorways.png     two corridors at odd angles: segments hidden, wall patches, doorways, corridor stubs
  <id>_<size>_doorways_roof.png  the same with the roof on (how the doorway meets the dome and the corridor)
  <id>_<size>_anchors.png      stand-in figures on every anchor (bed, seat, stand, aisle) seen from above
  doorway_close.png            one doorway close up (cutaway and closed roof), leaves open

"Lit like the game" (presentation/fx_sky.gd): warm key light, warm ambient (#d8c1aa), filmic tone map; the
Anchor_Light_* empties become warm point lights as RENDER is asked to do; emissive strips glow.

This script also shows RENDER the placement rule for doorways (function place_link).

Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/interior_render.py -- --file habitat_m [--links 38,197] [--only beauty,night,doorways,anchors,close]
"""
import bpy
import os
import sys
import math
from math import sin, cos, radians, degrees, asin, atan2, ceil, hypot
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K            # noqa: E402
import rooms_render as RR        # noqa: E402

OUT_DIR = os.path.join(K.ROOT, "art", "interiors")
SIZE = (1600, 1100)
SEG = 11.25
FRAME_HW = 1.10             # the jamb in the wall plane
UPPER_OVER_Z = 2.24          # round 12: the upper patch over the housing starts here
HIDE_HW = 1.76              # 3.1: the frame housing reaches 1.72: hide every segment it touches
PATCH_HW = 1.70             # 3.1: wall patches start 2 cm inside the housing edge
BAND_END_HW = 1.77          # 3.1 round 10: the band ends 5 cm before the housing (1.72), with a cap
GROUND = (0.50, 0.29, 0.16)


def view_transform(sc):
    for vt in ("Filmic", "AgX", "Standard"):
        try:
            sc.view_settings.view_transform = vt
            sc.view_settings.look = "None"
            return vt
        except Exception:
            continue


def setup(w, h, night=False, samples=64):
    RR.setup_scene(w, h, transparent=False, samples=samples, ground=GROUND,
                   world_rgb=(0.20, 0.23, 0.33) if night else (0.85, 0.76, 0.66),
                   sun_energy=0.12 if night else 3.4,
                   sun_dir=(-0.35, 0.55, 0.76) if night else (0.30, -0.55, 0.78))
    sc = bpy.context.scene
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.10 if night else 0.75
    sun = bpy.data.objects["Sun"]
    sun.data.color = (0.72, 0.78, 1.0) if night else (1.0, 0.93, 0.82)
    view_transform(sc)
    try:
        sc.eevee.use_shadows = True
    except Exception:
        pass
    return sc


def place(objs, M):
    for o in objs:
        o.matrix_world = M @ o.matrix_world


def import_at(name, M=Matrix.Identity(4), hide=()):
    path = os.path.join(K.MODEL_DIR, name + ".glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    place([o for o in objs if o.parent is None], M)
    for o in objs:
        base = o.name.split(".")[0]
        if base in hide or any(base.startswith(h) for h in hide if h.endswith("*")):
            o.hide_render = True
            o.hide_viewport = True
    return objs


def hide_match(objs, names):
    for o in objs:
        if o.name.split(".")[0] in names:
            o.hide_render = True
            o.hide_viewport = True


# the family accent light colour at the Anchor_Accent_* points (critic round 4; the same table is in the RENDER request)
ACCENT_COLOUR = {
    "lounge": "#f08fc0", "cantina": "#f08fc0",                    # comfort neon (the category colour)
    "greenhouse": "#ff8fd8", "fungus_farm": "#a78bfa", "algae_bioreactor": "#9cffb0", "kitchen": "#ffb070",
    "research_lab": "#7fe0ff", "research_assembler": "#8fb4ff", "bio_lab": "#9cffb0", "medical": "#bfe8ff",
    "habitat": "#ffc98a", "storehouse": "#ffb347", "cold_storage": "#bfe8ff",
    "oxygen_plant": "#5fe0ee", "water_recycler": "#5fc8ff", "atmo_processor": "#5fe0ee",
    "airlock": "#ffb347", "junction": "#c9d3e0",
}
ACCENT_DEFAULT = "#ffb347"                                       # industry: hazard amber


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def night_lighting(objs, R, ceiling_w=90.0, lamp_w=14.0, pool_w=None, tid=None, accent_w=80.0, spill_w=30.0):
    """The target night look for RENDER (critic round 2): dim moon ambient; ceiling lights at the Anchor_Light_*
    points (about 4,800 K, range 3.5 m); warm lamp pools at the Anchor_Lamp_* points (about 3,100 K); one warm
    floor pool (#FFE8C8, radius 0.8 R); the cove and skirting strips light their surroundings (EEVEE ray tracing)."""
    sc = bpy.context.scene
    for attr, val in (("use_raytracing", True), ("use_shadows", True)):
        try:
            setattr(sc.eevee, attr, val)
        except Exception:
            pass
    try:
        sc.eevee.ray_tracing_options.resolution_scale = "1"
    except Exception:
        pass
    n = 0
    for o in objs:
        if o.type != "EMPTY":
            continue
        nm = o.name.split(".")[0]
        if nm.startswith("Anchor_Light_"):
            ld = bpy.data.lights.new("L_" + nm, "POINT")
            ld.energy = ceiling_w
            ld.color = (1.0, 0.91, 0.82)
            ld.shadow_soft_size = 0.35
            try:
                ld.use_custom_distance = True
                ld.cutoff_distance = 3.2
            except Exception:
                pass
        elif nm.startswith("Anchor_Lamp_"):
            ld = bpy.data.lights.new("L_" + nm, "POINT")
            ld.energy = lamp_w
            ld.color = (1.0, 0.70, 0.42)
            ld.shadow_soft_size = 0.10
        elif nm.startswith("Anchor_Accent_"):
            ld = bpy.data.lights.new("L_" + nm, "POINT")
            ld.energy = accent_w
            ld.color = hex_rgb(ACCENT_COLOUR.get(tid, ACCENT_DEFAULT))
            ld.shadow_soft_size = 0.30
            try:
                ld.use_custom_distance = True
                ld.cutoff_distance = 3.0
            except Exception:
                pass
            # the visible floor spill: a coloured disk light 1.0 m above the floor, pointing down
            sd = bpy.data.lights.new("S_" + nm, "AREA")
            sd.shape = "DISK"
            sd.size = 1.8
            sd.energy = spill_w
            sd.color = ld.color
            so = bpy.data.objects.new("S_" + nm, sd)
            p_ = o.matrix_world.translation
            so.location = (p_.x, p_.y, 1.0)
            sc.collection.objects.link(so)
        else:
            continue
        lo = bpy.data.objects.new("L_" + nm, ld)
        lo.location = o.matrix_world.translation
        sc.collection.objects.link(lo)
        n += 1
    pr = 0.5 * R                      # the pool covers the middle; the wall ring falls off (about 25 % darker)
    ld = bpy.data.lights.new("FloorPool", "AREA")
    ld.shape = "DISK"
    ld.size = 2 * pr
    ld.energy = pool_w if pool_w is not None else 42.0 * pr * pr
    ld.color = (1.0, 0.91, 0.78)
    lo = bpy.data.objects.new("FloorPool", ld)
    lo.location = (0, 0, 3.2)
    sc.collection.objects.link(lo)
    return n


def lamps_from_anchors(objs, power=140.0, color=(1.0, 0.86, 0.70), radius=0.25):
    n = 0
    for o in objs:
        if o.type == "EMPTY" and o.name.startswith("Anchor_Light_"):
            ld = bpy.data.lights.new("L_" + o.name, "POINT")
            ld.energy = power
            ld.color = color
            ld.shadow_soft_size = radius
            lo = bpy.data.objects.new("L_" + o.name, ld)
            lo.location = o.matrix_world.translation
            bpy.context.scene.collection.objects.link(lo)
            n += 1
    return n


# --------------------------------------------------------------------------------------
# The doorway placement rule (the same numbers are in docs/requests/ART-HAB-to-RENDER.md)
# --------------------------------------------------------------------------------------
def link_plan(R, theta):
    """For a room of footprint radius R and a corridor at angle theta (deg, from +X toward +Y):
    returns dict(hide=[segment k], patches=[(a0, a1)], rw)."""
    Rw = R - 0.32
    phi = degrees(asin(min(0.99, HIDE_HW / Rw)))
    lo, hi = theta - phi, theta + phi
    ks = []
    k0 = int(math.floor(lo / SEG))
    k1 = int(math.floor(hi / SEG))
    for k in range(k0, k1 + 1):
        ks.append(k % 32)
    a0, a1 = k0 * SEG, (k1 + 1) * SEG
    phi_in = degrees(asin(min(0.99, PATCH_HW / Rw)))
    patches = []
    for (pa, pb) in ((a0, theta - phi_in), (theta + phi_in, a1)):
        span = pb - pa
        if span <= 0.01:
            continue
        chord = 2 * Rw * sin(radians(span / 2))
        n = max(1, int(ceil(chord / 0.45)))
        for j in range(n):
            patches.append((pa + span * j / n, pa + span * (j + 1) / n))
    return dict(hide=sorted(set(ks)), patches=patches, rw=Rw)


# --------------------------------------------------------------------------------------
# The junction rule (junction.glb only; no doorway.glb there): open spans, posts, sills, patches
# --------------------------------------------------------------------------------------
J_MOUTH_HW = 1.20           # half width of a mouth at the wall line (the corridor's outer wall is 1.18)
J_MERGE_GAP = 8.0           # two mouths closer than this (deg) become one open span
J_BISECT_MIN = 58.0         # a post stands between two links of one span only when they are this far apart
J_POST_HW = 0.12


def junction_plan(R, betas):
    """betas: model angles (deg) of the links.  Returns dict(rw, spans=[(s0, s1)], full, posts=[deg],
    hide=[k], patches=[(a0, a1)], sills=[(a0, a1)])."""
    Rw = R - 0.32
    h = degrees(asin(min(0.99, J_MOUTH_HW / Rw)))
    bs = sorted(b % 360.0 for b in betas)
    groups = []                                     # [[s0, s1, [betas]]]
    for b in bs:
        if groups and (b - h) - groups[-1][1] < J_MERGE_GAP:
            groups[-1][1] = b + h
            groups[-1][2].append(b)
        else:
            groups.append([b - h, b + h, [b]])
    if len(groups) > 1 and (groups[0][0] + 360.0) - groups[-1][1] < J_MERGE_GAP:
        g = groups.pop()
        groups[0] = [g[0] - 360.0, groups[0][1], [x - 360.0 for x in g[2]] + groups[0][2]]
    full = bool(groups) and (groups[0][1] - groups[0][0]) >= 360.0 - J_MERGE_GAP
    posts, hide, patches, sills = [], set(), [], []

    def pieces(pa, pb, out):
        span = pb - pa
        if span <= 0.01:
            return
        chord = 2 * Rw * sin(radians(span / 2))
        n = max(1, int(ceil(chord / 0.45)))
        for j in range(n):
            out.append((pa + span * j / n, pa + span * (j + 1) / n))
    if full:
        bb = groups[0][2]
        hide = set(range(32))
        for i in range(len(bb)):
            b0, b1 = bb[i], bb[(i + 1) % len(bb)] + (360.0 if i == len(bb) - 1 else 0.0)
            if b1 - b0 >= J_BISECT_MIN:
                posts.append(0.5 * (b0 + b1))
        pieces(0.0, 360.0, sills)
    else:
        for (s0, s1, bb) in groups:
            k0, k1 = int(math.floor(s0 / SEG)), int(math.floor((s1 - 1e-6) / SEG))
            for k in range(k0, k1 + 1):
                hide.add(k % 32)
            posts += [s0, s1]
            for i in range(len(bb) - 1):
                if bb[i + 1] - bb[i] >= J_BISECT_MIN:
                    posts.append(0.5 * (bb[i] + bb[i + 1]))
            pieces(k0 * SEG, s0, patches)
            pieces(s1, (k1 + 1) * SEG, patches)
            pieces(s0, s1, sills)
    return dict(rw=Rw, spans=[(g[0], g[1]) for g in groups], full=full, posts=posts, hide=sorted(hide),
                patches=patches, sills=sills)


def place_junction(R, betas, length=4.5, cutaway=True, accent=None):
    plan = junction_plan(R, betas)
    Rw = plan["rw"]

    def strip(name, pa, pb, r_face):
        span = pb - pa
        mid = 0.5 * (pa + pb)
        chord = 2 * Rw * sin(radians(span / 2)) + 0.01
        rr = r_face * cos(radians(span / 2))
        M = Matrix.Rotation(radians(mid), 4, "Z") @ Matrix.Translation((rr, 0, 0)) @ Matrix.Diagonal((1, chord, 1, 1))
        o = import_at(name, M)
        if accent:
            tint_accent(o, accent)
    for (pa, pb) in plan["patches"]:
        strip("wall_patch", pa, pb, Rw)
    for (pa, pb) in plan["sills"]:
        strip("junction_sill", pa, pb, Rw)
    for a in plan["posts"]:
        o = import_at("junction_post", Matrix.Rotation(radians(a), 4, "Z") @ Matrix.Translation((Rw, 0, 0)))
        if accent:
            tint_accent(o, accent)
    for th in betas:
        rot = Matrix.Rotation(radians(th), 4, "Z")
        start = R - 0.25
        Mc = rot @ Matrix.Translation((start + length / 2, 0, 0.05)) @ Matrix.Diagonal((length, 1, 1, 1))
        import_at("corridor", Mc, hide=("Roof",) if cutaway else ())
        for j in range(1, int(length // 2.5) + 1):
            x = start + 0.45 + 2.5 * j - 1.25
            if x > start + length - 0.2:
                break
            import_at("corridor_rib", rot @ Matrix.Translation((x, 0, 0.05)), hide=("Roof",) if cutaway else ())
    return plan


DOORWAY_RW = (2.50, 3.25, 4.00, 4.75, 5.50, 6.25, 7.00, 7.75, 8.50, 9.25)


def doorway_file(Rw, flat=False):
    """3.1: the doorway variant whose curved room face is nearest to this wall radius; the flat-lid variant for
    flat-roofed rooms (podium, drum, setback shells)."""
    rw = min(DOORWAY_RW, key=lambda q: abs(q - Rw))
    return ("doorway_flat_r%03d" if flat else "doorway_r%03d") % round(rw * 100)


def room_meta(file):
    """build_report.json -> models[id].v3.decals (upper_z, upper_band, shell, name_sign_deg)."""
    import json as _j
    try:
        for m in _j.load(open(os.path.join(HERE, "build_report.json"), encoding="utf-8"))["models"]:
            if m["id"] == file:
                return ((m.get("v3") or {}).get("decals") or {})
    except Exception:
        return {}
    return {}


DECAL_MARGIN = 0.40        # 3.1 section 3.3: decals hide over the door opening plus 0.4 m each side


def decal_hide(R, theta):
    """Segments whose decals meet the opening (half width 0.75) plus the margin, at the wall line."""
    Rw = R - 0.32
    phi = degrees(asin(min(0.99, (0.75 + DECAL_MARGIN) / Rw)))
    k0, k1 = int(math.floor((theta - phi) / SEG)), int(math.floor((theta + phi) / SEG))
    return sorted({k % 32 for k in range(k0, k1 + 1)})


def hide_prefix(objs, prefixes):
    for o in objs:
        if any(o.name.startswith(p) for p in prefixes):
            o.hide_render = True
            o.hide_viewport = True


def tint_accent(objs, rgb):
    for o in objs:
        if o.type != "MESH":
            continue
        for i, m in enumerate(o.data.materials):
            if m is not None and m.name.split(".")[0] == "Accent":
                mm = m.copy()
                bsdf = next((nd for nd in mm.node_tree.nodes if nd.bl_idname == "ShaderNodeBsdfPrincipled"), None)
                if bsdf is not None:
                    src = bsdf.inputs["Base Color"]
                    if src.is_linked:
                        # the importer multiplies COLOR_0 into Base Color: tint the constant input of that mix
                        node = src.links[0].from_node
                        for inp in node.inputs:
                            if inp.type == "RGBA" and not inp.is_linked:
                                inp.default_value = (*rgb, 1.0)
                                break
                    else:
                        src.default_value = (*rgb, 1.0)
                o.data.materials[i] = mm


def place_link(R, theta, length=4.5, cutaway=True, open_doors=False, accent=None, upper_z=None, flat_roof=False,
               upper_band=None):
    """Room centre at the origin.  Doorway, patches, corridor stub and ribs for one link."""
    plan = link_plan(R, theta)
    Rw = plan["rw"]
    rot = Matrix.Rotation(radians(theta), 4, "Z")
    Md = rot @ Matrix.Translation((Rw, 0, 0))
    hide_d = ("FrameTop", "DoorLTop", "DoorRTop", "Sign", "Status") if cutaway else ()
    d_objs = import_at(doorway_file(Rw, flat=bool(upper_z) or flat_roof), Md, hide=hide_d)
    if accent:
        tint_accent(d_objs, accent)
    if open_doors:
        t = 1.0 if open_doors is True else float(open_doors)      # 0 closed .. 1 open (0.75 m per leaf)
        for o in d_objs:
            b = o.name.split(".")[0]
            if b in ("DoorL", "DoorLTop"):
                o.matrix_world = o.matrix_world @ Matrix.Translation((0, -0.75 * t, 0))
            if b in ("DoorR", "DoorRTop"):
                o.matrix_world = o.matrix_world @ Matrix.Translation((0, 0.75 * t, 0))
    phi_b = degrees(asin(min(0.99, BAND_END_HW / Rw)))
    for (pa, pb) in plan["patches"]:
        # 3.1: the band ends 5 cm before the housing: a plain slice there, a cap at the band's end
        pieces = []
        for (a0, a1) in ((pa, pb),):
            lo_, hi_ = theta - phi_b, theta + phi_b
            if a1 <= lo_ or a0 >= hi_:
                pieces.append((a0, a1, "wall_patch"))
            else:
                if a0 < lo_:
                    pieces.append((a0, lo_, "wall_patch"))
                pieces.append((max(a0, lo_), min(a1, hi_), "wall_patch_plain"))
                if a1 > hi_:
                    pieces.append((hi_, a1, "wall_patch"))
        for (a0, a1, fname) in pieces:
            span = a1 - a0
            if span <= 1e-3:
                continue
            mid = 0.5 * (a0 + a1)
            chord = 2 * Rw * sin(radians(span / 2)) + 0.01
            rr = Rw * cos(radians(span / 2))
            M = Matrix.Rotation(radians(mid), 4, "Z") @ Matrix.Translation((rr, 0, 0)) @ Matrix.Diagonal((1, chord, 1, 1))
            po = import_at(fname, M)
            if accent:
                tint_accent(po, accent)
    for sgn in (-1, 1):
        a = theta + sgn * phi_b
        import_at("band_cap", Matrix.Rotation(radians(a), 4, "Z") @ Matrix.Translation((Rw, 0, 0)))
    if upper_z:
        # flat-walled rooms: the upper wall beside the housing (1.40 .. deck) and over it (housing top .. deck)
        z0, z1 = upper_z
        spans = [(pa, pb, z0) for (pa, pb) in plan["patches"]]
        phi_h = degrees(asin(min(0.99, PATCH_HW / Rw)))
        if z1 > UPPER_OVER_Z:
            # round 12: from 2.24 m (the housing's rounded top corners start at 2.26), so no gap shows beside the
            # corners; inside the housing the patch is hidden by the housing and its flat lid
            spans.append((theta - phi_h, theta + phi_h, UPPER_OVER_Z))
        for (pa, pb, zb) in spans:
            span = pb - pa
            mid = 0.5 * (pa + pb)
            chord = 2 * Rw * sin(radians(span / 2)) + 0.01
            rr = Rw * cos(radians(span / 2))
            M = (Matrix.Rotation(radians(mid), 4, "Z") @ Matrix.Translation((rr, 0, zb)) @
                 Matrix.Diagonal((1, chord, max(0.01, z1 - zb), 1)))
            po = import_at("wall_patch_upper", M)
            if accent:
                tint_accent(po, accent)
        if upper_band:
            # the upper band carried over the patch spans to a cap 5 cm before the housing
            b0, b1 = upper_band
            for (pa, pb) in plan["patches"]:
                for (a0, a1) in ((pa, min(pb, theta - phi_b)), (max(pa, theta + phi_b), pb)):
                    if a1 - a0 <= 1e-3:
                        continue
                    span = a1 - a0
                    mid = 0.5 * (a0 + a1)
                    chord = 2 * Rw * sin(radians(span / 2)) + 0.01
                    rr = Rw * cos(radians(span / 2))
                    M = (Matrix.Rotation(radians(mid), 4, "Z") @ Matrix.Translation((rr, 0, b0)) @
                         Matrix.Diagonal((1, chord, b1 - b0, 1)))
                    po = import_at("upper_band", M)
                    if accent:
                        tint_accent(po, accent)
            for sgn in (-1, 1):
                a = theta + sgn * phi_b
                import_at("band_cap", Matrix.Rotation(radians(a), 4, "Z") @
                          Matrix.Translation((Rw, 0, 0.5 * (b0 + b1) - 1.03)))
    # corridor: the game draws it from the room radius R to the far room, 0.25 m longer at each end
    start = R - 0.25
    Mc = rot @ Matrix.Translation((start + length / 2, 0, 0.05)) @ Matrix.Diagonal((length, 1, 1, 1))
    import_at("corridor", Mc, hide=("Roof",) if cutaway else ())
    nrib = int(length // 2.5)
    for j in range(1, nrib + 1):
        x = start + 0.45 + 2.5 * j - 1.25
        if x > start + length - 0.2:
            break
        import_at("corridor_rib", rot @ Matrix.Translation((x, 0, 0.05)), hide=("Roof",) if cutaway else ())
    return plan


# --------------------------------------------------------------------------------------
# Stand-in figures on the anchors
# --------------------------------------------------------------------------------------
def fig_material():
    m = bpy.data.materials.get("FigMat") or RR.flat_material("FigMat", (0.20, 0.85, 1.0), rough=0.5)
    return m


def capsule_obj(name, p0, p1, r, mat):
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r, depth=max(0.01, L), location=(p0 + p1) / 2)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = (p1 - p0).to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(mat)
    for q in (p0, p1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=r, location=q)
        s = bpy.context.active_object
        s.data.materials.append(mat)
    return o


def figures(objs, F=K.FLOOR_Z, work_sit=False):
    mat = fig_material()
    n = 0
    for o in objs:
        if o.type != "EMPTY" or not o.name.startswith("Anchor_"):
            continue
        name = o.name.split(".")[0]
        mw = o.matrix_world
        pos = mw.translation
        X = (mw.to_3x3() @ Vector((1, 0, 0))).normalized()
        Y = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
        Z = Vector((0, 0, 1))
        if name.startswith("Anchor_Work_") and work_sit:
            name = "Anchor_Seat_w"
        elif name.startswith("Anchor_Work_"):
            name = "Anchor_Stand_w"
        if name.startswith("Anchor_Stand_"):
            capsule_obj(name + "_fig", pos + Z * 0.25, pos + Z * 1.52, 0.17, mat)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.13, location=pos + Z * 1.68 + X * 0.03)
            bpy.context.active_object.data.materials.append(mat)
            capsule_obj(name + "_nose", pos + Z * 1.68, pos + Z * 1.68 + X * 0.2, 0.04, mat)
        elif name.startswith("Anchor_Seat_"):
            hip = pos - X * 0.30 + Z * (0.46 + 0.10)
            capsule_obj(name + "_torso", hip, hip + Z * 0.55, 0.16, mat)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.13, location=hip + Z * 0.72)
            bpy.context.active_object.data.materials.append(mat)
            knee = hip + X * 0.45
            capsule_obj(name + "_thigh", hip, knee, 0.08, mat)
            capsule_obj(name + "_shin", knee, knee - Z * 0.45 + X * 0.04, 0.06, mat)
        elif name.startswith("Anchor_Bed_"):
            c = pos - X * 0.55 + Z * (0.55 + 0.12)
            capsule_obj(name + "_body", c - Y * 0.80, c + Y * 0.45, 0.16, mat)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.13, location=c + Y * 0.72 + Z * 0.02)
            bpy.context.active_object.data.materials.append(mat)
            # the stand point marker (where lie_enter starts)
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.14, depth=0.01, location=pos + Z * 0.01)
            bpy.context.active_object.data.materials.append(mat)
        elif name.startswith("Anchor_Aisle_"):
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.10, depth=0.02, location=pos + Z * 0.012)
            bpy.context.active_object.data.materials.append(mat)
        else:
            continue
        n += 1
    return n


# --------------------------------------------------------------------------------------
# Shots
# --------------------------------------------------------------------------------------
def room_points(R, extra=(), top=1.4):
    pts = [Vector((R * cos(radians(a)), R * sin(radians(a)), 0.0)) for a in range(0, 360, 15)]
    pts += [Vector((R * cos(radians(a)), R * sin(radians(a)), 1.4)) for a in range(0, 360, 15)]
    if top > 1.5:
        pts += [Vector((0, 0, top))]
    pts += [Vector(p) for p in extra]
    return pts


def shot_room(file, R, out, night=False, links=(), cutaway=True, figs=False, size=(1600, 1100), elevation=56.0,
              azimuth=-42.0, margin=1.04, open_doors=False, focus=None, samples=64, lamps=True, top_z=None,
              hide_extra=(), marker_z=None):
    setup(size[0], size[1], night=night, samples=samples)
    if marker_z is not None:
        bpy.ops.mesh.primitive_torus_add(major_radius=R + 0.12, minor_radius=0.025, location=(0.0, 0.0, marker_z),
                                         major_segments=96, minor_segments=6)
        ring = bpy.context.active_object
        ring.name = "HeightMarker"
        mk = bpy.data.materials.new("HeightMarker")
        mk.use_nodes = True
        bsdf = mk.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (1.0, 0.04, 0.04, 1.0)
        for key, val in (("Emission Color", (1.0, 0.04, 0.04, 1.0)), ("Emission Strength", 2.0)):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = val
        ring.data.materials.append(mk)
    hide = K.LEVELS + (("Roof",) if cutaway else ()) + tuple(hide_extra)
    objs = import_at(file, hide=hide)
    extra = []
    acc = None
    try:
        import build_assets as BA
        tid = file.rsplit("_", 1)[0] if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else file
        acc = BA.hex_to_linear(K.ACCENTS[K.load_buildings().get(tid, {}).get("category", "logistics")])
    except Exception:
        acc = None
    if file == "junction" and links:
        plan = place_junction(R, links, cutaway=cutaway, accent=acc)
        hide_match(objs, {"Wall_%02d" % k for k in plan["hide"]})
        extra += [Vector(((R + 2.0) * cos(radians(th)), (R + 2.0) * sin(radians(th)), 0.0)) for th in links]
        links = ()
    for th in links:
        meta = room_meta(file)
        plan = place_link(R, th, cutaway=cutaway, open_doors=open_doors, accent=acc,
                          upper_z=None if cutaway else meta.get("upper_z"),
                          flat_roof=meta.get("shell") in ("podium", "drum", "setback"),
                          upper_band=None if cutaway else meta.get("upper_band"))
        hide_match(objs, {"Wall_%02d" % k for k in plan["hide"]} | {"Upper_%02d" % k for k in plan["hide"]})
        hide_prefix(objs, ["Decal_%02d_" % k for k in decal_hide(R, th)])
        extra.append(Vector(((R + 2.6) * cos(radians(th)), (R + 2.6) * sin(radians(th)), 0.0)))
    # 3.1 decals follow their source object: Decal_<seg>_L3 shows with L3, Decal_<seg>_Roof with the roof
    for o in objs:
        nm = o.name.split(".")[0]
        if nm.startswith("Decal_") and nm.rsplit("_", 1)[-1] in hide:
            o.hide_render = True
            o.hide_viewport = True
        if nm.startswith("Upper_") and "Roof" in hide:
            o.hide_render = True
            o.hide_viewport = True
    if cutaway:
        # 3.1: every "...Top" object (door housings and leaves above the wall top) lifts with the roof
        for o in objs:
            nm_ = o.name.split(".")[0]
            if nm_.endswith(("Top", "Status")) or nm_.startswith(("PressureLight_", "Beacon")):
                o.hide_render = True
                o.hide_viewport = True
    if open_doors:
        # the airlock's own doors (InnerDoor*, OuterDoor*): open along their local Y (their frame is the room frame)
        t = 1.0 if open_doors is True else float(open_doors)
        for o in objs:
            nm = o.name.split(".")[0]
            if nm.startswith(("InnerDoorL", "OuterDoorL")):
                o.matrix_world = Matrix.Translation((0, -0.75 * t, 0)) @ o.matrix_world
            if nm.startswith(("InnerDoorR", "OuterDoorR")):
                o.matrix_world = Matrix.Translation((0, 0.75 * t, 0)) @ o.matrix_world
    # crops on the trays, as the game places them (crop origin at the soil surface, z 0.56)
    tid_ = file.rsplit("_", 1)[0] if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else file
    if tid_ in ("greenhouse", "fungus_farm"):
        bdef = K.load_buildings()[tid_]
        sz = K.SIZE_KEYS.index(file.rsplit("_", 1)[-1])
        crops = ("crop_potato", "crop_tomato", "crop_wheat", "crop_greens") if tid_ == "greenhouse" else ("crop_mushroom",)
        for k, (cx, cy) in enumerate(bdef["sizes"]["tray_offsets"][sz]):
            import_at(crops[k % len(crops)], Matrix.Translation((cx, cy, 0.56)), hide=("Stage1", "Stage2"))
    if lamps and night:
        night_lighting(objs, R, tid=file.rsplit("_", 1)[0] if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else file)
    elif lamps:
        lamps_from_anchors(objs, power=60.0)
    RR.ensure_ao()
    if figs:
        tid_f = file.rsplit("_", 1)[0] if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else file
        fu = K.load_buildings().get(tid_f, {}).get("furniture", {})
        figures(objs, work_sit=fu.get("work_pose") == "sit")
    bpy.context.view_layer.update()
    if focus is not None:
        pts = [Vector(p) for p in focus]
    else:
        pts = room_points(R, extra, top=1.4 if cutaway else 4.8)
        if not cutaway:
            pts += [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" and not o.hide_render
                    for c in o.bound_box]
    RR.place_camera(pts, azimuth=azimuth, elevation=elevation, margin=margin, aspect=size[0] / size[1], focal=50.0)
    RR.render_to(out)
    print("  wrote", out)
    return out


def sheet(files, out, label=True):
    rows = [[(f, os.path.join(OUT_DIR, f + ".png")) for f in files]]
    RR.compose(rows, out, label_h=26 if label else 4)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--sheet" in argv:
        files = argv[argv.index("--sheet") + 1].split(",")
        sheet(files, argv[argv.index("--out") + 1])
        return
    file = argv[argv.index("--file") + 1] if "--file" in argv else "habitat_m"
    links = [float(x) for x in argv[argv.index("--links") + 1].split(",")] if "--links" in argv else [38.0, 197.0]
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else ["beauty", "night", "doorways", "roof",
                                                                             "anchors", "close", "detail"]
    global SIZE
    if "--size" in argv:
        SIZE = tuple(int(v) for v in argv[argv.index("--size") + 1].split("x"))
    tid = file.rsplit("_", 1)[0] if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else file
    size = K.SIZE_KEYS.index(file.rsplit("_", 1)[-1]) if file.rsplit("_", 1)[-1] in K.SIZE_KEYS else 1
    b = K.load_buildings().get(tid, {})
    R = float(b.get("sizes", {}).get("radius", [b.get("radius", 5.5)] * 4)[size]) if b.get("sizes") else float(b.get("radius", 5.5))
    if file == "airlock_r28":
        R = 2.8                      # old-save airlock (rooms_build.AIRLOCK_R_OLD)
    os.makedirs(OUT_DIR, exist_ok=True)
    base = os.path.join(OUT_DIR, file)
    if "jtest" in only:
        # junction door kit at the tightest spacing SIM allows (balance.json link_min_angle_deg) and evenly spread
        import json as _json
        mn = float(_json.load(open(os.path.join(K.ROOT, "content", "balance.json"), encoding="utf-8"))["link_min_angle_deg"])
        sets = [("3", [0.0, mn, 2 * mn]), ("4", [0.0, mn, 2 * mn, 3 * mn]), ("5", [mn * k for k in range(5)]),
                ("6", [mn * k for k in range(6)]), ("6even", [60.0 * k + 15.0 for k in range(6)]),
                ("4even", [90.0 * k + 20.0 for k in range(4)])]
        names = []
        for tag, bet in sets:
            bet = [b_ + 200.0 for b_ in bet] if not tag.endswith("even") else bet
            for roof in (False, True):
                nm = "junction_links_%s%s" % (tag, "_roof" if roof else "")
                shot_room(file, R, os.path.join(OUT_DIR, nm + ".png"), links=bet, cutaway=not roof, size=(1000, 760),
                          elevation=50.0 if not roof else 36.0, lamps=not roof, margin=1.02)
                names.append(nm)
        return
    if "beauty" in only:
        shot_room(file, R, base + ".png", size=SIZE)
    if "exterior" in only:
        # the building as the game shows it with the roof on (L2..L5 hidden), day light
        shot_room(file, R, base + "_exterior.png", cutaway=False, size=SIZE, elevation=40.0, azimuth=-38.0,
                  lamps=False, margin=1.06)
    if "night" in only:
        shot_room(file, R, base + "_night.png", night=True)
    if "doorways" in only:
        shot_room(file, R, base + "_doorways.png", links=links)
    if "roof" in only:
        shot_room(file, R, base + "_doorways_roof.png", links=links, cutaway=False, elevation=38.0, lamps=False,
                  margin=1.12)
    if "anchors" in only:
        shot_room(file, R, base + "_anchors.png", figs=True, elevation=72.0, azimuth=-90.0, lamps=True)
    if "detail" in only:
        # a close look at one bed, its bedside unit and the wall behind it
        th = 22.5
        c = Vector((3.4 * cos(radians(th)), 3.4 * sin(radians(th)), 0))
        focus = [c + Vector((dx, dy, dz)) for dx in (-1.6, 1.6) for dy in (-1.6, 1.6) for dz in (0.0, 1.4)]
        shot_room(file, R, base + "_detail.png", size=(1400, 900), elevation=40.0, azimuth=th + 180.0 + 30.0,
                  focus=focus, margin=1.0)
    if "cutproof" in only:
        # round 12: the cutaway from the side at eye level, a red ring at WALL_TOP 1.40 m round the room: nothing of
        # the cutaway may stand above the ring
        Rw = R - 0.32
        focus = [Vector((x, y, z)) for x in (-R, R) for y in (-R, R) for z in (0.0, 3.2)]
        for az in (-90.0, -30.0):
            shot_room(file, R, base + "_cut_side%s.png" % ("" if az == -90.0 else "_b"), size=(1400, 760),
                      elevation=5.0, azimuth=az, focus=focus, margin=1.02, lamps=True, marker_z=K.WALL_TOP)
    if "plights" in only:
        # round 12: the pressure lights (8 cm lamps on a dark plate) over the inner door, roof off, full height
        foc = [Vector((x, y, z)) for x in (-1.6, 0.9) for y in (-1.3, 1.3) for z in (1.4, 2.9)]
        shot_room(file, R, base + "_pressure_lights.png", cutaway=False, hide_extra=("Roof",), size=(1200, 800),
                  elevation=18.0, azimuth=180.0 + 25.0, focus=foc, margin=1.0)
    if "airlock31" in only:
        for tag, t in (("closed", 0.0), ("half", 0.5), ("open", 1.0)):
            shot_room(file, R, os.path.join(OUT_DIR, "airlock_%s.png" % tag), open_doors=t or None, size=(1200, 860),
                      elevation=52.0, azimuth=-60.0)
            shot_room(file, R, os.path.join(OUT_DIR, "airlock_%s_roof.png" % tag), open_doors=t or None,
                      cutaway=False, size=(1200, 860), elevation=24.0, azimuth=-25.0, lamps=False, margin=1.02)
        shot_room(file, R, os.path.join(OUT_DIR, "airlock_links.png"), links=links, size=(1200, 860), elevation=50.0,
                  azimuth=-60.0)
        shot_room(file, R, os.path.join(OUT_DIR, "airlock_links_roof.png"), links=links, cutaway=False,
                  size=(1200, 860), elevation=30.0, azimuth=150.0, lamps=False, margin=1.02)
    if "door31" in only:
        # 3.1 door kit: closed, half-open, open; cutaway and roof on
        th = links[0]
        Rw = R - 0.32
        c = Vector((Rw * cos(radians(th)), Rw * sin(radians(th)), 0))
        focus = [c + Vector((dx, dy, dz)) for dx in (-1.9, 1.9) for dy in (-1.9, 1.9) for dz in (0.0, 2.7)]
        for tag, t in (("closed", 0.0), ("half", 0.5), ("open", 1.0)):
            shot_room(file, R, os.path.join(OUT_DIR, "door31_%s.png" % tag), links=[th], open_doors=t or None,
                      size=(1200, 860), elevation=34.0, azimuth=th + 180.0 - 35.0, focus=focus, margin=1.0)
            shot_room(file, R, os.path.join(OUT_DIR, "door31_%s_roof.png" % tag), links=[th], open_doors=t or None,
                      cutaway=False, size=(1200, 860), elevation=22.0, azimuth=th - 38.0, focus=focus, margin=1.0,
                      lamps=False)
            shot_room(file, R, os.path.join(OUT_DIR, "door31_%s_inside.png" % tag), links=[th], open_doors=t or None,
                      cutaway=False, size=(1200, 860), elevation=16.0, azimuth=th + 180.0 + 12.0,
                      focus=[c + Vector((dx, dy, dz)) for dx in (-2.8, 0.3) for dy in (-1.9, 1.9) for dz in (0.0, 2.6)],
                      margin=1.0, lamps=False, hide_extra=("Roof",))
    if "close" in only:
        th = links[0]
        Rw = R - 0.32
        c = Vector((Rw * cos(radians(th)), Rw * sin(radians(th)), 0))
        focus = [c + Vector((dx, dy, dz)) for dx in (-1.8, 1.8) for dy in (-1.8, 1.8) for dz in (0.0, 2.5)]
        shot_room(file, R, os.path.join(OUT_DIR, "doorway_close.png"), links=[th], open_doors=True, size=(1400, 900),
                  elevation=34.0, azimuth=th + 180.0 - 35.0, focus=focus, margin=1.0)
        shot_room(file, R, os.path.join(OUT_DIR, "doorway_close_roof.png"), links=[th], cutaway=False, size=(1400, 900),
                  elevation=24.0, azimuth=th - 40.0, focus=focus, margin=1.0, lamps=False)
        shot_room(file, R, os.path.join(OUT_DIR, "doorway_close_inside.png"), links=[th], cutaway=True, size=(1400, 900),
                  elevation=30.0, azimuth=th + 180.0 + 20.0, focus=[c + Vector((dx, dy, dz)) for dx in (-2.6, 0.4)
                                                                   for dy in (-1.8, 1.8) for dz in (0.0, 1.6)],
                  margin=1.0)


if __name__ == "__main__":
    main()
