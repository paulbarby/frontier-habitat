"""debug: the vertices inside the bed box in a clip, with dominant bones.  -- BODY CLIP [outfit]"""
import bpy, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import npc_common as N
import people_verify as PV
argv = sys.argv[sys.argv.index("--") + 1:]
body, clip = argv[0], argv[1]
outfit = argv[2] if len(argv) > 2 else "casual_a"
rig, meshes = PV.import_person(body)
ob = meshes["Outfit_" + outfit]
names = {g.index: g.name for g in ob.vertex_groups}
top = np.array([names.get(max(v.groups, key=lambda g: g.weight).group, "?") if v.groups else "?" for v in ob.data.vertices])
bz, bb = (0.45 if clip == "sleep_cell" else 0.55), 0.55
act = next(a for a in bpy.data.actions if a.name.split("_Rig")[0] == clip)
n = int(round(act.frame_range[1]))
for f in range(0, n + 1, 3):
    PV.set_clip(rig, clip, f)
    co = PV.world_co(ob)
    m1 = np.all((co > np.array((-bb - 0.47, -1.0, bz - 0.15))) & (co < np.array((-bb + 0.30, 1.0, bz - 0.015))), axis=1)
    m2 = np.all((co > np.array((-bb - 0.39, -0.92, 0.0))) & (co < np.array((-bb + 0.39, 0.92, bz - 0.15))), axis=1)
    m = m1 | m2
    if m.any():
        from collections import Counter
        c = Counter(top[m].tolist()).most_common(3)
        zs = co[m][:, 2]
        print("BED %s f%d: %d verts, lowest %.3f, bones %s, mean pos %s" % (clip, f, m.sum(), zs.min(), c, tuple(round(float(x), 2) for x in co[m].mean(axis=0))))
