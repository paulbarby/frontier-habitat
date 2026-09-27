"""
Frontier Habitat 4.0 - ART-B: check the ART-NPC crew clips against a vehicle GLB (Blender 5.2, --background only).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_fit.py -- --id rover_small

For each seat: drive_sit / ride_sit on Seat_<i>; board / alight (or the _r mirrors, from the anchor's `clip` extra)
on Anchor_Board_<i>. Measures
  - hand error: distance from prop.L / prop.R (the grip centre, ART-NPC) to Anchor_Grip_1/2 (driver) and to
    Anchor_Grab_<i> (the nearer hand), at every 10th frame of the sit clips;
  - body through the vehicle: deformed suit vertices that lie inside a vehicle mesh (closest-point normal test,
    deeper than 1 cm), at every 5th frame.
Writes art/vehicles/<id>_fit.json and prints a summary.
"""
import bpy
import os
import sys
import json
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vehicle_common as V      # noqa: E402
import vehicle_render as VR     # noqa: E402

SUIT = os.path.join(V.MODEL_DIR, "astronaut_suit.glb")


OWNER = []


def vehicle_bvh(objs):
    verts, polys = [], []
    OWNER.clear()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        n = VR.base(o)
        if n in ("Lights", "Cargo"):
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        off = len(verts)
        verts += [mw @ v.co for v in me.vertices]
        polys += [[off + i for i in p.vertices] for p in me.polygons]
        OWNER.extend([n] * len(me.polygons))
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def suit_points(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:                    # skinned meshes only (the importer adds a bone-shape Icosphere)
        if o.type != "MESH" or not any(m.type == "ARMATURE" for m in o.modifiers):
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def inside(bvh, pts, depth=0.01):
    bad, worst, where = 0, 0.0, None
    for p in pts:
        loc, nrm, idx, d = bvh.find_nearest(p, 0.25)
        if loc is None:
            continue
        s = (p - loc).dot(nrm)
        if s < -depth and -s >= 0.8 * d:          # face-interior hits only (an edge normal gives false hits)
            bad += 1
            if -s > worst:
                worst, where = -s, (OWNER[idx], [round(c, 2) for c in p], [round(c, 2) for c in loc], [round(c, 2) for c in nrm])
    return bad, worst, where


def seg_dist(p, c, half=0.10):
    """distance from p to a vertical handle axis through c (+- half)"""
    z = min(max(p.z, c.z - half), c.z + half)
    return (p - Vector((c.x, c.y, z))).length


def frames_of(act):
    a, b = act.frame_range
    return int(a), int(b)


def check(vid):
    VR.day((64, 64))
    vobjs, by = VR.load_vehicle(vid, gate=1.0, cargo=False)
    bvh = vehicle_bvh(vobjs)
    res = {}
    seats = sorted(n for n in by if n.startswith("Seat_"))
    for sn in seats:
        i = sn.split("_")[1]
        seat = by[sn]
        role = seat.get("role", "passenger")
        clip = "drive_sit" if role == "driver" else "ride_sit"
        jobs = [(clip, seat.matrix_world.copy())]
        bd = by.get("Anchor_Board_" + i)
        if bd is not None:
            bc = bd.get("clip", "board")
            jobs += [(bc, bd.matrix_world.copy()), (bc.replace("board", "alight"), bd.matrix_world.copy())]
        for clip_name, M in jobs:
            objs = VR.colonist(M, clip_name, 0)
            rig = next(o for o in objs if o.type == "ARMATURE")
            act = rig.animation_data.action
            f0, f1 = frames_of(act)
            row = dict(frames=[f0, f1], through=[], hands=[])
            for f in range(f0, f1 + 1, 5):
                bpy.context.scene.frame_set(f)
                bpy.context.view_layer.update()
                n, w, wh = inside(bvh, suit_points(objs))
                row["through"].append([f, n, round(w, 3), wh])
                if clip_name.startswith(("board", "alight")):
                    gb = by.get("Anchor_Grab_" + i)
                    if gb is not None:
                        g = gb.matrix_world.translation
                        pl = rig.matrix_world @ rig.pose.bones["prop.L"].head
                        pr = rig.matrix_world @ rig.pose.bones["prop.R"].head
                        row["hands"].append([f, {"err_grab": round(min(seg_dist(pl, g), seg_dist(pr, g)), 3),
                                                 "prop.L": [round(c, 3) for c in pl], "prop.R": [round(c, 3) for c in pr]}])
                if clip_name in ("drive_sit", "ride_sit") and (f - f0) % 10 == 0:
                    pl = rig.matrix_world @ rig.pose.bones["prop.L"].head
                    pr = rig.matrix_world @ rig.pose.bones["prop.R"].head
                    h = {"prop.L": [round(c, 3) for c in pl], "prop.R": [round(c, 3) for c in pr]}
                    if clip_name == "drive_sit":
                        g1 = by["Anchor_Grip_1"].matrix_world.translation      # driver's left handle
                        g2 = by["Anchor_Grip_2"].matrix_world.translation
                        h["err_L_grip1"] = round(seg_dist(pl, g1, 0.09), 3)
                        h["err_R_grip2"] = round(seg_dist(pr, g2, 0.09), 3)
                    gb = by.get("Anchor_Grab_" + i)
                    if gb is not None:
                        g = gb.matrix_world.translation
                        h["err_grab"] = round(min(seg_dist(pl, g), seg_dist(pr, g)), 3)
                    row["hands"].append([f, h])
            res["%s %s" % (sn, clip_name)] = row
            for o in objs:
                bpy.data.objects.remove(o, do_unlink=True)
    out = os.path.join(V.ART_DIR, "%s_fit.json" % vid)
    json.dump(res, open(out, "w", encoding="utf-8"), indent=1)
    for k, row in res.items():
        thr = max((t[1] for t in row["through"]), default=0)
        worst = max((t[2] for t in row["through"]), default=0)
        hs = row["hands"]
        he = ""
        if hs:
            keys = [kk for kk in hs[0][1] if kk.startswith("err")]
            he = "  " + "  ".join("%s max %.3f" % (kk, max(h[1][kk] for h in hs)) for kk in keys)
        wh = max(row["through"], key=lambda t: t[2])[3] if row["through"] else None
        he = he.replace("err_grab max", "err_grab min %.3f max" % min(h[1]["err_grab"] for h in hs)) if hs and "err_grab" in hs[0][1] else he
        print("FIT %-28s frames %s  through: max %d verts, depth %.3f at %s%s" % (k, row["frames"], thr, worst, wh, he))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    check(argv[argv.index("--id") + 1] if "--id" in argv else "rover_small")
