"""
Frontier Habitat 5.0 - ART-NPC: frame strips of clips as the player sees them (the follow camera: 1.9 m behind the
right shoulder at eye height, RENDER camera_rig.gd sh_dist) plus a side view.  One import per body, many frames: fast.

  blender --background --factory-startup --python tools/blender/npc_strip.py -- --body m1 --outfit casual_a \
      --clips run,walk --frames 8 --views follow,side [--out art/people/strip_run.png] [--size 240x340]

Bodies: suit, indoor (astronaut files) or m1..f3, c1, c2 (people files).  Furniture props as people_render.
"""
import bpy
import os
import sys
import json
from math import radians
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
_ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--body" in _ARGV and _ARGV[_ARGV.index("--body") + 1] not in ("suit", "indoor"):
    import people_mpfb             # noqa: E402,F401  (people skeleton: face + expression bones, before any solver)
import npc_render as NR         # noqa: E402
import people_render as PR      # noqa: E402

# view: (azimuth deg (0 = in front, +X), elevation deg, distance m, target height share of the body, lens)
VIEWS = {
    "follow": (195.0, 14.0, 2.6, 0.62, 50.0),     # behind the right shoulder (game: 1.9 m behind the eye + FOV 70)
    "side": (-90.0, 6.0, 3.6, 0.52, 70.0),        # the body's right side: lean, arm swing, foot contact
    "front": (-30.0, 8.0, 3.4, 0.55, 70.0),
    "high": (-35.0, 42.0, 3.2, 0.45, 50.0),       # the room camera (Paul's crate shot)
    "low": (-90.0, 2.0, 3.4, 0.20, 70.0),         # feet at ground level: contact and float
    "back_close": (200.0, 18.0, 1.5, 0.74, 60.0),  # shoulders, neck and upper back (skinning)
    "front_close": (-25.0, 10.0, 1.5, 0.74, 60.0),
}


def load(body, outfit):
    if body in ("suit", "indoor"):
        rig, objs = NR.import_astronaut(os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % body))
        if body == "indoor":
            # one head only (Head_0..3 overlap otherwise)
            for o in objs:
                nm = o.name.split(".")[0]
                if nm.startswith("Head_") and nm != "Head_0":
                    bpy.data.objects.remove(o)
        return rig, 1.0
    rig, _ = PR.import_person(body, outfit)
    return rig, PR.manifest()["variants"][body]["scale"]


def rebake(rig, body, s, clips):
    """Bake `clips` again from the CURRENT source onto the imported rig (preview of a change without the 1-2 min
    build): people get the build's contact calibration on the imported meshes.  The new action replaces the old."""
    import people_anims as PA
    import npc_anims as A
    solver = N.Solver()
    solver.set_rest_from_rig(rig)
    if body in ("suit", "indoor"):
        table = {c[0]: (c[6], c[5]) for c in A.all_clips()}
        fix = None
        wrap = (lambda fn, name: fn)
    else:
        import people_mpfb as PM
        meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name.split(".")[0].startswith(("Outfit_", "Head_", "Hair_"))]
        outfit = next(o for o in meshes if o.name.startswith("Outfit_"))
        head = next(o for o in meshes if o.name.startswith("Head_"))
        hair = next(o for o in meshes if o.name.startswith("Hair_"))
        PA.FOOT_DZ = rig.data.bones["foot.L"].head_local.z - N.ANKLE_JOINT.z * s
        PA.ARM_IN = 5.0 if PM.VARIANTS[body]["macro"]["weight"] < 0.58 else 0.0
        PA.LID_REST = PM.VARIANTS[body].get("lid_rest", 5.0)
        PM.calibrate_contacts(rig, solver, s, [outfit, head, hair], [outfit])
        table = {c[0]: (c[6], c[5]) for c in PA.people_clips()}
        reach = {sd: (solver.head["forearm." + sd] - solver.head["upper_arm." + sd]).length +
                 (solver.head["hand." + sd] - solver.head["forearm." + sd]).length for sd in ("L", "R")}

        def fix(P):
            _, _, pos, _ = solver.solve(P)
            for sd in ("L", "R"):
                if P.g("arm.%s.ik" % sd) <= 0 or P.g("arm.%s.chest" % sd) > 0:
                    continue
                sh = pos["upper_arm." + sd]
                t = Vector((P.g("arm.%s.x" % sd), P.g("arm.%s.y" % sd), P.g("arm.%s.z" % sd)))
                d = t - sh
                if d.length > PM.REACH_MAX * reach[sd]:
                    t = sh + d.normalized() * PM.REACH_MAX * reach[sd]
                    P["arm.%s.x" % sd], P["arm.%s.y" % sd], P["arm.%s.z" % sd] = t.x, t.y, t.z
            return P
        wrap = (lambda fn, name: (lambda f: PA.retarget(fn(f), s, name)))
    for c in clips:
        old = NR.action_for(c)
        if old is not None:
            old.name = "old_" + c
        fn, n = table[c]
        N.bake_clip(rig, solver, c, wrap(fn, c), n, fix=fix)
    ad = rig.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    N.reset_pose(rig)


def frames_of(clip):
    a = NR.action_for(clip)
    lo, hi = a.frame_range
    return int(lo), int(hi)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(k, d=None):
        return argv[argv.index(k) + 1] if k in argv else d
    body = arg("--body", "m1")
    outfit = arg("--outfit", "casual_a")
    clips = arg("--clips", "walk").split(",")
    nfr = int(arg("--frames", "8"))
    views = arg("--views", "follow,side").split(",")
    w, h = (int(x) for x in arg("--size", "240x340").split("x"))
    explicit = arg("--at")               # clip:f1/f2/f3 explicit frames
    out = arg("--out") or os.path.join(PR.ART, "_tmp", "strip_%s_%s.png" % (body, "_".join(clips)))
    PR.tmpdir()
    rows = []
    poses = arg("--poses")              # clip:frame,clip:frame,...  one row per view, no furniture
    if poses:
        NR.setup(w, h, ground=(0.46, 0.44, 0.42), samples=16)
        rig, s = load(body, outfit)
        pl = [(p.split(":")[0], int(p.split(":")[1])) for p in poses.split(",")]
        if "--rebake" in argv:
            rebake(rig, body, s, sorted(set(c for c, _ in pl)))
        for v in views:
            az, el, dist, th, lens = VIEWS[v]
            row = []
            for clip, f in pl:
                NR.set_clip(rig, clip, f)
                ch = rig.matrix_world @ rig.pose.bones["neck"].head
                hips = rig.matrix_world @ rig.pose.bones["hips"].head
                tgt = Vector((ch.x, ch.y, ch.z - 0.12 * s)) if v.endswith("_close") else \
                    Vector((hips.x, hips.y, max(0.45, 1.80 * s * th)))
                NR.clear_cameras()
                NR.camera(tuple(tgt), az, el, dist * max(0.8, s), lens=lens)
                p = os.path.join(PR.TMP, "sp_%s_%s_%s_%d.png" % (body, clip, v, f))
                row.append(("%s %s f%d %s" % (body, clip, f, v), NR.render(p)))
            rows.append(row)
        NR.compose(rows, out, title="%s (%s): poses" % (body, outfit))
        print("STRIP", out)
        return
    for clip in clips:
        NR.setup(w, h, ground=(0.46, 0.44, 0.42), samples=16)
        NR.add_grid(step=0.25, half=3.0)
        if clip in PR.FURNITURE_PROPS:
            PR.FURNITURE_PROPS[clip]()
        if clip in ("sit_bar_stool", "drink_bar"):
            PR.stool_props()
        rig, s = load(body, outfit)
        if "--rebake" in argv:
            rebake(rig, body, s, [clip])
        lo, hi = frames_of(clip)
        if explicit and explicit.startswith(clip + ":"):
            fl = [int(x) for x in explicit.split(":")[1].split("/")]
        else:
            fl = [int(round(lo + (hi - lo) * k / max(1, nfr - 1))) for k in range(nfr)]
        for v in views:
            az, el, dist, th, lens = VIEWS[v]
            row = []
            for f in fl:
                NR.set_clip(rig, clip, f)
                hips = rig.matrix_world @ rig.pose.bones["hips"].head
                tgt = Vector((hips.x, hips.y, 1.80 * s * th)) if v != "low" else Vector((hips.x, hips.y, 0.35))
                if v.endswith("_close"):
                    ch = rig.matrix_world @ rig.pose.bones["neck"].head
                    tgt = Vector((ch.x, ch.y, ch.z - 0.12 * s))
                if clip in PR.LOW_CLIPS and v in ("side", "front", "follow"):
                    tgt.z = max(0.45, hips.z)
                NR.clear_cameras()
                NR.camera(tuple(tgt), az, el, dist * max(0.8, s), lens=lens)
                p = os.path.join(PR.TMP, "st_%s_%s_%s_%d.png" % (body, clip, v, f))
                row.append(("%s %s %s f%d" % (body, clip, v, f), NR.render(p)))
            rows.append(row)
    NR.compose(rows, out, title="%s (%s): %s - follow = 1.9 m behind the right shoulder" % (body, outfit, ", ".join(clips)))
    print("STRIP", out)


if __name__ == "__main__":
    main()
