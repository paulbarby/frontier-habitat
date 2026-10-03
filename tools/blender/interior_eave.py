"""Frontier Habitat 5.0 - ART-HAB: the raised eave (Paul 2026-10-03, doorway head room in the follow view).

Paul: "walking into corridors, the habitat's roof section is so low it overlaps the door entries, so you have beams
at every door entrance."  His choice: raise the roof and ceiling so every beam, rib, band and ring sits above the
door frames (door opening top 2.24 m + 0.25 m), all round the room.

Dome and setback shells met the wall at WALL_TOP (1.40 m): the dome ring, the seal ring and the setback ledge crossed
every door opening.  raise(rm), called after the room builder and before the ceiling pass, inserts a vertical drum
from the wall top to EAVE (2.60 m) at the wall radius and moves the whole roof up by LIFT = EAVE - WALL_TOP:
  - Roof and L2..L5: every vertex at or above CUT (1.30 m) moves up (the dome keeps its shape; things standing on it
    move with it; anything that crosses the cut stretches);
  - Interior, Tall_*, Lights and the other parts: a vertex moves up only when it touches the old roof from below
    (a cord, a column top: within TOUCH under it, above 1.80 m) or stands on top of it (a beacon, a mast);
  - anchors the same way; rm.H, rm.top_z, rm.D (setback), rm.crown_z and rm.lift follow, so rm.dome_z() and
    rm.headroom() give the new roof.
The drum skin (and its ribs) lies at the wall line between 1.40 m and EAVE: interior_kit.split_decals moves it to
the Upper_<seg> objects (WallsUp), which the game hides at a doorway like the podium drum wall; the build report gives
upper_z = (1.40, EAVE + 0.05), so the game uses the flat door kit with its upper patch.
The airlock keeps its chamber block: inside the block footprint only the block top moves (the block stretches).
"""
from math import hypot
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import rooms_kit as K
from rooms_kit import WALL_TOP, reg_angles, RZ, T

EAVE = 2.60                 # the lattice domes' base ring is 8 cm under the eave: 2.52 > 2.49
LIFT = EAVE - WALL_TOP
CUT = 1.30
TOUCH = 0.10
SHELLS = ("dome", "setback")


def _bvh(part):
    o = part.origin
    vs = [Vector(v) + o for v in part.verts]
    if not part.faces:
        return None
    return BVHTree.FromPolygons(vs, [list(f) for f in part.faces], all_triangles=False)


def _moves(bvh, p):
    """True when world point p touches the old roof from below or stands on it."""
    if p.z < CUT:
        return False
    up = bvh.ray_cast(p - Vector((0, 0, 0.005)), Vector((0, 0, 1)), 60.0)
    if up[0] is not None:
        return p.z >= 1.80 and up[3] <= TOUCH + 0.005
    dn = bvh.ray_cast(p + Vector((0, 0, 0.005)), Vector((0, 0, -1)), 60.0)
    return dn[0] is not None


def _block(rm):
    """The airlock chamber block footprint (x0, hw, zt) or None."""
    return getattr(rm, "airlock_block", None)


def raise_eave(rm):
    if getattr(rm, "lift", 0.0) or getattr(rm, "shell", None) not in SHELLS or not getattr(rm, "v3", False):
        return 0.0
    blk = _block(rm)
    old = _bvh(rm.roof)
    # 1. roof shell and level parts: a rigid lift above the cut
    for part in [rm.roof] + [rm.L[n] for n in (2, 3, 4, 5)]:
        o = part.origin
        for i, v in enumerate(part.verts):
            w = v + o
            if blk and part is rm.roof and i >= blk["v1"]:
                continue                     # the airlock's chamber walls and inner door tops (Roof) stay
            if blk and part is rm.roof and blk["v0"] <= i < blk["v1"] and i not in blk["fair"]:
                t = (w.z - blk["z0"]) / max(0.05, blk["z1"] - blk["z0"])      # the block: bottom stays, top moves
                v.z += LIFT * max(0.0, min(1.0, t))
            elif w.z >= CUT:
                v.z += LIFT
    # 2. everything else: what hangs from the roof or stands on it
    moved = 0
    if old is not None:
        skip = {id(rm.roof), id(rm.base)} | {id(rm.L[n]) for n in (2, 3, 4, 5)} | {id(w) for w in rm.walls}
        others = [rm.interior, rm.lights] + list(getattr(rm, "extra_parts", []))
        for part in others:
            if id(part) in skip or not part.verts:
                continue
            o = part.origin
            for v in part.verts:
                if _moves(old, v + o):
                    v.z += LIFT
                    moved += 1
        anc = []
        for a in rm.anchors:
            pos = Vector(a[1])
            if _moves(old, pos):
                pos.z += LIFT
            anc.append((a[0], tuple(pos)) + tuple(a[2:]))
        rm.anchors = anc
    # 3. the drum skin and its ribs (Roof; split_decals moves them to Upper_<seg>)
    Rw = rm.Rw
    r = rm.roof
    n0 = len(r.faces)
    r.lathe_a([(Rw, WALL_TOP - 0.02), (Rw, EAVE + 0.02)], reg_angles(rm.seg), "Hull", smooth=False)
    nrib = (8, 12, 16, 20)[min(3, rm.size)]
    for k in range(nrib):
        with r.at(RZ(360.0 * (k + 0.5) / nrib), T(Rw, 0, 0)):
            r.box0(0.02, 0, WALL_TOP, 0.08, 0.14, LIFT, "Frame", mats={"-z": None, "-x": None, "+z": None})
    cut = getattr(rm, "airlock_cut", None)
    if cut:
        keep = list(range(n0))
        for i in range(n0, len(r.faces)):
            vs = [r.verts[j] + r.origin for j in r.faces[i]]
            cx, cy = sum(q.x for q in vs) / len(vs), sum(q.y for q in vs) / len(vs)
            if not (cx > cut[0] + 0.10 and abs(cy) < cut[1] + 0.02):
                keep.append(i)
        r.faces = [r.faces[i] for i in keep]
        r.fmat = [r.fmat[i] for i in keep]
        r.fsmooth = [r.fsmooth[i] for i in keep]
    # 4. the room's numbers
    rm.lift = LIFT
    rm.eave = EAVE
    if rm.H is not None:
        rm.H += LIFT
    rm.top_z += LIFT
    if rm.shell == "setback" and getattr(rm, "D", None):
        rm.D += LIFT
    if getattr(rm, "crown_z", None) is not None:
        rm.crown_z += LIFT
    rm.rooms_hi = [(fn, z + LIFT if z > WALL_TOP else z) for fn, z in rm.rooms_hi]
    rm.eave_moved = moved
    return LIFT
