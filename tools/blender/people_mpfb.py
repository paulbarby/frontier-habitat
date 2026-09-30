"""
Frontier Habitat 5.0 - ART-NPC: people bodies from MPFB (MakeHuman for Blender), ROUTE A: the MPFB body is skinned to
OUR skeleton (v3 + jaw + lids), so every clip and RENDER's code stay as they are.  Blender --background only.

  # 1. find out what the installed MPFB offers (API, data folders, asset names) - read-only
  blender --background --factory-startup --python tools/blender/people_mpfb.py -- --probe --data D:/Tools/mpfb/data
  # 2. build variants
  blender --background --factory-startup --python tools/blender/people_mpfb.py -- --data D:/Tools/mpfb/data \
      --variants m1,f1

STATUS 2026-09-30: written BEFORE MPFB was installed.  Every MPFB call goes through class Mpfb (one place to fix);
the API names follow MPFB 2.0 (HumanService / TargetService) from its documentation and source as I know them, NOT
checked against 2.0.17.  Run --probe first.  Asset names are glob patterns until --probe lists the real files.

Pipeline per variant:
  1. MPFB human from macro values (gender, age, muscle, weight, height, proportions, race mix); MakeHuman's
     "default" rig with its weights (it has jaw and eyelid bones; "game_engine" is the fallback).
  2. CC0 assets: skin (mhmat), eyes, eyebrows, eyelashes, teeth, hair; the garments of every outfit (mhclo), each with
     its body delete mask recorded.
  3. Turn the human to our axes (MakeHuman faces -Y; we face +X, left = +Y); delete helper geometry.
  4. Pose the MPFB rig so the arms and legs lie along OUR bind directions (arms 30 deg from vertical), apply the pose
     to every mesh (the vertex groups stay).
  5. Our rig: bone heads at the MPFB joints (mapped), bone directions from the v3 bind, jaw and lids at the face.
  6. Weights: every MPFB group goes to its mapped v3 bone (unmapped groups go to the nearest mapped ancestor);
     <= 4 influences, normalised.
  7. Meshes (the draw rule does not change): Head_<v> = eyes + brows + lashes + teeth;
     Hair_<v>; Outfit_<id> = the body minus that outfit's delete masks + its garments.  Decimated to the budget.
  8. Materials rebuilt as plain Principled + image textures (the glTF exporter cannot read MPFB's node groups):
     Skin (a detail map the tone tint multiplies), Hair (alpha), Eye, Teeth, one material per garment.
     Textures <= 1024 px (budget: faces up to 1024 px per variant).
  9. Clips baked with people_anims (retarget by height), exported as people_<v>.glb; people_manifest.json updated.
"""
import bpy
import os
import sys
import glob
import json
import math
import time
import fnmatch
import importlib
import inspect
from mathutils import Vector, Matrix, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C          # noqa: E402
import npc_common as N          # noqa: E402
import people_face as PF        # noqa: E402
import people_uniform as PU     # noqa: E402
N.extend_skeleton(PF.FACE_BONES)
# expression bones (MPFB people only; placed per body in joints_ours): brows, mouth corners, lower lids
EXPR_BONES = [("brow.L", "head", (0.09, 0.03, 1.69), (0.12, 0.03, 1.70)),
              ("brow.R", "head", (0.09, -0.03, 1.69), (0.12, -0.03, 1.70)),
              ("mouth.L", "head", (0.07, 0.02, 1.60), (0.10, 0.02, 1.60)),
              ("mouth.R", "head", (0.07, -0.02, 1.60), (0.10, -0.02, 1.60)),
              ("lids_low", "head", (0.08, 0.0, 1.66), (0.11, 0.0, 1.66))]
N.extend_skeleton(EXPR_BONES)

OUT_TEX = os.path.join(N.MODEL_DIR, "people_tex")
BUDGET = dict(lod0=24000, body=8000, garments=7000, hair=3600, head=1500, tex=1024)

# ------------------------------------------------------------------------------------------------------------------
# variants: MakeHuman macro values (0..1).  age: 0.1875 = 11 years, 0.5 = 25, 1.0 = 90.  Heights are exact (the body is
# scaled to them after the macros).  race = african / asian / caucasian (sums to 1).
# ------------------------------------------------------------------------------------------------------------------
VARIANTS = {
    "m1": dict(sex="m", height=1.80, macro=dict(gender=1.0, age=0.50, muscle=0.60, weight=0.50, proportions=0.60,
                                                race=(0.10, 0.10, 0.80)),
               skin="skins/young_caucasian_male", hair="hair/short02", brows="eyebrows/eyebrow008",
               eye_mat="eyes/materials/brown.mhmat"),
    "m2": dict(sex="m", height=1.76, macro=dict(gender=1.0, age=0.62, muscle=0.45, weight=0.65, proportions=0.50,
                                                race=(0.80, 0.05, 0.15)),
               skin="skins/middleage_african_male", hair="hair/short04", brows="eyebrows/eyebrow009",
               eye_mat="eyes/materials/brown.mhmat"),
    "m3": dict(sex="m", height=1.90, macro=dict(gender=1.0, age=0.76, muscle=0.40, weight=0.55, proportions=0.55,
                                                race=(0.05, 0.75, 0.20)),
               skin="skins/middleage_asian_male", hair="hair/short01", brows="eyebrows/eyebrow004",
               eye_mat="eyes/materials/brownlight.mhmat"),
    "f1": dict(sex="f", height=1.68, macro=dict(gender=0.0, age=0.50, muscle=0.50, weight=0.45, proportions=0.60,
                                                race=(0.10, 0.10, 0.80)),
               skin="skins/young_caucasian_female", hair="hair/toigo_curled_under_bob", brows="eyebrows/eyebrow010",
               eye_mat="eyes/materials/green.mhmat"),
    "f2": dict(sex="f", height=1.62, macro=dict(gender=0.0, age=0.60, muscle=0.55, weight=0.60, proportions=0.50,
                                                race=(0.75, 0.05, 0.20)),
               skin="skins/middleage_african_female", hair="hair/afro01", brows="eyebrows/eyebrow003",
               eye_mat="eyes/materials/brown.mhmat"),
    "f3": dict(sex="f", height=1.74, macro=dict(gender=0.0, age=0.70, muscle=0.40, weight=0.50, proportions=0.55,
                                                race=(0.05, 0.75, 0.20)),
               skin="skins/middleage_asian_female", hair="hair/ponytail01", brows="eyebrows/eyebrow010",
               eye_mat="eyes/materials/brownlight.mhmat"),
    "c1": dict(sex="m", height=1.38, child=True, macro=dict(gender=1.0, age=0.17, muscle=0.50, weight=0.50,
                                                             proportions=0.50, race=(0.20, 0.20, 0.60)),
               skin="skins/young_caucasian_male", hair="hair/short03", brows="eyebrows/eyebrow005",
               eye_mat="eyes/materials/green.mhmat"),
    "c2": dict(sex="f", height=1.34, child=True, macro=dict(gender=0.0, age=0.16, muscle=0.50, weight=0.45,
                                                             proportions=0.50, race=(0.30, 0.30, 0.40)),
               skin="skins/young_african_female", hair="hair/ponytail01", brows="eyebrows/eyebrow011",
               eye_mat="eyes/materials/brown.mhmat"),
}
PILOT = ["m1", "f1"]
FACE = dict(eyes="eyes/low-poly", eyelashes="eyelashes/eyelashes01", teeth="teeth/teeth_base")

# outfits per sex: garment folders (CC0) and the material each garment gets.  "tint:<Name>" = our contract material
# with the garment texture as a detail map (SuitAccent = department colour, Coverall = uniform grey, ClothTint =
# per-person colour); "own" = the garment's own texture, not tinted.
OUTFITS = {
    # the contract uniform: our coverall (people_uniform.py) + MPFB boots; department looks = base colour + add-ons
    "uniform": dict(generator="coverall", who=["all roles on shift"], look="see people_uniform.DEPARTMENTS",
                    m=[("clothes/toigo_ankle_boots_male", "own")], f=[("clothes/toigo_ankle_boots_male", "own")]),
    "casual_a": dict(
        who=["off duty"],
        look="tee in the person's colour (over the waistband), dark cargo trousers, sneakers",
        m=[("clothes/toigo_basic_tucked_t-shirt", "tint:ClothTint"), ("clothes/cortu_cargo_pants", "own"),
           ("clothes/shoes06", "own")],
        f=[("clothes/toigo_basic_tucked_t-shirt", "tint:ClothTint"), ("clothes/cortu_cargo_pants", "own"),
           ("clothes/shoes05", "own")]),
}
PILOT_OUTFITS = ["uniform", "casual_a"]
TINT_BASE = {"SuitAccent": (1.0, 1.0, 1.0), "Coverall": (0.34, 0.38, 0.43), "ClothTint": (1.0, 1.0, 1.0)}

# MPFB bone -> v3 bone.  First match wins; the "default" rig first, then "game_engine".  Unmapped bones give their
# weights to the nearest mapped ancestor.  S = side placeholder (L/R and l/r).
BONE_MAP = [
    # default rig (MakeHuman 1.x names)
    ("root", "root"), ("pelvis.S", "hips"), ("spine05", "hips"), ("spine04", "spine"), ("spine03", "spine"),
    ("spine02", "chest"), ("spine01", "chest"), ("neck01", "neck"), ("neck02", "neck"), ("neck03", "head"),
    ("head", "head"), ("jaw", "jaw"), ("tongue*", "jaw"), ("orbicularis03.S", "lids"),
    ("orbicularis04.S", "lids_low"), ("oculi0*.S", "brow.S"), ("oris07.S", "mouth.S"), ("levator05.S", "mouth.S"),
    ("risorius0*.S", "mouth.S"),
    ("clavicle.S", "shoulder.S"), ("shoulder01.S", "shoulder.S"), ("upperarm0*.S", "upper_arm.S"),
    ("lowerarm0*.S", "forearm.S"), ("wrist.S", "hand.S"), ("metacarpal*.S", "hand.S"), ("finger*.S", "hand.S"),
    ("upperleg0*.S", "thigh.S"), ("lowerleg0*.S", "shin.S"), ("foot.S", "foot.S"), ("toe*.S", "toe.S"),
    # game_engine rig
    ("pelvis", "hips"), ("spine_01", "spine"), ("spine_02", "chest"), ("spine_03", "chest"), ("neck_01", "neck"),
    ("clavicle_S", "shoulder.S"), ("upperarm_S", "upper_arm.S"), ("upperarm_twist*_S", "upper_arm.S"),
    ("lowerarm_S", "forearm.S"), ("lowerarm_twist*_S", "forearm.S"), ("hand_S", "hand.S"), ("thumb*_S", "hand.S"),
    ("index*_S", "hand.S"), ("middle*_S", "hand.S"), ("ring*_S", "hand.S"), ("pinky*_S", "hand.S"),
    ("thigh_S", "thigh.S"), ("thigh_twist*_S", "thigh.S"), ("calf_S", "shin.S"), ("calf_twist*_S", "shin.S"),
    ("foot_S", "foot.S"), ("ball_S", "toe.S"),
]
# the MPFB joint that places each v3 bone head (candidates in order)
JOINTS = {
    "hips": ["pelvis.L|pelvis", "@mid"], "spine": ["spine04", "spine_01"], "chest": ["spine02", "spine_02"],
    "neck": ["neck01", "neck_01"], "head": ["head"], "jaw": ["jaw"],
    "shoulder.S": ["clavicle.S", "clavicle_S"], "upper_arm.S": ["upperarm01.S", "upperarm_S"],
    "forearm.S": ["lowerarm01.S", "lowerarm_S"], "hand.S": ["wrist.S", "hand_S"],
    "thigh.S": ["upperleg01.S", "thigh_S"], "shin.S": ["lowerleg01.S", "calf_S"], "foot.S": ["foot.S", "foot_S"],
    "toe.S": ["toe1-1.S|toe*.S", "ball_S"],
}


# ------------------------------------------------------------------------------------------------------------------
# MPFB adapter: the ONLY place that calls MPFB
# ------------------------------------------------------------------------------------------------------------------
class Mpfb:
    def __init__(self, data_dir=None, ext_dir=None):
        self.data_dir = data_dir
        self.pkg = self._enable(ext_dir)
        self.HumanService = self._cls("services.humanservice", "HumanService")
        self.TargetService = self._cls("services.targetservice", "TargetService", required=False)
        self.LocationService = self._cls("services.locationservice", "LocationService", required=False)

    @staticmethod
    def _enable(ext_dir=None):
        """Enable the installed MPFB extension, or (not installed) import it from ext_dir/mpfb for this run only
        (Blender's user configuration is not changed).  Returns the package name."""
        import addon_utils
        names = [m.__name__ for m in addon_utils.modules() if m.__name__.split(".")[-1] == "mpfb"]
        if names:
            addon_utils.enable(names[0], default_set=True, persistent=False)
            return names[0]
        if not ext_dir or not os.path.isdir(os.path.join(ext_dir, "mpfb")):
            raise RuntimeError("MPFB is not installed and no --ext folder with mpfb/ was given")
        # a local extension repository for this run only (--factory-startup: the preferences are not saved)
        repos = bpy.context.preferences.extensions.repos
        repo = next((r for r in repos if r.module == "npc_mpfb"), None)
        if repo is None:
            repo = repos.new(name="npc_mpfb", module="npc_mpfb", custom_directory=ext_dir, source="USER")
        addon_utils.extensions_refresh(ensure_wheels=False) if hasattr(addon_utils, "extensions_refresh") else None
        name = "bl_ext.npc_mpfb.mpfb"
        addon_utils.enable(name, default_set=True, persistent=False)
        importlib.import_module(name)
        return name

    def _cls(self, mod, cls, required=True):
        try:
            return getattr(importlib.import_module("%s.%s" % (self.pkg, mod)), cls)
        except Exception as e:                              # noqa: BLE001
            if required:
                raise RuntimeError("MPFB API: %s.%s.%s not found (%s) - run --probe" % (self.pkg, mod, cls, e))
            return None

    # --- data -----------------------------------------------------------------------------------------------------
    def asset_roots(self):
        roots = []
        if self.data_dir:
            roots.append(self.data_dir)
        if self.LocationService is not None:
            for fn in ("get_user_data", "get_mpfb_data", "get_system_data"):
                f = getattr(self.LocationService, fn, None)
                if f:
                    try:
                        roots.append(f())
                    except Exception:                       # noqa: BLE001
                        pass
        return [r for r in roots if r and os.path.isdir(r)]

    def asset(self, folder, ext="mhclo"):
        """The first .<ext> file in an asset folder (relative to the data roots), or a direct relative file."""
        for root in self.asset_roots():
            p = os.path.join(root, folder)
            if os.path.isfile(p):
                return p
            fs = sorted(glob.glob(os.path.join(p, "*." + ext)))
            if fs:
                return fs[0]
        raise FileNotFoundError("asset %s (*.%s) not found under %s" % (folder, ext, self.asset_roots()))

    def find(self, kind, pattern, ext):
        """Asset files of a kind folder (skins, eyes, eyebrows, eyelashes, teeth, hair, clothes) matching the pattern
        (patterns separated by |).  Sorted, first = the choice."""
        out = []
        for root in self.asset_roots():
            for f in glob.glob(os.path.join(root, "**", kind, "**", "*." + ext), recursive=True):
                name = os.path.basename(f).lower()
                if any(fnmatch.fnmatch(name, p.strip().lower()) for p in pattern.split("|")):
                    out.append(f)
        return sorted(set(out))

    # --- human ----------------------------------------------------------------------------------------------------
    def create_human(self, macro):
        details = None
        if self.TargetService is not None and hasattr(self.TargetService, "get_default_macro_info_dict"):
            details = self.TargetService.get_default_macro_info_dict()
            for k in ("gender", "age", "muscle", "weight", "proportions"):
                details[k] = macro[k]
            a, s, c = macro["race"]
            details["race"] = dict(african=a, asian=s, caucasian=c)
        hs = self.HumanService
        return hs.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                               feet_on_ground=True, scale=0.1, macro_detail_dict=details)

    def add_rig(self, basemesh):
        for rig in ("default", "game_engine"):
            try:
                return self.HumanService.add_builtin_rig(basemesh, rig, import_weights=True), rig
            except Exception as e:                          # noqa: BLE001
                last = e
        raise RuntimeError("MPFB add_builtin_rig failed: %s" % last)

    def set_skin(self, basemesh, mhmat):
        self.HumanService.set_character_skin(mhmat, basemesh, skin_type="MAKESKIN")

    def add_asset(self, basemesh, mhclo, asset_type):
        """Returns the new mesh object."""
        before = set(bpy.data.objects)
        self.HumanService.add_mhclo_asset(mhclo, basemesh, asset_type=asset_type, material_type="MAKESKIN")
        new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        return new[0] if new else None


# ------------------------------------------------------------------------------------------------------------------
def probe(data_dir, ext_dir=None):
    """Read-only: what does the installed MPFB offer?"""
    m = Mpfb(data_dir, ext_dir)
    print("PROBE package", m.pkg)
    for cls in (m.HumanService, m.TargetService, m.LocationService):
        if cls is None:
            continue
        for nm, fn in inspect.getmembers(cls, predicate=inspect.isfunction):
            if not nm.startswith("_"):
                try:
                    sig = str(inspect.signature(fn))
                except (TypeError, ValueError):
                    sig = "(?)"
                print("PROBE %s.%s%s" % (cls.__name__, nm, sig))
    print("PROBE roots", m.asset_roots())
    for kind, ext in (("skins", "mhmat"), ("eyes", "mhclo"), ("eyebrows", "mhclo"), ("eyelashes", "mhclo"),
                      ("teeth", "mhclo"), ("hair", "mhclo"), ("clothes", "mhclo"), ("proxymeshes", "proxy")):
        fs = m.find(kind, "*", ext)
        print("PROBE %s: %d" % (kind, len(fs)))
        for f in fs[:80]:
            print("PROBE   %s" % os.path.relpath(f, m.asset_roots()[0]) if m.asset_roots() else f)


# ------------------------------------------------------------------------------------------------------------------
# geometry steps
# ------------------------------------------------------------------------------------------------------------------
def side_names(pat, s):
    return pat.replace(".S", "." + s).replace("_S", "_" + s.lower())


def resolve_bone_map(mh_rig):
    """MPFB bone name -> v3 bone name, for every MPFB bone (unmapped -> nearest mapped ancestor)."""
    direct = {}
    for b in mh_rig.data.bones:
        for pat, v3 in BONE_MAP:
            for s in ("L", "R"):
                p = side_names(pat, s)
                if fnmatch.fnmatch(b.name, p):
                    direct[b.name] = v3.replace(".S", "." + s)
                    break
            if b.name in direct:
                break
    out = {}
    for b in mh_rig.data.bones:
        x = b
        while x is not None and x.name not in direct:
            x = x.parent
        out[b.name] = direct[x.name] if x is not None else "hips"
    return out


def turn_to_our_axes(objs):
    """MakeHuman faces -Y; we face +X with left = +Y: +90 deg about Z."""
    R = Matrix.Rotation(math.radians(90.0), 4, "Z")
    for o in objs:
        if o.parent is None:
            o.matrix_world = R @ o.matrix_world
    bpy.context.view_layer.update()
    for o in objs:
        if o.type == "MESH":
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)


def delete_helpers(basemesh):
    """MakeHuman's helper geometry (clothes fitting helpers, joint cubes) is not part of the body."""
    names = [g.name for g in basemesh.vertex_groups if g.name.lower().startswith(("helper", "joint", "hide"))]
    if not names:
        return 0
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(basemesh.data)
    dl = bm.verts.layers.deform.active
    idx = {basemesh.vertex_groups[n].index for n in names}
    kill = [v for v in bm.verts if dl and any(g in idx for g in v[dl].keys())]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(basemesh.data)
    bm.free()
    return len(kill)


JOINT_GROUPS = {                       # v3 bone head <- MakeHuman joint group (S = l / r)
    "hips": "joint-pelvis", "neck": "joint-neck", "head": "joint-head", "jaw": "joint-jaw",
    "shoulder.S": "joint-S-clavicle", "upper_arm.S": "joint-S-shoulder", "forearm.S": "joint-S-elbow",
    "hand.S": "joint-S-hand", "thigh.S": "joint-S-upper-leg", "shin.S": "joint-S-knee", "foot.S": "joint-S-ankle",
    "toe.S": "joint-S-foot-1",                          # the ball of the foot (foot-2 is the toe tip)
}


def mh_to_ours(p):
    """MakeHuman axes (faces -Y, left = +X) -> ours (faces +X, left = +Y)."""
    return Vector((-p.y, p.x, p.z))


def ours_to_mh(d):
    return Vector((d.y, -d.x, d.z))


def group_centroids(ob, wmin=0.5):
    """World centroid of every vertex group (the joint cubes; face bone groups with wmin 0.3)."""
    acc = {}
    mw = ob.matrix_world
    for v in ob.data.vertices:
        co = mw @ v.co
        for g in v.groups:
            if g.weight > wmin:
                a = acc.setdefault(g.group, [Vector(), 0])
                a[0] += co
                a[1] += 1
    return {ob.vertex_groups[i].name: a[0] / a[1] for i, a in acc.items() if a[1]}


def joints_ours(base):
    """v3 joint positions (ours axes) from the joint groups; spine / chest between hips and neck as in v3; lids at the
    eyes; symmetric."""
    cen = group_centroids(base)
    J = {}
    for v3, grp in JOINT_GROUPS.items():
        for s_, mh in ((("L", "l"), ("R", "r")) if ".S" in v3 else (("", ""),)):
            name = v3.replace(".S", "." + s_) if s_ else v3
            g = grp.replace("-S-", "-%s-" % mh)
            if g in cen:
                J[name] = cen[g].copy()                  # the meshes are in our axes already (finish_meshes)
    hz, nz = N.BIND_HEAD["hips"].z, N.BIND_HEAD["neck"].z
    for b in ("spine", "chest"):
        f = (N.BIND_HEAD[b].z - hz) / (nz - hz)
        J[b] = J["hips"].lerp(J["neck"], f)
    if "joint-l-eye" in cen and "joint-r-eye" in cen:
        eyes = (cen["joint-l-eye"] + cen["joint-r-eye"]) / 2          # the eyeball centres: lids turn about them
        J["lids"] = eyes.copy()
        J["lids_low"] = eyes.copy()
        J["brow.L"], J["brow.R"] = cen["joint-l-eye"].copy(), cen["joint-r-eye"].copy()
    bc = group_centroids(base, 0.3)
    for s_ in ("L", "R"):
        if "oris07." + s_ in bc:
            J["mouth." + s_] = bc["oris07." + s_] - Vector((0.035, 0.0, 0.0))
    for b in list(J):                                                   # symmetric about y = 0
        if b.endswith(".L") and b[:-1] + "R" in J:
            a, c = J[b], J[b[:-1] + "R"]
            m = Vector(((a.x + c.x) / 2, (a.y - c.y) / 2, (a.z + c.z) / 2))
            J[b], J[b[:-1] + "R"] = m, Vector((m.x, -m.y, m.z))
        elif "." not in b:
            J[b].y = 0.0
    return J


def pose_to_v3_bind(mh_rig, meshes, bmap):
    """Pose the MakeHuman rig (MakeHuman axes) so upper arms, forearms, thighs and shins lie along OUR bind directions;
    apply the pose to every mesh (their vertex groups stay).  Proximal chains first."""
    bpy.context.view_layer.objects.active = mh_rig
    bpy.ops.object.mode_set(mode="POSE")
    want = [("upper_arm", N.EL_JOINT - N.SH_JOINT), ("forearm", N.WR_JOINT - N.EL_JOINT),
            ("thigh", N.KNEE_JOINT - N.HIP_JOINT), ("shin", N.ANKLE_JOINT - N.KNEE_JOINT)]
    for part, d_l in want:
        for s_ in ("L", "R"):
            d = Vector(d_l) if s_ == "L" else Vector((d_l.x, -d_l.y, d_l.z))
            d = ours_to_mh(d).normalized()
            chain = [b for b in mh_rig.pose.bones if bmap.get(b.name) == "%s.%s" % (part, s_)
                     and not b.name.startswith(("finger", "metacarpal", "toe"))]
            if not chain:
                continue
            first = min(chain, key=lambda b: len(b.parent_recursive))
            last = max(chain, key=lambda b: len(b.parent_recursive))
            bpy.context.view_layer.update()
            a = mh_rig.matrix_world @ first.head
            b = mh_rig.matrix_world @ last.tail
            q = (b - a).normalized().rotation_difference(d)
            Mw = Matrix.Translation(a) @ q.to_matrix().to_4x4() @ Matrix.Translation(-a) @ \
                (mh_rig.matrix_world @ first.matrix)
            first.matrix = mh_rig.matrix_world.inverted() @ Mw
            bpy.context.view_layer.update()
    # relaxed hands: the fingers curl a little (MakeHuman finger bones; thumb less)
    for pb in mh_rig.pose.bones:
        nm = pb.name
        if nm.startswith("finger") and "-" in nm:
            digit, seg = nm[6:].split("-")[0], nm.split("-")[1].split(".")[0]
            ang = {"1": 14.0, "2": 26.0, "3": 22.0}.get(seg, 0.0) * (0.55 if digit == "1" else 1.0)
            pb.rotation_mode = "XYZ"
            pb.rotation_euler.x = math.radians(ang) * FINGER_CURL_SIGN
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in meshes:                                    # the MakeHuman targets are shape keys: bake them in first
        if o.data.shape_keys is not None:
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for o in meshes:
        mod = next((md for md in o.modifiers if md.type == "ARMATURE"), None)
        if mod is None:
            continue
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)


def finish_meshes(meshes, k, z0):
    """Unparent (keep the world transform), turn to our axes, scale by k about the origin, feet on z = 0."""
    R = Matrix.Rotation(math.radians(90.0), 4, "Z") @ Matrix.Scale(k, 4)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(Matrix.Translation((0, 0, -z0)))
        o.data.transform(R)
        o.data.update()


def build_our_rig(J, s):
    """Our rig (v3 + jaw + lids): heads at the joints J (ours axes), tails along the v3 bind directions scaled by s."""
    rig = N.build_rig("Rig")
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in rig.data.edit_bones:
        n = eb.name
        h = J.get(n)
        if h is None:                                   # root, prop.S: the v3 offset from the parent, scaled
            par = N.PARENT.get(n)
            h = (J[par] + (N.BIND_HEAD[n] - N.BIND_HEAD[par]) * s) if par else Vector((0, 0, 0))
            J[n] = h
        eb.head = h
        eb.tail = h + (N.BIND_TAIL[n] - N.BIND_HEAD[n]) * s
        eb.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def move_weights(ob, bmap, rig):
    """MPFB groups -> v3 groups (summed), <= 4 influences, normalised; skinned to our rig."""
    old = {g.index: g.name for g in ob.vertex_groups}
    acc = [dict() for _ in ob.data.vertices]
    for v in ob.data.vertices:
        for g in v.groups:
            nm = old.get(g.group)
            v3 = bmap.get(nm) if nm is not None else None
            if v3:
                acc[v.index][v3] = acc[v.index].get(v3, 0.0) + g.weight
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {n: ob.vertex_groups.new(name=n) for n in N.BONE_NAMES}
    for i, w in enumerate(acc):
        if not w:
            w = {"hips": 1.0}
        w = N.limit_normalise(w)
        for b, x in w.items():
            groups[b].add([i], x, "REPLACE")
    for m in list(ob.modifiers):
        if m.type in ("ARMATURE", "MASK"):
            ob.modifiers.remove(m)
    ob.parent = rig
    ob.matrix_parent_inverse = Matrix.Identity(4)
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


def decimate(ob, target_tris):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris <= target_tris:
        return tris
    g = ob.vertex_groups.get("npc_dec") or ob.vertex_groups.new(name="npc_dec")
    edge_v = set()
    for e in ob.data.edges:
        pass
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for vv in bm.verts:
        if any(e.is_boundary for e in vv.link_edges):
            edge_v.add(vv.index)
            for e in vv.link_edges:
                edge_v.add(e.other_vert(vv).index)
    bm.free()
    g.add([i for i in range(len(ob.data.vertices)) if i not in edge_v], 1.0, "REPLACE")
    if edge_v:
        g.add(list(edge_v), 0.0, "REPLACE")
    mod = ob.modifiers.new("Dec", "DECIMATE")
    mod.ratio = target_tris / tris
    mod.vertex_group = "npc_dec"
    mod.vertex_group_factor = 10.0
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_move_to_index(modifier="Dec", index=0)
    bpy.ops.object.modifier_apply(modifier="Dec")
    if ob.vertex_groups.get("npc_dec"):
        ob.vertex_groups.remove(ob.vertex_groups["npc_dec"])
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ------------------------------------------------------------------------------------------------------------------
# materials: plain Principled + textures (<= 1024 px), names from the contract
# ------------------------------------------------------------------------------------------------------------------
def read_mhmat(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and not parts[0].startswith("#"):
            out[parts[0]] = parts[1]
    return out


def blur_alpha(px, w, h, r):
    """Box-blur the alpha channel 3 times (about a gaussian of radius r px): a smooth clip contour."""
    import numpy as np
    a = px[:, 3].reshape(h, w).astype(np.float32)
    for _ in range(3):
        for axis in (0, 1):
            c = np.cumsum(np.pad(a, [(r + 1, r) if k == axis else (0, 0) for k in (0, 1)], mode="edge"), axis=axis)
            a = ((np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis) -
                  np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)) / (2 * r + 1))
    px[:, 3] = a.ravel()
    return px


def texture(path, name, size=BUDGET["tex"], detail=False, bake_rgb=None, alpha_blur=0):
    """Load, shrink to <= size, optionally make a tint detail map (the image divided by its mean colour), save PNG."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    if max(w, h) > size:
        img.scale(size * w // max(w, h), size * h // max(w, h))
    if detail:
        import numpy as np
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        solid = px[:, 3] > 0.5                              # the mean of the visible pixels (alpha cards)
        mean = (px[solid, :3] if solid.any() else px[:, :3]).mean(axis=0) + 1e-4
        px[:, :3] = np.clip(px[:, :3] / mean * 0.82, 0.0, 1.0)
        if bake_rgb is not None:                            # a plain (untinted) material: its colour goes in here
            px[:, :3] = np.clip(px[:, :3] * np.array(bake_rgb, dtype=np.float32), 0.0, 1.0)
        if alpha_blur:
            w_, h_ = img.size
            px = blur_alpha(px, w_, h_, alpha_blur)
        img.pixels = px.ravel().tolist()
    os.makedirs(OUT_TEX, exist_ok=True)
    out = os.path.join(OUT_TEX, name + ".png")
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    return img


def plain_material(name, base=None, alpha=None, normal=None, rough=0.6, color=(1, 1, 1), cutoff=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    if base is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = base
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha == "base":
            # alpha clip: the glTF exporter writes alphaMode MASK (cutoff 0.5) for 1 - (alpha < 0.5)
            lt = nt.nodes.new("ShaderNodeMath")
            lt.operation = "LESS_THAN"
            lt.inputs[1].default_value = cutoff
            sub = nt.nodes.new("ShaderNodeMath")
            sub.operation = "SUBTRACT"
            sub.inputs[0].default_value = 1.0
            nt.links.new(tn.outputs["Alpha"], lt.inputs[0])
            nt.links.new(lt.outputs[0], sub.inputs[1])
            nt.links.new(sub.outputs[0], bsdf.inputs["Alpha"])
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = "DITHERED"
    if normal is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = normal
        tn.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


TEX_SIZE = {"Skin": 1024, "Hair": 1024, "Eye": 256, "Hair_brows": 256, "Hair_lashes": 256, "Teeth": 128}
TEX_DEFAULT, TEX_NORMAL = 512, 256          # garments; normal maps


def material_from_mhmat(mhmat, name, v, detail=False, alpha=False, bake_rgb=None):
    d = read_mhmat(mhmat)
    root = os.path.dirname(mhmat)

    def tex(key, suffix, **kw):
        f = d.get(key)
        if not f:
            return None
        p = f if os.path.isabs(f) else os.path.join(root, f)
        return texture(p, "%s_%s_%s" % (v, name.lower(), suffix), **kw) if os.path.exists(p) else None
    base = tex("diffuseTexture", "base", detail=detail, bake_rgb=bake_rgb, size=TEX_SIZE.get(name, TEX_DEFAULT),
               alpha_blur=6 if name == "Hair" else 0)
    nrm = tex("normalmapTexture", "normal", size=TEX_NORMAL)
    return plain_material(name, base=base, alpha="base" if alpha else None, normal=nrm,
                          cutoff=0.3 if name == "Hair_brows" else 0.5,
                          rough=float(d.get("roughness", 0.6) or 0.6))


def replace_materials(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


# ------------------------------------------------------------------------------------------------------------------
def clear_data():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images,
                 bpy.data.actions, bpy.data.node_groups, bpy.data.cameras, bpy.data.lights):
        for item in list(coll):
            try:
                coll.remove(item)
            except Exception:                               # noqa: BLE001
                pass
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def mhclo_material(mhclo):
    """The .mhmat a .mhclo names on its 'material' line (next to the .mhclo)."""
    for line in open(mhclo, encoding="utf-8", errors="replace"):
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0] == "material":
            f = os.path.join(os.path.dirname(mhclo), parts[1].strip())
            if os.path.exists(f):
                return f
    fs = glob.glob(os.path.join(os.path.dirname(mhclo), "*.mhmat"))
    return fs[0] if fs else None


def report_mpfb(base, mh_rig, objs):
    """What MPFB made (for the log): sizes, axes, bones, groups, masks."""
    zs = [(base.matrix_world @ v.co) for v in base.data.vertices]
    lo = Vector((min(p.x for p in zs), min(p.y for p in zs), min(p.z for p in zs)))
    hi = Vector((max(p.x for p in zs), max(p.y for p in zs), max(p.z for p in zs)))
    print("MPFB base %s: %d verts %d faces, bbox %s .. %s" % (base.name, len(base.data.vertices),
                                                            len(base.data.polygons), tuple(round(x, 3) for x in lo),
                                                            tuple(round(x, 3) for x in hi)))
    print("MPFB base modifiers:", [(md.name, md.type, getattr(md, "vertex_group", "")) for md in base.modifiers])
    print("MPFB base groups (%d):" % len(base.vertex_groups), [g.name for g in base.vertex_groups][:400])
    print("MPFB rig %s: %d bones:" % (mh_rig.name, len(mh_rig.data.bones)), [b.name for b in mh_rig.data.bones])
    for o in objs:
        if o is None:
            continue
        print("MPFB part %s: %d verts %d faces, mats %s, groups %d, mods %s" % (
            o.name, len(o.data.vertices), len(o.data.polygons), [m_.name for m_ in o.data.materials],
            len(o.vertex_groups), [(md.type, getattr(md, "object", None) and md.object.name) for md in o.modifiers]))


def build_variant(m, v, outfits, stop=None):
    import people_anims as PA
    spec = VARIANTS[v]
    clear_data()                  # not C.reset_scene(): factory settings would drop the run-only MPFB repository
    t0 = time.time()
    base = m.create_human(spec["macro"])
    mh_rig, rig_kind = m.add_rig(base)
    skin_mhmat = m.asset(spec["skin"], "mhmat")
    m.set_skin(base, skin_mhmat)
    parts = {}
    for kind, folder in dict(FACE, eyebrows=spec["brows"]).items():
        f = m.asset(folder)
        parts[kind] = (m.add_asset(base, f, kind.capitalize()), f)
    hair_f = m.asset(spec["hair"])
    parts["hair"] = (m.add_asset(base, hair_f, "Hair"), hair_f)
    garments = {}
    for oid in outfits:
        garments[oid] = []
        for folder, mat in OUTFITS[oid][spec["sex"]]:
            f = m.asset(folder)
            before = {md.name for md in base.modifiers}
            ob = m.add_asset(base, f, "Clothes")
            masks = [md.vertex_group for md in base.modifiers if md.name not in before and md.type == "MASK"]
            garments[oid].append((ob, f, mat, masks))
    objs = [p[0] for p in parts.values()] + [g[0] for gs in garments.values() for g in gs]
    report_mpfb(base, mh_rig, objs)
    if stop == "mpfb":
        out = os.path.join(os.environ.get("NPC_SCRATCH", os.path.dirname(N.MODEL_DIR)), "npc_mpfb_%s.blend" % v)
        bpy.ops.wm.save_as_mainfile(filepath=out)
        print("SAVED", out)
        return None
    # ---- pose, axes, size -------------------------------------------------------------------------------
    bmap = resolve_bone_map(mh_rig)
    meshes = [base] + [o for o in objs if o is not None]
    pose_to_v3_bind(mh_rig, meshes, bmap)
    body_idx = base.vertex_groups["body"].index if "body" in base.vertex_groups else None
    zs = [(base.matrix_world @ vv.co).z for vv in base.data.vertices
          if body_idx is None or any(g.group == body_idx and g.weight > 0.5 for g in vv.groups)]
    z0, k = min(zs), spec["height"] / (max(zs) - min(zs))
    finish_meshes(meshes, k, z0)
    J = joints_ours(base)
    print("  joints: " + ", ".join("%s %.3f/%.3f/%.3f (v3 %.3f)" % (b, J[b].x, J[b].y, J[b].z, N.BIND_HEAD[b].z * spec["height"] / 1.8)
                                  for b in ("hips", "neck", "head", "upper_arm.L", "hand.L", "thigh.L", "shin.L", "foot.L", "toe.L")))
    bpy.data.objects.remove(mh_rig)
    s_ = spec["height"] / 1.80
    rig = build_our_rig(J, s_)
    addon_objs = {}
    for oid in garments:
        if OUTFITS[oid].get("generator") == "coverall":
            shell, addon_objs = PU.make_uniform(base, J)
            garments[oid].insert(0, (shell, "gen:coverall", "shell", []))
            objs.append(shell)
    # ---- subdivision: only coarse garments keep one level -------------------------------------------------
    keep_subsurf = {g[0] for gs in garments.values() for g in gs} | {parts["eyes"][0]}
    for o in meshes:
        for md in list(o.modifiers):
            if md.type == "SUBSURF":
                bpy.context.view_layer.objects.active = o
                if o in keep_subsurf and len(o.data.polygons) < 800:
                    md.levels = 1
                    bpy.ops.object.modifier_apply(modifier=md.name)
                else:
                    o.modifiers.remove(md)
    for oid, gs in garments.items():
        tops = [g for g in gs if garment_layer(g[1]) == 3 and g[2] != "shell"]
        bottoms = [g[0] for g in gs if garment_layer(g[1]) == 2]
        for g in tops:
            extend_hem(g[0], [base] + bottoms)
    # ---- the body copy per outfit, before the groups are replaced -----------------------------------------
    if body_idx is not None:
        remove_groups_verts_not(base, "body")
    bodies = {}
    for oid, gs in garments.items():
        b = base.copy()
        b.data = base.data.copy()
        bpy.context.scene.collection.objects.link(b)
        remove_groups_verts(b, [mk for _, _, _, masks in gs for mk in masks])
        bodies[oid] = b
    bpy.data.objects.remove(base)
    # ---- weights ------------------------------------------------------------------------------------------
    for o in list(bodies.values()) + [o for o in objs if o is not None] + list(addon_objs.values()):
        move_weights(o, bmap, rig)
    for a in addon_objs.values():                       # add-ons are small: <= 900 triangles each
        if ntris(a) > 900:
            decimate(a, 900)
    # ---- materials ----------------------------------------------------------------------------------------
    skin_mat = material_from_mhmat(skin_mhmat, "Skin", os.path.basename(spec["skin"]), detail=True)
    eye_mat = material_from_mhmat(m.asset(spec["eye_mat"], "mhmat"), "Eye",
                                  "eye_" + os.path.splitext(os.path.basename(spec["eye_mat"]))[0])
    tris = {}
    head_parts = []
    for kind in ("eyes", "eyebrows", "eyelashes", "teeth"):
        ob, f = parts[kind]
        if ob is None:
            continue
        if kind == "eyes":
            mat = eye_mat
        else:
            nm = {"eyebrows": "Hair_brows", "eyelashes": "Hair_lashes", "teeth": "Teeth"}[kind]
            hairy = nm.startswith("Hair")
            key = os.path.basename(os.path.dirname(f)) + ("_%s" % spec["sex"] if hairy else "")
            mat = material_from_mhmat(mhclo_material(f), nm, key, detail=hairy, alpha=hairy,
                                      bake_rgb=((0.55,) * 3 if spec["sex"] == "m" else (0.72,) * 3) if hairy else None)
        replace_materials(ob, mat)
        if kind == "teeth":
            decimate(ob, 700)
        head_parts.append(ob)
    head = join(head_parts, "Head_%s" % v)
    tris[head.name] = ntris(head)
    hob, hf = parts["hair"]
    soften_hair(hob, J)
    replace_materials(hob, material_from_mhmat(mhclo_material(hf), "Hair", os.path.basename(os.path.dirname(hf)),
                                               detail=True, alpha=True))
    hob.name = hob.data.name = "Hair_%s" % v
    tris[hob.name] = decimate(hob, BUDGET["hair"])
    for oid, gs in garments.items():
        body = bodies[oid]
        replace_materials(body, skin_mat)
        nk = remove_covered(body, [ob for ob, _, _, _ in gs])
        # between garments: an inner layer loses what an outer layer covers (tops over trousers over shoes)
        for ob, f, _, _ in gs:
            outer = [o2 for o2, f2, _, _ in gs if garment_layer(f2) > garment_layer(f)]
            if outer:
                tuck_under(ob, outer)
                remove_covered(ob, outer)
        gsum = sum(ntris(ob) for ob, _, _, _ in gs)
        room = BUDGET["lod0"] - 600 - tris[head.name] - tris[hob.name]
        if any(g[2] == "shell" for g in gs):
            room -= max([0] + [ntris(a) for a in addon_objs.values()]) + 300     # the biggest add-on set
        body_t = min(ntris(body), BUDGET["body"])
        tb = decimate(body, body_t)
        g_budget = room - tb
        print("  %s %s: %d covered skin vertices removed" % (v, oid, nk))
        pieces = [body]
        for ob, f, mat, _ in gs:
            if mat == "shell":
                uniform_materials(ob, v)
                if gsum > g_budget:
                    decimate(ob, int(g_budget * ntris(ob) / max(1, gsum)))
                pieces.append(ob)
                continue
            if mat.startswith("tint:"):
                nm = mat[5:]
                plain = nm not in ("SuitAccent", "ClothTint")          # the game tints only these two
                mm = material_from_mhmat(mhclo_material(f), nm, os.path.basename(os.path.dirname(f)),
                                         detail=True, bake_rgb=TINT_BASE.get(nm) if plain else None)
            else:
                nm = "Cloth_" + os.path.basename(os.path.dirname(f))
                mm = material_from_mhmat(mhclo_material(f), nm, os.path.basename(os.path.dirname(f)))
            replace_materials(ob, mm)
            if gsum > g_budget:
                decimate(ob, int(g_budget * ntris(ob) / max(1, gsum)))
            pieces.append(ob)
        out = join(pieces, "Outfit_%s" % oid)
        tris[out.name] = ntris(out)
        print("  %s %s: body %d tris, outfit %d" % (v, oid, tb, tris[out.name]))
    for a, ob in addon_objs.items():
        uniform_materials(ob, v)
        tris[ob.name] = ntris(ob)
    # ---- AO, clips, export ----------------------------------------------------------------------------------
    objs_out = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
    occ = {n: [n] + ([hob.name] if n.startswith("Outfit_") else []) for n in objs_out}   # the hair shades the skin
    C.bake_ao(objs_out, occ, dist=0.12 * s_, samples=48, min_ao=0.45, strength=1.0, verbose=False)
    for o in objs_out.values():
        N.smooth_ao(o, iterations=2, floor={"Skin": 0.62, "Hair": 0.55})
    for n, o in objs_out.items():
        if n.startswith("Outfit_"):
            hairline_shade(o, hob)
    PA.FOOT_DZ = J["foot.L"].z - N.ANKLE_JOINT.z * s_          # this body's ankle height vs the v3 one
    PA.ARM_IN = 5.0                                            # the standing arms 5 deg closer (CRITIC round 40)
    solver = N.Solver()
    solver.set_rest_from_rig(rig)
    first_outfit = bpy.data.objects["Outfit_%s" % list(garments)[0]]          # the outfit npc_verify measures
    all_outfits = [bpy.data.objects["Outfit_%s" % o] for o in garments]
    calibrate_contacts(rig, solver, s_, [first_outfit, head, hob], all_outfits)
    reach = {sd: (solver.head["forearm." + sd] - solver.head["upper_arm." + sd]).length +
                 (solver.head["hand." + sd] - solver.head["forearm." + sd]).length for sd in ("L", "R")}

    def clamp_reach(P):
        """An arm target beyond 97 % of this body's reach is pulled in along the shoulder line (a straight arm has no
        bend plane: the elbow would flip)."""
        _, _, pos, _ = solver.solve(P)
        for sd in ("L", "R"):
            if P.g("arm.%s.ik" % sd) <= 0 or P.g("arm.%s.chest" % sd) > 0:
                continue
            sh = pos["upper_arm." + sd]
            t = Vector((P.g("arm.%s.x" % sd), P.g("arm.%s.y" % sd), P.g("arm.%s.z" % sd)))
            d = t - sh
            if d.length > REACH_MAX * reach[sd]:
                t = sh + d.normalized() * REACH_MAX * reach[sd]
                P["arm.%s.x" % sd], P["arm.%s.y" % sd], P["arm.%s.z" % sd] = t.x, t.y, t.z
        return P
    meta = {}
    for (name, kind, pf, pt, loop, frames, fn, extra) in PA.people_clips():
        fv = (lambda fn, name: (lambda f: PA.retarget(fn(f), s_, name)))(fn, name)
        N.bake_clip(rig, solver, name, fv, frames, fix=clamp_reach)
        mt = dict(frames=frames, duration_s=round(frames / N.FPS, 4), kind=kind, pose_from=pf, pose_to=pt, loop=loop)
        mt.update(extra)
        meta[name] = mt
    if os.environ.get("NPC_DEBUG"):
        import numpy as np
        import people_verify as PV
        co = pose_eval(rig, solver, PA.retarget(dict((c[0], c[6]) for c in PA.people_clips())["sit_bar_stool"](0), s_,
                                                  "sit_bar_stool"), [first_outfit])
        mk = (np.abs(co[:, 0] + 0.04) < 0.11) & (np.abs(co[:, 1]) < 0.15) & (co[:, 2] > 0.6)
        print("  DEBUG stool pose_eval after bake %.3f" % co[mk, 2].min())
        N.reset_pose(rig)
        PV.set_clip(rig, "sit_bar_stool", 1)
        PV.set_clip(rig, "sit_bar_stool", 0)
        co = PV.world_co(first_outfit)
        mk = (np.abs(co[:, 0] + 0.04) < 0.11) & (np.abs(co[:, 1]) < 0.15) & (co[:, 2] > 0.6)
        print("  DEBUG stool baked action %.3f" % co[mk, 2].min())
        rig.animation_data.action = None
    N.reset_pose(rig)
    path = os.path.join(N.MODEL_DIR, "people_%s.glb" % v)
    N.export_glb_skinned(path)
    n_img, saved = externalize_images(path)
    print("  %s: %d images to %s/ (%d bytes out of the GLB)" % (v, n_img, SHARED_TEX, saved))
    print("  %s: %s  %.1f s" % (v, tris, time.time() - t0))
    return dict(tris=tris, clips=meta, scale=s_, path=path, outfits=list(garments), addons=sorted(tris_addons(tris)),
                sources=dict(skin=spec["skin"], hair=spec["hair"], brows=spec["brows"], eyes=spec["eye_mat"],
                             outfits={o: [g[0] for g in OUTFITS[o][spec["sex"]]] for o in garments}))


PA_DEFAULTS = {}
FINGER_CURL_SIGN = 1.0      # + curls the MakeHuman finger bones towards the palm (checked in the hand render)
REACH_MAX = 0.93            # arm IK targets beyond this share of the arm length are pulled in (the elbow keeps a bend)


def pose_eval(rig, solver, P, obs):
    """Pose the rig from a Pose (as bake_clip does) and return the evaluated vertices of obs (world, numpy)."""
    import numpy as np
    import people_verify as PV
    qb, loc, _, _ = solver.basis(P)
    for b, q in qb.items():
        pb = rig.pose.bones[b]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
    rig.pose.bones["hips"].location = loc
    for sd in ("L", "R"):
        rig.pose.bones["prop." + sd].location = solver.last_prop_locs["prop." + sd]
    bpy.context.view_layer.update()
    return np.vstack([PV.world_co(o) for o in obs if o is not None])


def calibrate_contacts(rig, solver, s, obs, feet_obs=None):
    """This body's contact offsets (people_anims module values): lying on the floor, the chair seat and the bar stool
    (the same masks as npc_verify).  Two passes."""
    import numpy as np
    import people_anims as PA
    if not PA_DEFAULTS:
        PA_DEFAULTS.update(LIE_LIFT=PA.LIE_LIFT, SEAT_DROP=PA.SEAT_DROP, STOOL_ADJ=PA.STOOL_ADJ, KNEEL_ADJ=0.0)
    for k, v in PA_DEFAULTS.items():
        setattr(PA, k, v)
    clips = {c[0]: c[6] for c in PA.people_clips()}
    for _ in range(2):
        # the ankle height: the lowest sole of all outfits (shoes and boots) on the floor when standing
        co = pose_eval(rig, solver, PA.retarget(clips["idle"](0), s, "idle"), feet_obs or obs)
        PA.FOOT_DZ += 0.002 - co[:, 2].min()
        co = pose_eval(rig, solver, PA.retarget(clips["dead"](0), s, "dead"), obs)
        PA.LIE_LIFT += 0.004 - co[:, 2].min()
        co = pose_eval(rig, solver, PA.retarget(clips["repair_kneel"](0), s, "repair_kneel"), obs)
        PA.KNEEL_ADJ += 0.004 - co[:, 2].min()
        co = pose_eval(rig, solver, PA.retarget(clips["sit_idle"](0), s, "sit_idle"), obs)
        m = (co[:, 0] > -0.52) & (co[:, 0] < -0.15) & (np.abs(co[:, 1]) < 0.23)
        if m.any():
            PA.SEAT_DROP += 0.462 - co[m, 2].min()
        co = pose_eval(rig, solver, PA.retarget(clips["sit_bar_stool"](0), s, "sit_bar_stool"), obs)
        m = (np.abs(co[:, 0] + 0.04) < 0.11) & (np.abs(co[:, 1]) < 0.15) & (co[:, 2] > 0.6)
        if m.any():
            if os.environ.get("NPC_DEBUG"):
                i = int(np.argmin(np.where(m, co[:, 2], 9.0)))
                print("  DEBUG stool pass: low %.3f at %s, STOOL_ADJ %.3f, hips %s" % (
                    co[m, 2].min(), tuple(round(x, 3) for x in co[i]), PA.STOOL_ADJ,
                    tuple(round(x, 3) for x in rig.pose.bones["hips"].location)))
            PA.STOOL_ADJ += 0.762 - co[m, 2].min()
    N.reset_pose(rig)
    print("  contacts: LIE_LIFT %.3f  SEAT_DROP %.3f  STOOL_ADJ %.3f  KNEEL_ADJ %.3f  FOOT_DZ %.3f" % (
        PA.LIE_LIFT, PA.SEAT_DROP, PA.STOOL_ADJ, PA.KNEEL_ADJ, PA.FOOT_DZ))


def soften_hair(ob, J):
    """Hair below the jaw rests on the neck and the shoulders: at the tips the head weight becomes head 10 %, neck 50 %,
    chest 40 % (the collar moves with the chest, so the tips stay outside it)."""
    z_top, z_low = J["jaw"].z + 0.02, J["neck"].z
    gh, gn, gc = (ob.vertex_groups.get(n) for n in ("head", "neck", "chest"))
    if gh is None:
        return
    z_min = J["neck"].z + 0.045                         # trim: no hair below the neck base + 4.5 cm (the collar)
    for v in ob.data.vertices:
        if v.co.z < z_min:
            v.co.z = z_min - 0.004 * (z_min - v.co.z) / max(1e-3, z_min - v.co.z + 0.02)
    gn = gn or ob.vertex_groups.new(name="neck")
    gc = gc or ob.vertex_groups.new(name="chest")
    for v in ob.data.vertices:
        z = (ob.matrix_world @ v.co).z
        if z >= z_top:
            continue
        f = min(1.0, (z_top - z) / max(1e-3, z_top - z_low))
        wh = next((g.weight for g in v.groups if g.group == gh.index), 0.0)
        if wh <= 0:
            continue
        wn = next((g.weight for g in v.groups if g.group == gn.index), 0.0)
        wc = next((g.weight for g in v.groups if g.group == gc.index), 0.0)
        gh.add([v.index], wh * (1 - 0.9 * f), "REPLACE")
        gn.add([v.index], wn + wh * 0.5 * f, "REPLACE")
        gc.add([v.index], wc + wh * 0.4 * f, "REPLACE")


def hairline_shade(ob, hair, band=0.025, dark=0.55):
    """A soft band under the hair edge: skin within `band` of the hair surface gets darker AO (fading out), so the
    cut-out edge of the hair cards does not read as a hard line on the forehead."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(hair.data)
    bm.transform(hair.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    me = ob.data
    attr = me.color_attributes.get("AO")
    if attr is None:
        return 0
    n = 0
    mw = ob.matrix_world
    for poly in me.polygons:
        if me.materials[poly.material_index].name.split(".")[0] != "Skin":
            continue
        for li in poly.loop_indices:
            p = mw @ me.vertices[me.loops[li].vertex_index].co
            hit = tree.find_nearest(p, band)
            if hit[0] is None:
                continue
            f = dark + (1.0 - dark) * (hit[3] / band) ** 1.5
            c = attr.data[li].color
            attr.data[li].color = (c[0] * f, c[1] * f, c[2] * f, c[3])
            n += 1
    return n


def ntris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def remove_groups_verts_not(ob, keep):
    """Delete every vertex that is not in the group keep (MakeHuman helper geometry)."""
    import bmesh
    gi = ob.vertex_groups[keep].index
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    dl = bm.verts.layers.deform.active
    kill = [v for v in bm.verts if not (dl and v[dl].get(gi, 0.0) > 0.5)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


SHARED_TEX = "people_tex_shared"


def externalize_images(glb_path):
    """Move every embedded image of a GLB to assets/models/people_tex_shared/<name>.png and refer to it by a relative
    URI (one file per texture for every variant that uses it; Godot imports it once).  The BIN chunk is compacted."""
    import struct
    data = open(glb_path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    boff = 20 + jlen
    blen = struct.unpack("<I", data[boff:boff + 4])[0]
    binc = data[boff + 8:boff + 8 + blen]
    out_dir = os.path.join(os.path.dirname(glb_path), SHARED_TEX)
    os.makedirs(out_dir, exist_ok=True)
    views = doc.get("bufferViews", [])
    drop = set()
    for im in doc.get("images", []):
        if "bufferView" not in im:
            continue
        bv = views[im["bufferView"]]
        raw = binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        name = "".join(c if c.isalnum() or c in "-_" else "_" for c in im.get("name", "img%d" % im["bufferView"]))
        ext = ".png" if im.get("mimeType", "image/png") == "image/png" else ".jpg"
        fp = os.path.join(out_dir, name + ext)
        if not os.path.exists(fp) or open(fp, "rb").read() != raw:
            open(fp, "wb").write(raw)
        drop.add(im["bufferView"])
        im.pop("bufferView")
        im.pop("mimeType", None)
        im["uri"] = "%s/%s%s" % (SHARED_TEX, name, ext)
    if not drop:
        return 0, 0
    remap, new_views, parts, off = {}, [], [], 0
    for i, bv in enumerate(views):
        if i in drop:
            continue
        raw = binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        pad = (-off) % 4
        parts.append(b"\0" * pad)
        off += pad
        nb = dict(bv)
        nb["byteOffset"] = off
        parts.append(raw)
        off += len(raw)
        remap[i] = len(new_views)
        new_views.append(nb)
    for acc in doc.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
        sp = acc.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    doc["bufferViews"] = new_views
    newbin = b"".join(parts)
    newbin += b"\0" * ((-len(newbin)) % 4)
    doc["buffers"][0]["byteLength"] = len(newbin)
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(newbin)
    outb = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + \
        struct.pack("<II", len(newbin), 0x004E4942) + newbin
    tmp = glb_path + ".tmp"
    open(tmp, "wb").write(outb)
    os.replace(tmp, glb_path)
    return len(drop), len(data) - len(outb)


def tris_addons(tris):
    return [n for n in tris if n.startswith("Addon_")]


def extend_hem(top, others, band=0.08, drop=0.055, gap=0.006):
    """Lengthen a top: its lowest band moves down by up to `drop` (so it covers the waistband) and stays outside the
    body and the trousers (`gap`)."""
    from mathutils.bvhtree import BVHTree
    import bmesh
    trees = []
    for o in others:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        trees.append(BVHTree.FromBMesh(bm))
        bm.free()
    zs = [v.co.z for v in top.data.vertices]
    zmin = min(zs)
    for v in top.data.vertices:
        if v.co.z > zmin + band:
            continue
        w = 1.0 - (v.co.z - zmin) / band
        w = w * w * (3 - 2 * w)
        p = v.co.copy()
        p.z -= drop * w
        best = None
        for t in trees:
            hit = t.find_nearest(p, 0.08)
            if hit[0] is not None and (best is None or hit[3] < best[3]):
                best = hit
        if best is not None and (p - best[0]).dot(best[1]) < gap:
            p = best[0] + best[1] * gap
        v.co = p
    top.data.update()


_UNI_MATS = {}


def canvas_textures():
    """A woven canvas (base around white, for the tint) and its normal map; shared by every variant."""
    import numpy as np
    base_p = os.path.join(OUT_TEX, "uniform_canvas_base.png")
    nrm_p = os.path.join(OUT_TEX, "uniform_canvas_normal.png")
    if not (os.path.exists(base_p) and os.path.exists(nrm_p)):
        os.makedirs(OUT_TEX, exist_ok=True)
        n = 256
        u = np.arange(n)[None, :] / n
        v = np.arange(n)[:, None] / n
        rng = np.random.default_rng(7)
        weave = 0.5 + 0.5 * np.sin(2 * np.pi * 32 * u) * np.sin(2 * np.pi * 32 * v)
        noise = rng.random((n, n)) * 0.5 + 0.5 * np.roll(rng.random((n, n)), 1, axis=0)
        h = 0.7 * weave + 0.3 * noise
        col = 0.82 + 0.035 * (h - 0.5)
        img = bpy.data.images.new("uniform_canvas_base", n, n, alpha=False)
        px = np.ones((n, n, 4), dtype=np.float32)
        px[:, :, 0] = px[:, :, 1] = px[:, :, 2] = col
        img.pixels = px.ravel().tolist()
        img.filepath_raw = base_p
        img.file_format = "PNG"
        img.save()
        gx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
        gy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
        nz = np.ones_like(h)
        nx, ny = -gx * 0.6, -gy * 0.6
        L = np.sqrt(nx * nx + ny * ny + nz * nz)
        img2 = bpy.data.images.new("uniform_canvas_normal", n, n, alpha=False)
        px2 = np.ones((n, n, 4), dtype=np.float32)
        px2[:, :, 0], px2[:, :, 1], px2[:, :, 2] = nx / L * 0.5 + 0.5, ny / L * 0.5 + 0.5, nz / L * 0.5 + 0.5
        img2.pixels = px2.ravel().tolist()
        img2.filepath_raw = nrm_p
        img2.file_format = "PNG"
        img2.save()
    b = bpy.data.images.load(base_p, check_existing=True)
    nm = bpy.data.images.load(nrm_p, check_existing=True)
    return b, nm


def uniform_materials(ob, v):
    """The uniform's contract materials by slot name (UniformBase and SuitAccent are tinted by the game)."""
    try:
        next(iter(_UNI_MATS.values())).name if _UNI_MATS else None
    except ReferenceError:
        _UNI_MATS.clear()
    if not _UNI_MATS:
        for nm_ in ("UniformBase", "SuitAccent", "Zip", "Leather", "Metal", "Apron", "Armor", "Rank"):
            ph = bpy.data.materials.get(nm_)
            if ph is not None:
                ph.name = nm_ + "_placeholder"          # the real materials take the exact contract names
        cb, cn = canvas_textures()
        _UNI_MATS.update({
            "UniformBase": plain_material("UniformBase", base=cb, normal=cn, rough=0.82),
            "SuitAccent": plain_material("SuitAccent", base=cb, normal=cn, rough=0.7),
            "Zip": plain_material("Zip", color=(0.07, 0.07, 0.08), rough=0.35),
            "Leather": plain_material("Leather", color=(0.10, 0.07, 0.05), rough=0.6),
            "Metal": plain_material("Metal", color=(0.60, 0.61, 0.63), rough=0.3),
            "Apron": plain_material("Apron", base=cb, normal=cn, rough=0.85, color=(0.93, 0.93, 0.91)),
            "Armor": plain_material("Armor", color=(0.16, 0.17, 0.19), rough=0.5),
            "Rank": plain_material("Rank", color=(0.80, 0.64, 0.24), rough=0.35),
        })
    for i, m in enumerate(ob.data.materials):
        base = m.name.split(".")[0].replace("_placeholder", "") if m else "UniformBase"
        if base in _UNI_MATS:
            ob.data.materials[i] = _UNI_MATS[base]


def garment_layer(mhclo):
    if mhclo.startswith("gen:"):
        return 3
    """Our layer order (the packs give most garments the same z_depth): tops 3, trousers / skirts 2, shoes 1."""
    n = os.path.basename(os.path.dirname(mhclo)).lower()
    if any(k in n for k in ("shirt", "t-shirt", "tee", "polo", "top", "sweater", "jacket", "suit", "dress")):
        return 3
    if any(k in n for k in ("pants", "jeans", "trousers", "skirt", "shorts")):
        return 2
    return 1


def tuck_under(inner, outers, reach=0.03, gap=0.004):
    """Inner-layer vertices that stick out through an outer layer (within `reach`) move to just inside it."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    trees = []
    for g in outers:
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bm.transform(g.matrix_world)
        trees.append(BVHTree.FromBMesh(bm))
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(inner.data)
    bm.normal_update()
    moved = 0
    for v in bm.verts:
        p = inner.matrix_world @ v.co
        n = (inner.matrix_world.to_3x3() @ v.normal).normalized()
        for t in trees:
            hit = t.ray_cast(p + n * 0.002, -n, reach)[0]
            if hit is not None:
                v.co = inner.matrix_world.inverted() @ (hit - n * gap)
                moved += 1
                break
    bm.to_mesh(inner.data)
    bm.free()
    return moved


def remove_covered(body, garments, reach=0.03, margin=0.05):
    """Delete body vertices under a garment: a ray along the vertex normal meets a garment within `reach`.  Vertices
    within `margin` of a garment's open edge (neckline, cuffs, hem) stay: the edge lifts off the body in motion."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
    trees = []
    edge_pts = []
    for g in garments:
        bm = bmesh.new()
        bm.from_mesh(g.data)
        bm.transform(g.matrix_world)
        trees.append(BVHTree.FromBMesh(bm))
        edge_pts += [v.co.copy() for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
        bm.free()
    kd = KDTree(max(1, len(edge_pts)))
    for i, p in enumerate(edge_pts):
        kd.insert(p, i)
    kd.balance()
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    kill = []
    for v in bm.verts:
        p = body.matrix_world @ v.co
        n = (body.matrix_world.to_3x3() @ v.normal).normalized()
        if edge_pts and kd.find(p)[2] < margin:
            continue
        if any(t.ray_cast(p - n * 0.002, n, reach)[0] is not None for t in trees):
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    return len(kill)


def remove_groups_verts(ob, names):
    import bmesh
    idx = {ob.vertex_groups[n].index for n in names if n in ob.vertex_groups}
    if not idx:
        return
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    dl = bm.verts.layers.deform.active
    kill = [v for v in bm.verts if dl and any(g in idx and w > 0.5 for g, w in v[dl].items())]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def join(objs, name):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def write_manifest(results):
    import people_build as PB
    import people_anims as PA
    MAN = PB.MANIFEST
    doc = json.load(open(MAN, encoding="utf-8")) if os.path.exists(MAN) else {}
    doc["version"] = "5.0-mpfb-pilot"
    doc["skeleton"] = dict(bones=list(N.BONE_NAMES), face_bones=list(N.BONE_NAMES[24:]),
                           note=("The v3 skeleton (24 bones, the same names and hierarchy) plus face bones under head: "
                                 "jaw (lower face), lids (upper lids: blink), lids_low (lower lids), brow.L/R, mouth.L/R "
                                 "(corners).  Expressions (smile, laugh, frown, surprise) are keyed in the clips.  Joint "
                                 "positions per body (MPFB)."))
    doc["status"] = ("PILOT (MPFB): m1 and f1, outfits uniform_engineering and casual_a, 30 clips.  Bodies from MPFB "
                     "(MakeHuman, CC0 assets) skinned to OUR skeleton (route A): names, bones, clips and the draw "
                     "rule are as before.")
    variants = doc.get("variants", {})
    for v, r in results.items():
        spec = VARIANTS[v]
        outs = {}
        for o in r["outfits"]:
            if OUTFITS[o].get("generator") == "coverall":
                for dept, d in PU.DEPARTMENTS.items():
                    outs[dept] = dict(mesh="Outfit_%s" % o, addons=["Addon_%s" % a for a in d["addons"]],
                                      base_rgb=[round(x, 3) for x in d["base"]])
            else:
                outs[o] = "Outfit_%s" % o
        on_screen = {}
        for o, e in outs.items():
            mesh = e if isinstance(e, str) else e["mesh"]
            add = [] if isinstance(e, str) else e["addons"]
            on_screen[o] = (r["tris"]["Head_%s" % v] + r["tris"]["Hair_%s" % v] + r["tris"][mesh] +
                            sum(r["tris"].get(a, 0) for a in add))
        variants[v] = dict(sex=spec["sex"], height_m=spec["height"], scale=round(r["scale"], 4),
                           file="people_%s.glb" % v, head="Head_%s" % v, hair="Hair_%s" % v,
                           outfits=outs, addons=r["addons"], triangles=r["tris"], triangles_on_screen=on_screen,
                           source="MPFB 2.0.17 + CC0 MakeHuman assets", assets=r["sources"])
    doc["variants"] = variants
    doc["outfits"] = {o: dict(who=d["who"], look=d["look"]) for o, d in PU.DEPARTMENTS.items()}
    doc["outfits"]["casual_a"] = dict(who=OUTFITS["casual_a"]["who"], look=OUTFITS["casual_a"]["look"])
    draw = doc.get("draw", {})
    draw["per_person"] = ("Draw Head_<variant> (eyes, brows, lashes, teeth), Hair_<variant> and ONE Outfit_<id> (the "
                          "body skin it leaves visible + its garments).  Hide every other Outfit_*.")
    draw["materials"] = {
        "Skin": "tint like v3 Skin (mode 2); the skin texture multiplies (a detail map around white)",
        "Hair*": "Hair, Hair_brows, Hair_lashes: tint like v3 Hair (mode 3); alpha MASK (clip 0.5); the texture "
                 "multiplies",
        "SuitAccent": "department colour (mode 1): the uniform shirt; the texture multiplies",
        "Coverall": "plain grey trousers (texture)", "ClothTint": "per-person clothes colour; the texture multiplies",
        "Eye": "plain, textured", "Teeth": "plain", "Cloth_*": "plain, textured (the garment's own look)"}
    draw["lod"] = "LOD0 only in this pilot (<= 24k triangles per person on screen).  LOD1 (<= 4k) follows."
    doc["draw"] = draw
    clips = {}
    for v, r in results.items():
        for name, mt in r["clips"].items():
            clips.setdefault(name, mt)
    doc["clips"] = clips
    doc["furniture"] = dict(bar_stool=PA.BAR_STOOL)
    doc["textures"] = dict(note="embedded in each GLB, <= 1024 px; sources in assets/models/people_tex/ (.gdignore)")
    doc["credits"] = ("MakeHuman / MPFB assets: CC0 packs (makehuman_system_assets, skins01, skins02, hair01, shirts01, "
                      "pants01, suits01, suits02, shoes01, dress01, eyebrows01, eyelashes01)")
    with open(MAN + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(MAN + ".tmp", MAN)
    with open(PB.PAIRS + ".tmp", "w", encoding="utf-8") as fh:          # the pair offsets (hug distance)
        json.dump(PA.pairs_json(), fh, indent=1)
    os.replace(PB.PAIRS + ".tmp", PB.PAIRS)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    data = argv[argv.index("--data") + 1] if "--data" in argv else None
    ext = argv[argv.index("--ext") + 1] if "--ext" in argv else None
    if "--probe" in argv:
        probe(data, ext)
        return
    variants = argv[argv.index("--variants") + 1].split(",") if "--variants" in argv else PILOT
    stop = argv[argv.index("--stop") + 1] if "--stop" in argv else None
    outfits = argv[argv.index("--outfits") + 1].split(",") if "--outfits" in argv else PILOT_OUTFITS
    m = Mpfb(data, ext)
    results = {v: build_variant(m, v, outfits, stop) for v in variants}
    if stop:
        return
    write_manifest(results)


if __name__ == "__main__":
    main()
