"""Showcase build of the role props (scratch use, ART-HAB): an empty storehouse L whose 32 wall slots show the kinds
named in FH_ROLE_SHOW (comma list, cycled).  Run with FH_MODEL_DIR / FH_REPORT_DIR / FH_ART_DIR pointing at a
scratch folder, then render with interior_render.py --only props (see docs/progress/ART-HAB.md)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_build as RB          # noqa: E402
import interior_rooms as IR       # noqa: E402
import interior_kit as IK         # noqa: E402


def show_interior(rm):
    plan = IK.Plan(rm, clear=0.65)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.30, radial=16, edge_band=0.64, inner_disc=1.25)
    kinds = [s for s in os.environ.get("FH_ROLE_SHOW", "panel").split(",") if s]
    plan.wall_items(kinds, IR.wall_set(plan), open_every=0, seed=3, depth_of=IR.DEPTHS, open_kinds=(None,))
    plan.anchor("Stand", 0.0, 0.0, 0.0)


IR.INTERIORS[os.environ.get("FH_SHOW_TID", "storehouse")] = show_interior
sys.argv += [] if "--" in sys.argv else ["--"]
sys.argv += ["--only", os.environ.get("FH_SHOW_TID", "storehouse"), "--sizes", os.environ.get("FH_SHOW_SIZE", "l"),
             "--no-thumbs", "--no-verify"]
RB.main()
