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
BUDGET = dict(lod0=20500, outfit=14000, body=5600, garments=7000, hair=3400, head=1500, tex=1024)

# ------------------------------------------------------------------------------------------------------------------
# variants: MakeHuman macro values (0..1).  age: 0.1875 = 11 years, 0.5 = 25, 1.0 = 90.  Heights are exact (the body is
# scaled to them after the macros).  race = african / asian / caucasian (sums to 1).
# ------------------------------------------------------------------------------------------------------------------
VARIANTS = {
    "m1": dict(sex="m", height=1.80, macro=dict(gender=1.0, age=0.50, muscle=0.60, weight=0.50, proportions=0.60,
                                                race=(0.10, 0.10, 0.80)),
               skin="skins/young_caucasian_male", hair="hair/short04", brows="eyebrows/eyebrow002",
               eye_mat="eyes/materials/brown.mhmat"),
    "m2": dict(sex="m", height=1.76, macro=dict(gender=1.0, age=0.62, muscle=0.45, weight=0.65, proportions=0.50,
                                                race=(0.80, 0.05, 0.15)),
               skin="skins/middleage_african_male", hair="hair/culturalibre_hair_02", brows="eyebrows/eyebrow009",
               eye_mat="eyes/materials/brown.mhmat"),
    "m3": dict(sex="m", height=1.90, macro=dict(gender=1.0, age=0.76, muscle=0.40, weight=0.55, proportions=0.55,
                                                race=(0.05, 0.75, 0.20)),
               skin="skins/middleage_asian_male", hair="hair/short02", brows="eyebrows/eyebrow004",
               eye_mat="eyes/materials/brownlight.mhmat"),
    "f1": dict(sex="f", height=1.68, macro=dict(gender=0.0, age=0.50, muscle=0.50, weight=0.45, proportions=0.60,
                                                race=(0.10, 0.10, 0.80)),
               skin="skins/young_caucasian_female", hair="hair/toigo_curled_under_bob", brows="eyebrows/eyebrow003",
               eye_mat="eyes/materials/green.mhmat", lid_rest=10.0),
    "f2": dict(sex="f", height=1.62, macro=dict(gender=0.0, age=0.60, muscle=0.55, weight=0.60, proportions=0.50,
                                                race=(0.75, 0.05, 0.20)),
               skin="skins/middleage_african_female", hair="hair/afro01", brows="eyebrows/eyebrow001",
               eye_mat="eyes/materials/brown.mhmat"),
    "f3": dict(sex="f", height=1.74, macro=dict(gender=0.0, age=0.70, muscle=0.40, weight=0.50, proportions=0.55,
                                                race=(0.05, 0.75, 0.20)),
               skin="skins/middleage_asian_female", hair="hair/rehmanpolanski_hair_bun_brown", brows="eyebrows/eyebrow006",
               eye_mat="eyes/materials/brownlight.mhmat"),
    "c1": dict(sex="m", height=1.38, child=True, macro=dict(gender=1.0, age=0.17, muscle=0.50, weight=0.50,
                                                             proportions=0.50, race=(0.20, 0.20, 0.60)),
               skin="skins/young_caucasian_male", hair="hair/short03", brows="eyebrows/eyebrow005",
               eye_mat="eyes/materials/green.mhmat"),
    "c2": dict(sex="f", height=1.34, child=True, macro=dict(gender=0.0, age=0.16, muscle=0.50, weight=0.45,
                                                             proportions=0.50, race=(0.30, 0.30, 0.40)),
               skin="skins/young_african_female", hair="hair/bob02", brows="eyebrows/eyebrow007",
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
        who=["off duty"], look="jeans / tee: a tee in the person's colour over the waistband, dark cargo trousers, sneakers",
        m=[("clothes/elvs_crude_t-shirt_male", "tint:ClothTint"), ("clothes/cortu_cargo_pants", "own"),
           ("clothes/shoes06", "own")],
        f=[("clothes/joepal_crude_t-shirt_female", "tint:ClothTint"), ("clothes/cortu_cargo_pants", "own"),
           ("clothes/shoes05", "own")]),
    "casual_b": dict(
        who=["off duty", "social events"], look="dress / jacket: a knit sweater and wool trousers (men), a shift dress "
                                                "and flats (women); the knit and the dress take the person's colour",
        m=[("clothes/toigo_fisherman_sweater", "tint:ClothTint"), ("clothes/toigo_wool_pants", "own"),
           ("clothes/shoes01", "own")],
        f=[("clothes/toigo_shift_dress", "tint:ClothTint"), ("clothes/toigo_flats", "own")]),
    "casual_c": dict(
        who=["off duty", "sport"], look="sport wear: a sports tee with jeans and sneakers (men), a sports top and leggings "
                                          "with sneakers (women)",
        m=[("clothes/male_casualsuit02", "own"), ("clothes/shoes06", "own")],
        f=[("clothes/female_sportsuit01", "own"), ("clothes/shoes06", "own")]),
    "swimwear": dict(
        who=["pool"], look="modest one-piece (women, girls); swim trunks with a tee (men, boys); the person's colour",
        m=[("gen:trunks", "tint:ClothTint"), ("clothes/elvs_crude_t-shirt_male", "tint:ClothTint")],
        f=[("gen:swimsuit", "tint:ClothTint")]),
    "school": dict(
        who=["children at the academy"], look="school uniform: a white polo, grey wool trousers and black shoes (boys); a "
                                                 "navy pinafore dress and flats (girls)",
        m=[("clothes/namuhekam_male_polo_shirt", "tint:SchoolWhite"), ("clothes/toigo_wool_pants", "tint:SchoolGrey"),
           ("clothes/shoes01", "own")],
        f=[("clothes/toigo_shift_dress", "tint:SchoolNavy"), ("clothes/toigo_flats", "own")]),
}
# per-variant garments (variety: 110 people, 6 bodies): outfit -> garment list, replacing the sex default
VARIANT_OUTFITS = {
    "m2": {"casual_a": [("clothes/namuhekam_male_polo_shirt", "tint:ClothTint"), ("clothes/toigo_wool_pants", "own"),
                         ("clothes/shoes04", "own")]},
    "m3": {"casual_b": [("clothes/male_casualsuit05", "own"), ("clothes/shoes02", "own")]},
    "f2": {"casual_b": [("clothes/toigo_halter_dress_knee_length", "tint:ClothTint"), ("clothes/toigo_ballet_flats", "own")]},
    "f3": {"casual_a": [("clothes/toigo_turtleneck_halter_top", "tint:ClothTint"), ("clothes/cortu_cargo_pants", "own"),
                         ("clothes/shoes05", "own")]},
}
ADULT_OUTFITS = ["uniform", "casual_a", "casual_b", "casual_c", "swimwear"]
CHILD_OUTFITS = ["school", "casual_a", "casual_b", "swimwear"]
PILOT_OUTFITS = ADULT_OUTFITS


def garments_of(v, oid):
    spec = VARIANTS[v]
    return VARIANT_OUTFITS.get(v, {}).get(oid) or OUTFITS[oid][spec["sex"]]


TINT_BASE = {"SuitAccent": (1.0, 1.0, 1.0), "Coverall": (0.34, 0.38, 0.43), "ClothTint": (1.0, 1.0, 1.0),
             "SchoolWhite": (0.92, 0.92, 0.90), "SchoolGrey": (0.36, 0.37, 0.40), "SchoolNavy": (0.11, 0.15, 0.30)}

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
            ang = {"1": 20.0, "2": 34.0, "3": 28.0}.get(seg, 0.0) * (0.55 if digit == "1" else 1.0)
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


def decimate(ob, target_tris, weight_at=None, edges=True):
    """Collapse decimation to target_tris; open edges are protected (weight 0), and weight_at(p) (0 = keep .. 1 =
    free) protects a region (the face)."""
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
    for vv in (bm.verts if edges else []):
        if any(e.is_boundary for e in vv.link_edges):
            edge_v.add(vv.index)
            for e in vv.link_edges:
                edge_v.add(e.other_vert(vv).index)
    bm.free()
    if weight_at is None:
        g.add([i for i in range(len(ob.data.vertices)) if i not in edge_v], 1.0, "REPLACE")
    else:
        mw = ob.matrix_world
        for vv in ob.data.vertices:
            if vv.index not in edge_v:
                g.add([vv.index], weight_at(mw @ vv.co), "REPLACE")
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


def texture(path, name, size=BUDGET["tex"], detail=False, bake_rgb=None, alpha_blur=0, alpha_dense=0.0):
    """Load, shrink to <= size, optionally make a tint detail map (the image divided by its mean colour), save PNG."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    if max(w, h) > size:
        img.scale(size * w // max(w, h), size * h // max(w, h))
    if detail:
        import numpy as np
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        lum = px[:, :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
        solid = (px[:, 3] > 0.5) & (lum > 0.12)             # the mean of the visible pixels (no black padding)
        mean = (px[solid, :3] if solid.any() else px[:, :3]).mean(axis=0) + 1e-4
        lm = float(mean @ np.array([0.30, 0.59, 0.11]))
        norm = mean ** 0.72 * lm ** 0.28                    # 28 % of the texture's own hue stays (warmth)
        px[:, :3] = np.clip(px[:, :3] / norm * 0.82, 0.0, 1.0)
        if bake_rgb is not None:                            # a plain (untinted) material: its colour goes in here
            px[:, :3] = np.clip(px[:, :3] * np.array(bake_rgb, dtype=np.float32), 0.0, 1.0)
        if alpha_blur:
            w_, h_ = img.size
            px = blur_alpha(px, w_, h_, alpha_blur)
        if alpha_dense:
            # brows: a 1 px max filter and an alpha boost, so the thin hairs survive the 0.5 alpha clip (full brows,
            # not dotted lines)
            w_, h_ = img.size
            a = px[:, 3].reshape(h_, w_)
            a = np.maximum.reduce([a, np.roll(a, 1, 0), np.roll(a, -1, 0), np.roll(a, 1, 1), np.roll(a, -1, 1)])
            px[:, 3] = np.clip(a.ravel() * alpha_dense, 0.0, 1.0)
        img.pixels = px.ravel().tolist()
    os.makedirs(OUT_TEX, exist_ok=True)
    out = os.path.join(OUT_TEX, name + ".png")
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    return img


NORMAL_MAPS = False     # RENDER's people shader samples albedo only (shaders/npc_skin.gdshaderinc): no normal maps


def plain_material(name, base=None, alpha=None, normal=None, rough=0.6, color=(1, 1, 1), cutoff=0.5):
    if not NORMAL_MAPS:
        normal = None
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


TEX_SIZE = {"Skin": 1024, "Hair": 1024, "Eye": 256, "Hair_brows": 512, "Hair_lashes": 256, "Teeth": 128}
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
               alpha_blur=0, alpha_dense=1.35 if name == "Hair_brows" else 0.0)
    nrm = tex("normalmapTexture", "normal", size=TEX_NORMAL) if NORMAL_MAPS else None
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
    hair_f = m.asset(os.environ.get("NPC_HAIR_" + v.upper(), spec["hair"]))
    parts["hair"] = (m.add_asset(base, hair_f, "Hair"), hair_f)
    garments = {}
    for oid in outfits:
        garments[oid] = []
        for folder, mat in garments_of(v, oid):
            if folder.startswith("gen:"):
                garments[oid].append((None, folder, mat, []))       # built after the pose (people_uniform)
                continue
            f = m.asset(folder)
            before = {md.name for md in base.modifiers}
            ob = m.add_asset(base, f, "Clothes")
            masks = [md.vertex_group for md in base.modifiers if md.name not in before and md.type == "MASK"]
            garments[oid].append((ob, f, mat, masks))
    objs = [p[0] for p in parts.values()] + [g[0] for gs in garments.values() for g in gs if g[0] is not None]
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
        for k, g in enumerate(garments[oid]):
            if g[0] is None and g[1] in ("gen:trunks", "gen:swimsuit"):
                ob = PU.make_trunks(base, J) if g[1] == "gen:trunks" else PU.make_swimsuit(base, J)
                ob.name = ob.data.name = "%s_%s" % (g[1][4:], oid)
                garments[oid][k] = (ob, g[1], g[2], [])
                objs.append(ob)
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
            pass                                      # untucked tees (2026-10-01): no hem extension
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
    for a in addon_objs.values():                       # add-ons: coats <= 3000 triangles, the others <= 1600
        cap = 2150 if a.name.split(".")[0] in ("Addon_labcoat", "Addon_tunic", "Addon_jacket") else 1500
        if ntris(a) > cap:
            decimate(a, cap)
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
                                      bake_rgb=(0.60,) * 3 if hairy else None)
        replace_materials(ob, mat)
        if kind == "teeth":
            decimate(ob, 700)
        head_parts.append(ob)
    head = join(head_parts, "Head_%s" % v)
    tris[head.name] = ntris(head)
    hob, hf = parts["hair"]
    soften_hair(hob, J, next(iter(bodies.values())))
    replace_materials(hob, material_from_mhmat(mhclo_material(hf), "Hair", os.path.basename(os.path.dirname(hf)),
                                               detail=True, alpha=True))
    hob.name = hob.data.name = "Hair_%s" % v
    tris[hob.name] = decimate(hob, BUDGET["hair"])
    for oid, gs in garments.items():
        body = bodies[oid]
        replace_materials(body, skin_mat)
        is_shell = any(g[2] == "shell" for g in gs)
        if is_shell:
            nk = remove_inside_coverall(body, J)
            nk += remove_covered(body, [ob for ob, _, m_, _ in gs if m_ != "shell"])
        else:
            nk = remove_covered(body, [ob for ob, _, _, _ in gs])
        # between garments: an inner layer loses what an outer layer covers (tops over trousers over shoes)
        for ob, f, _, _ in gs:
            outer = [o2 for o2, f2, _, _ in gs if garment_layer(f2) > garment_layer(f)]
            if outer:
                # boots under the coverall legs: only the part inside the trouser tube moves or goes (above the hem)
                zlim = (J["foot.L"].z + 0.080 + 0.012) if any(o2 is g[0] for g in gs if g[2] == "shell" for o2 in outer) else None
                tuck_under(ob, outer, zmin=zlim)
                remove_covered(ob, outer, zmin=zlim)
        gsum = sum(ntris(ob) for ob, _, m_, _ in gs if m_ != "shell")
        shell_t = sum(ntris(ob) for ob, _, m_, _ in gs if m_ == "shell")
        # V5 section 1: <= 14k triangles per body + outfit at LOD0 (the outfit mesh with its largest add-on set)
        room = BUDGET["outfit"]
        if is_shell:
            room -= max(sum(ntris(addon_objs[a]) for a in PU.DEPARTMENTS[d_]["addons"] if a in addon_objs)
                        for d_ in PU.DEPARTMENTS)
        body_t = min(ntris(body), BUDGET["body"] - (600 if is_shell else 0))
        face_z = J["neck"].z + 0.02
        tb = decimate(body, body_t, weight_at=lambda p: 0.30 if p.z > face_z else (0.55 if p.z > face_z - 0.28 else 0.9))
        g_budget = max(600, room - tb - shell_t)
        print("  %s %s: %d covered skin vertices removed" % (v, oid, nk))
        pieces = [body]
        for ob, f, mat, _ in gs:
            if mat == "shell":
                uniform_materials(ob, v)                # built to its own budget (clean edges: no decimation)
                pieces.append(ob)
                continue
            if f.startswith("gen:"):
                cb, cn = canvas_textures()
                nm = "%s_%s" % (mat[5:], f[4:])
                mm = bpy.data.materials.get(nm) or plain_material(nm, base=cb, normal=cn, rough=0.55)
            elif mat.startswith("tint:"):
                nm = mat[5:]
                plain = nm not in ("SuitAccent", "ClothTint")          # the game tints only these two
                gname = os.path.basename(os.path.dirname(f))
                mname = nm + "_" + gname if nm == "ClothTint" else nm     # RENDER matches the prefix
                mm = bpy.data.materials.get(mname) or material_from_mhmat(
                    mhclo_material(f), mname, gname, detail=True, bake_rgb=TINT_BASE.get(nm) if plain else None)
            else:
                nm = "Cloth_" + os.path.basename(os.path.dirname(f))
                mm = bpy.data.materials.get(nm) or material_from_mhmat(mhclo_material(f), nm,
                                                                       os.path.basename(os.path.dirname(f)))
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
    PA.LID_REST = spec.get("lid_rest", 5.0)                   # relaxed upper lids (CRITIC round 40: f1 stare)
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
    lod1 = export_lod1(v, rig)
    tris.update({"LOD1_" + k: n for k, n in lod1.items()})
    print("  %s: %s  %.1f s" % (v, tris, time.time() - t0))
    return dict(tris=tris, clips=meta, scale=s_, path=path, outfits=list(garments), addons=sorted(tris_addons(tris)),
                sources=dict(skin=spec["skin"], hair=spec["hair"], brows=spec["brows"], eyes=spec["eye_mat"],
                             outfits={o: [g[0] for g in garments_of(v, o)] for o in garments}))


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


def soften_hair(ob, J, skin=None):
    """Hair below the jaw rests on the neck and the shoulders: at the tips the head weight becomes head 10 %, neck 50 %,
    chest 40 % (the collar moves with the chest, so the tips stay outside it)."""
    z_top, z_low = J["jaw"].z + 0.02, J["neck"].z
    gh, gn, gc = (ob.vertex_groups.get(n) for n in ("head", "neck", "chest"))
    if gh is None:
        return
    z_min = J["neck"].z + 0.062                         # trim: no hair below the neck base + 6.2 cm (the collar)
    for v in ob.data.vertices:
        if v.co.z < z_min:
            v.co.z = z_min - 0.004 * (z_min - v.co.z) / max(1e-3, z_min - v.co.z + 0.02)
    if skin is not None:                                 # below the jaw: 1.2 cm clear of the neck and nape skin
        from mathutils.bvhtree import BVHTree
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(skin.data)
        bm.transform(skin.matrix_world)
        tree = BVHTree.FromBMesh(bm)
        bm.free()
        for v in ob.data.vertices:
            if v.co.z > J["jaw"].z + 0.01:
                continue
            hit = tree.find_nearest(v.co, 0.03)
            if hit[0] is None:
                continue
            s_ = (v.co - hit[0]).dot(hit[1])
            if s_ < 0.012:
                v.co = v.co + hit[1] * (0.012 - s_)
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


LOD1 = dict(outfit=1900, hair=520, head=160, addon=340, coat=420)


def export_lod1(v, rig):
    """people_<v>_lod1.glb: the same skeleton and mesh names, no clips (RENDER samples the LOD0 file's clips).
    Per person <= 3k triangles: Outfit 1.9k + its add-ons + Head (eyes and brows only) + Hair.  Called after the
    LOD0 export: the meshes are decimated in place."""
    import bmesh
    out = {}
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        nm = o.name.split(".")[0]
        if nm.startswith("Head_"):
            bm = bmesh.new()
            bm.from_mesh(o.data)
            mats = [m.name.split(".")[0] if m else "" for m in o.data.materials]
            kill = [f for f in bm.faces if mats[f.material_index] in ("Hair_lashes", "Teeth")]
            bmesh.ops.delete(bm, geom=kill, context="FACES")
            bm.to_mesh(o.data)
            bm.free()
            target = LOD1["head"]
        elif nm.startswith("Hair_"):
            target = LOD1["hair"]
        elif nm.startswith("Outfit_"):
            target = LOD1["outfit"]
        elif nm in ("Addon_labcoat", "Addon_tunic", "Addon_jacket"):
            target = LOD1["coat"]
        else:
            target = LOD1["addon"]
        out[nm] = decimate(o, target, edges=False)
    path = os.path.join(N.MODEL_DIR, "people_%s_lod1.glb" % v)
    N.reset_pose(rig)
    N.export_glb_skinned(path, animations=False)
    externalize_images(path)
    print("  %s LOD1: %s" % (v, out))
    return out


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
    base_p = os.path.join(OUT_TEX, "uniform_canvas3_base.png")
    nrm_p = os.path.join(OUT_TEX, "uniform_canvas3_normal.png")
    if not (os.path.exists(base_p) and os.path.exists(nrm_p)):
        os.makedirs(OUT_TEX, exist_ok=True)
        n = 256
        u = np.arange(n)[None, :] / n
        v = np.arange(n)[:, None] / n
        rng = np.random.default_rng(7)

        def blur(a, r):
            for _ in range(2):
                for ax in (0, 1):
                    a = sum(np.roll(a, k, axis=ax) for k in range(-r, r + 1)) / (2 * r + 1)
            return a
        mottle = blur(rng.random((n, n)), 12)
        mottle = (mottle - mottle.mean()) / (mottle.std() + 1e-6)
        fibre = blur(rng.random((n, n)), 1)
        fibre = (fibre - fibre.mean()) / (fibre.std() + 1e-6)
        twill = np.sin(2 * np.pi * 16 * (u + v))                  # a soft diagonal twill, 16 lines per tile
        h = twill + 0.25 * blur(rng.random((n, n)), 3) * 4.0
        col = 0.82 + 0.012 * mottle + 0.010 * fibre
        img = bpy.data.images.new("uniform_canvas3_base", n, n, alpha=False)
        px = np.ones((n, n, 4), dtype=np.float32)
        px[:, :, 0] = px[:, :, 1] = px[:, :, 2] = col
        img.pixels = px.ravel().tolist()
        img.filepath_raw = base_p
        img.file_format = "PNG"
        img.save()
        gx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
        gy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
        nz = np.ones_like(h)
        nx, ny = -gx * 0.10, -gy * 0.10
        L = np.sqrt(nx * nx + ny * ny + nz * nz)
        img2 = bpy.data.images.new("uniform_canvas3_normal", n, n, alpha=False)
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
        for nm_ in ("UniformBase", "SuitAccent", "Zip", "Leather", "Metal", "Apron", "Armor", "Rank", "Coat"):
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
            "Apron": plain_material("Apron", normal=cn, rough=0.85, color=(0.86, 0.86, 0.83)),
            "Armor": plain_material("Armor", color=(0.16, 0.17, 0.19), rough=0.5),
            "Rank": plain_material("Rank", color=(0.80, 0.64, 0.24), rough=0.35),
            "Coat": plain_material("Coat", normal=cn, rough=0.8, color=(0.88, 0.89, 0.88)),
        })
    for i, m in enumerate(ob.data.materials):
        base = m.name.split(".")[0].replace("_placeholder", "") if m else "UniformBase"
        if base in _UNI_MATS:
            ob.data.materials[i] = _UNI_MATS[base]


def garment_layer(mhclo):
    if mhclo.startswith("gen:"):
        return 2 if mhclo == "gen:trunks" else 3
    """Our layer order (the packs give most garments the same z_depth): tops 3, trousers / skirts 2, shoes 1."""
    n = os.path.basename(os.path.dirname(mhclo)).lower()
    if any(k in n for k in ("shirt", "t-shirt", "tee", "polo", "top", "sweater", "jacket", "suit", "dress")):
        return 3
    if any(k in n for k in ("pants", "jeans", "trousers", "skirt", "shorts")):
        return 2
    return 1


def tuck_under(inner, outers, reach=0.03, gap=0.004, zmin=None):
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
        if zmin is not None and p.z < zmin:
            continue
        for t in trees:
            hit = t.ray_cast(p + n * 0.002, -n, reach)[0]
            if hit is not None:
                v.co = inner.matrix_world.inverted() @ (hit - n * gap)
                moved += 1
                break
    bm.to_mesh(inner.data)
    bm.free()
    return moved


def remove_inside_coverall(body, J):
    """The coverall hides everything from 3 cm under its neckline to 4.5 cm up the sleeve from the wrist cut and
    down to 3 cm above the trouser hem (people_uniform cut planes): those body vertices go (a rule, not rays)."""
    import bmesh
    nc = Vector((J["neck"].x, 0.0, J["neck"].z - 0.012))
    no = Vector((0.12, 0.0, 1.0)).normalized()
    hem = J["foot.L"].z + 0.080
    bm = bmesh.new()
    bm.from_mesh(body.data)
    kill = []
    for v in bm.verts:
        p = body.matrix_world @ v.co
        if ((p - nc).dot(no) > -0.030 and Vector((p.x - nc.x, p.y, 0)).length < 0.095) or (p - nc).dot(no) > 0.02 \
                or p.z < hem + 0.030:
            continue
        hand = False
        for s in ("L", "R"):
            a, b = J["forearm." + s], J["hand." + s]
            d = b - a
            t = (p - a).dot(d) / d.length_squared
            if t > 1.0 - 0.063 / d.length and (p - (a + d * min(t, 1.0))).length < 0.16:
                hand = True
        if not hand:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    return len(kill)


def remove_covered(body, garments, reach=0.03, margin=0.05, zmin=None):
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
        if zmin is not None and p.z < zmin:
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
    doc["version"] = "5.0-mpfb"
    doc["skeleton"] = dict(bones=list(N.BONE_NAMES), face_bones=list(N.BONE_NAMES[24:]),
                           note=("The v3 skeleton (24 bones, the same names and hierarchy) plus face bones under head: "
                                 "jaw (lower face), lids (upper lids: blink), lids_low (lower lids), brow.L/R, mouth.L/R "
                                 "(corners).  Expressions (smile, laugh, frown, surprise) are keyed in the clips.  Joint "
                                 "positions per body (MPFB).  Children use the same skeleton (their own joint positions)."))
    doc["status"] = ("FULL SET (MPFB): 6 adults (m1 m2 m3 f1 f2 f3) and 2 children (c1 c2); every outfit of V5 section 1; "
                     "LOD0 in people_<v>.glb, LOD1 in people_<v>_lod1.glb.  Bodies from MPFB (MakeHuman, CC0 assets) "
                     "skinned to OUR skeleton (route A).")
    variants = doc.get("variants", {})
    for v, r in results.items():
        spec = VARIANTS[v]
        outs = {}
        for o in r["outfits"]:
            if OUTFITS[o].get("generator") == "coverall":
                for dept, d in PU.DEPARTMENTS.items():
                    outs[dept] = dict(mesh="Outfit_%s" % o, addons=["Addon_%s" % a for a in d["addons"]],
                                      base_rgb=[round(x, 3) for x in d["base"]])
                    if "accent" in d:
                        outs[dept]["accent_rgb"] = [round(x, 3) for x in d["accent"]]
            else:
                outs[o] = "Outfit_%s" % o
        on_screen, lod1 = {}, {}
        T = r["tris"]
        for o, e in outs.items():
            mesh = e if isinstance(e, str) else e["mesh"]
            add = [] if isinstance(e, str) else e["addons"]
            on_screen[o] = dict(outfit_and_addons=T[mesh] + sum(T.get(a, 0) for a in add),
                                with_head_and_hair=T[mesh] + sum(T.get(a, 0) for a in add) + T["Head_%s" % v] +
                                T["Hair_%s" % v])
            lod1[o] = (T.get("LOD1_" + mesh, 0) + sum(T.get("LOD1_" + a, 0) for a in add) +
                       T.get("LOD1_Head_%s" % v, 0) + T.get("LOD1_Hair_%s" % v, 0))
        variants[v] = dict(sex=spec["sex"], child=bool(spec.get("child")), height_m=spec["height"],
                           scale=round(r["scale"], 4), file="people_%s.glb" % v, lod1_file="people_%s_lod1.glb" % v,
                           head="Head_%s" % v, hair="Hair_%s" % v, outfits=outs, addons=r["addons"],
                           triangles={k: n for k, n in T.items() if not k.startswith("LOD1_")},
                           triangles_lod1={k[5:]: n for k, n in T.items() if k.startswith("LOD1_")},
                           triangles_on_screen=on_screen, triangles_on_screen_lod1=lod1,
                           look=dict(skin_tone_hint=LOOK_HINT.get(v)), source="MPFB 2.0.17 + CC0 MakeHuman assets",
                           assets=r["sources"])
    doc["variants"] = {k: variants[k] for k in VARIANTS if k in variants}
    doc["outfits"] = {o: dict(who=d["who"], look=d["look"]) for o, d in PU.DEPARTMENTS.items()}
    for o, d in OUTFITS.items():
        if not d.get("generator"):
            doc["outfits"][o] = dict(who=d["who"], look=d["look"])
    doc["addons"] = {
        "Addon_toolbelt": "belt, buckle and three pouches (engineering, security)",
        "Addon_apron": "white bib apron with neck straps and ties (food)",
        "Addon_vest": "armoured vest with shoulder straps (security)",
        "Addon_labcoat": "white knee-length lab coat, open below the waist; collar and sleeve bands are SuitAccent (science)",
        "Addon_tunic": "white hip-length tunic; collar and sleeve bands are SuitAccent (medical)",
        "Addon_jacket": "tailored hip-length jacket with a stand collar; body is UniformBase, collar and cuff bands "
                        "SuitAccent (command)",
        "Addon_rank1": "shoulder boards (UniformBase) with 1 gold bar (Rank); fits any uniform, with or without a coat",
        "Addon_rank2": "as rank1 with 2 bars", "Addon_rank3": "as rank1 with 3 bars (commander default)"}
    draw = doc.get("draw", {})
    draw["per_person"] = ("Draw Head_<variant> (eyes, brows, lashes, teeth), Hair_<variant> and ONE Outfit_<mesh> (the "
                          "body skin it leaves visible + its garments) + the outfit's Addon_* list.  Hide every other "
                          "Outfit_* and Addon_*.  Beyond 12 m draw the same names from people_<v>_lod1.glb (same "
                          "skeleton and bind; it has no clips: use the LOD0 file's clips).")
    draw["materials"] = {
        "Skin*": "tint like v3 Skin (mode 2); the texture is a detail map around 0.82 that keeps 28 % of the skin hue",
        "Hair*": "Hair, Hair_brows, Hair_lashes: tint like v3 Hair (mode 3); alpha MASK (clip 0.5); the texture "
                 "multiplies",
        "UniformBase*": "the outfit's base_rgb (mode 6): the coverall, the jacket body, the rank boards",
        "SuitAccent*": "department colour (mode 1): the bands on the coverall and the coat collars and cuffs; "
                       "accent_rgb in the outfit entry overrides it (prison)",
        "ClothTint*": "per-person clothes colour (mode 5); several garments: ClothTint_<garment> (match the prefix)",
        "Coat, Apron, Armor, Leather, Metal, Zip, Rank": "plain (colour baked)",
        "School*": "plain (school uniform colours baked)", "Eye": "plain, textured", "Teeth": "plain",
        "Cloth_*": "plain, textured (the garment's own look)"}
    draw["lod"] = ("LOD0 (people_<v>.glb): outfit + add-ons <= 14k triangles; head + hair about 4-6k more.  LOD1 "
                   "(people_<v>_lod1.glb, beyond 12 m): <= 3k per person including head and hair.")
    doc["draw"] = draw
    clips = {}
    for v, r in results.items():
        for name, mt in r["clips"].items():
            clips.setdefault(name, mt)
    old = doc.get("clips", {})
    old.update(clips)
    doc["clips"] = old
    doc["furniture"] = PA.furniture_json() if hasattr(PA, "furniture_json") else dict(bar_stool=PA.BAR_STOOL)
    doc["textures"] = dict(note=("external PNGs in assets/models/people_tex_shared/ (one file per texture, shared by "
                                 "every variant that uses it); sources in assets/models/people_tex/ (.gdignore)"))
    doc["credits"] = ("MakeHuman / MPFB assets: CC0 packs (makehuman_system_assets, skins01, skins02, hair01, shirts01, "
                      "pants01, suits01, suits02, shoes01, dress01, eyebrows01, eyelashes01)")
    with open(MAN + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(MAN + ".tmp", MAN)
    with open(PB.PAIRS + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(PA.pairs_json(), fh, indent=1)
    os.replace(PB.PAIRS + ".tmp", PB.PAIRS)


LOOK_HINT = {"m1": 3, "m2": 0, "m3": 2, "f1": 2, "f2": 1, "f3": 3, "c1": 4, "c2": 1}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    data = argv[argv.index("--data") + 1] if "--data" in argv else None
    ext = argv[argv.index("--ext") + 1] if "--ext" in argv else None
    if "--probe" in argv:
        probe(data, ext)
        return
    variants = argv[argv.index("--variants") + 1].split(",") if "--variants" in argv else PILOT
    stop = argv[argv.index("--stop") + 1] if "--stop" in argv else None
    given = argv[argv.index("--outfits") + 1].split(",") if "--outfits" in argv else None
    m = Mpfb(data, ext)
    results = {v: build_variant(m, v, given or (CHILD_OUTFITS if VARIANTS[v].get("child") else ADULT_OUTFITS), stop)
               for v in variants}
    if stop:
        return
    write_manifest(results)


if __name__ == "__main__":
    main()
