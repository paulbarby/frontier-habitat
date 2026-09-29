"""
Frontier Habitat 5.0 - ART-B: a test sheet of every sign string used in the super dome (critic round 28 fix 1).
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_signs_test.py
Writes art/dome/sign_test_sheet.png (front view, emissive letters on dark plates).
"""
import bpy
import os
import sys
import re

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_render as R          # noqa: E402
import dome_common as D         # noqa: E402
import dome_floors as F         # noqa: E402
import dome_l2                  # noqa: E402
import vehicle_common as VC     # noqa: E402
from mathutils import Vector    # noqa: E402

EXTRA = ["PRISM SHIFT", "ADULTS ONLY", "MENU", "TO LET", "SAT-1", "LP-01", "MR-02", "HP-03", "RV-01", "TR-07",
         "SH-12", "LN-03", "MD-21", "SC-09", "CR-01"] + list(D.WORDS)


def main():
    texts = []
    for v in F.L1_VENUES + dome_l2.L2_VENUES:
        texts.append((v[1], v[4]))
    for t in EXTRA:
        texts.append((t, "SignAmber"))
    missing = sorted({ch for t, _ in texts for ch in t if ch != " " and ch not in D.SC.GLYPHS})
    print("GLYPHS MISSING:", missing or "none")
    R.setup_scene(1800, 1400, transparent=False, world_rgb=(0.05, 0.05, 0.07), ground=None, sun_energy=0.5)
    p = VC.Node("Signs")
    cols = 3
    for k, (t, mat) in enumerate(texts):
        x = (k % cols) * 6.0
        y = -(k // cols) * 1.0
        D.sign_text(p, t, Vector((x, 0.0, y)), Vector((1, 0, 0)), 0.5, mat, Vector((0, -1, 0)), depth=0.04,
                    plate="Palette:#1c2026", pad=0.12)
    ob = VC.node_obj(p, D.DomeMatSet("#e07a3a"))
    D.flat_ao(ob)
    D.SC.apply_palette(ob)
    R.ao_materials()
    cd = bpy.data.cameras.new("C")
    cd.type = "ORTHO"
    rows = (len(texts) + cols - 1) // cols
    cd.ortho_scale = max(18.5, rows * 1.0 * 1800 / 1400 + 1)
    co = bpy.data.objects.new("C", cd)
    bpy.context.scene.collection.objects.link(co)
    co.location = (6.0, -20.0, -(rows - 1) / 2.0)
    co.rotation_euler = (1.5708, 0, 0)
    bpy.context.scene.camera = co
    R.render_to(os.path.join(D.ART_DIR, "sign_test_sheet.png"))


if __name__ == "__main__":
    main()
