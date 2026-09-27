"""Set glTF import parameters in assets/models/*.glb.import (the files ART-HAB owns; astronaut_* excluded).

Run: python tools/blender/glb_import_params.py key=value [key=value ...] [--only prefix1,prefix2] [--dry]
Example: python tools/blender/glb_import_params.py meshes/generate_lods=false meshes/create_shadow_meshes=false
Then: node tools/godot.mjs import (Godot re-imports the changed files)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "models")


def main():
    argv = sys.argv[1:]
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    dry = "--dry" in argv
    sets = [a.split("=", 1) for a in argv if "=" in a and not a.startswith("--")]
    changed = 0
    for f in sorted(os.listdir(MODELS)):
        if not f.endswith(".glb.import") or f.startswith("astronaut_"):
            continue
        if only and not f.startswith(tuple(only)):
            continue
        p = os.path.join(MODELS, f)
        s = open(p, encoding="utf-8").read()
        s0 = s
        for k, v in sets:
            pat = re.compile(r"^%s=.*$" % re.escape(k), re.M)
            if pat.search(s):
                s = pat.sub("%s=%s" % (k, v), s)
            else:
                s = s.replace("[params]\n", "[params]\n\n%s=%s\n" % (k, v), 1)
        if s != s0:
            changed += 1
            if not dry:
                with open(p, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(s)
    print("glb_import_params: %d files %s" % (changed, "(dry run)" if dry else "changed"))


main()
