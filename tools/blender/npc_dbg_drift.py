import bpy, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import npc_common as N
import npc_verify as NV
from mathutils import kdtree
argv = sys.argv[sys.argv.index("--") + 1:]
variant, kind, clip, frame = argv[0], argv[1], argv[2], int(argv[3])
rig, body, others = NV.import_rig(NV.model_path(variant))
vis = [o for o in NV.attach_visitors(rig, variant) if o.name.split(".")[0] == "Vis_" + kind]
bodies = [body] + [o for o in others if o.name.startswith("Head_0")]
dg = bpy.context.evaluated_depsgraph_get()
ad = rig.animation_data
ad.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
rest_b = np.concatenate([NV.mesh_world(b, dg) for b in bodies])
def top_bone(ob):
    W = NV.group_weights(ob); names = sorted(W)
    M = np.stack([W[n] for n in names], axis=1)
    return np.array(names)[M.argmax(axis=1)]
tb = np.concatenate([top_bone(b) for b in bodies])
trees = {}
for bn in set(tb.tolist()):
    ids = np.where(tb == bn)[0]
    kd = kdtree.KDTree(len(ids))
    for i in ids: kd.insert(rest_b[i], int(i))
    kd.balance(); trees[bn] = kd
o = vis[0]
rv = NV.mesh_world(o, dg); vb = top_bone(o)
idx = np.array([(trees[b] if b in trees else trees["chest"]).find(q)[1] for q, b in zip(rv, vb)])
d0 = np.linalg.norm(rv - rest_b[idx], axis=1)
act = NV.action_for(clip); ad.action = act
if act.slots: ad.action_slot = act.slots[0]
for f in ([frame - 3, frame, frame + 3] if frame > 3 else [frame]):
    bpy.context.scene.frame_set(f)
    cb = np.concatenate([NV.mesh_world(b, dg) for b in bodies])
    co = NV.mesh_world(o, dg)
    dd = np.abs(np.linalg.norm(co - cb[idx], axis=1) - d0)
    order = np.argsort(-dd)[:5]
    print("DRIFT f%d max %.4f" % (f, dd.max()))
    for i in order:
        print("   v%d drift %.4f d0 %.3f attach_bone %s body_bone %s rest %s" % (i, dd[i], d0[i], vb[i], tb[idx[i]], tuple(round(float(x), 3) for x in rv[i])))
