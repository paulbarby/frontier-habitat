"""debug: lowest vertices of a body in a clip frame, with their dominant bones.  -- BODY CLIP FRAME [xlo xhi ylo yhi]"""
import bpy, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import npc_common as N
import people_mpfb as PM
import people_verify as PV
argv = sys.argv[sys.argv.index("--") + 1:]
body, clip, frame = argv[0], argv[1], int(argv[2])
box = [float(x) for x in argv[3:7]] if len(argv) >= 7 else None
path = os.path.join(N.MODEL_DIR, ("astronaut_%s.glb" % body) if body in ("suit", "indoor") else ("people_%s.glb" % body))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = N.FPS
bpy.ops.import_scene.gltf(filepath=path)
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for tr in list((rig.animation_data or rig.animation_data_create()).nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
PV.set_clip(rig, clip, frame)
obs = [o for o in bpy.data.objects if o.type == "MESH"]
rows = []
for ob in [o for o in obs if o.vertex_groups]:
    if body not in ("suit", "indoor") and not (ob.name.startswith("Outfit_" + os.environ.get("OUTFIT", "casual_a")) or ob.name.startswith("Head_") or ob.name.startswith("Hair_")):
        continue
    co = PV.world_co(ob)
    names = {g.index: g.name for g in ob.vertex_groups}
    for i, v in enumerate(ob.data.vertices):
        p = co[i]
        if box and not (box[0] <= p[0] <= box[1] and box[2] <= p[1] <= box[3]):
            continue
        g = names.get(max(v.groups, key=lambda g: g.weight).group, "?") if v.groups else "?"
        rows.append((float(p[2]), ob.name, g, tuple(round(float(x), 3) for x in p)))
rows.sort()
per = {}
for z, on, g, p in rows:
    if g not in per or z < per[g][0]:
        per[g] = (z, p)
print("PERBONE " + "  ".join("%s %.3f" % (g, v[0]) for g, v in sorted(per.items(), key=lambda kv: kv[1][0])[:14]))
for r in rows[:12]:
    print("LOW %.3f %s %s %s" % r)
