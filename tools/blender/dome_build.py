"""
Frontier Habitat 5.0 - builds every super dome file and writes assets/models/dome_manifest.json. ART-B.
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_build.py
"""
import os
import sys
import json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dome_common as D                                    # noqa: E402
import dome_shell                                          # noqa: E402
import dome_floors                                         # noqa: E402
import dome_atrium                                         # noqa: E402
import dome_stages                                         # noqa: E402
import dome_l2                                             # noqa: E402


def manifest():
    rep = json.load(open(D.REPORT_JSON, encoding="utf-8"))
    files = []
    for key in ["dome_shell", "dome_floor1", "dome_floor2", "dome_floor3", "dome_floor4", "dome_floor5", "dome_atrium",
                "dome_scaffold"]:
        r = rep.get(key, {})
        files.append({"file": key + ".glb", "tris": r.get("tris"), "top_nodes": sorted((r.get("tris_by_top") or {}).keys())})
    floors = []
    for n in range(1, 6):
        floors.append({"floor": n, "z": D.FLOOR_Z[n - 1], "ceiling": round(dome_floors.ceil_z(n), 3),
                       "group": "Floor_%d" % n, "file": "dome_floor%d.glb" % n,
                       "use": "shops and businesses" if n <= 2 else "accommodation"})
    m = {
        "version": "5.0-pilot",
        "origin": "dome centre on the ground; Blender Z up = Godot Y up; all files share it (no offsets)",
        "radius": D.R_BASE, "height": D.DOME_H, "size_label": "XXXXL",
        "ring": {"inner": D.R_IN, "outer": D.R_OUT, "front": D.R_FRONT, "sectors": D.N_SEC, "sector_deg": D.SEC,
                 "passages_L1": list(D.PASSAGES), "lift_sectors": list(D.LIFT_SECTORS)},
        "floors": floors,
        "roof": {"z": D.ROOF_Z, "group": "Floor_Roof", "file": "dome_floor5.glb"},
        "files": files,
        "groups": {
            "Foundation": "stage foundation", "Gates": "stage structure (12 gates, Anchor_Gate_<i> outside, Anchor_GateIn_<i> inside)",
            "Floor_<n>/Struct_<n>": "stage level_<n> structure", "Floor_<n>/Shell_<n>, Lamps_<n>": "fit-out",
            "Floor_1/Venue_<id>, VenueLamps_<id>": "fit-out of that venue", "Dome": "stage dome glass",
            "Atrium, Promenade": "fit-out", "Lifts": "structure (shafts)", "Lift_<i>": "cabs, move along Z to extras.stops",
        },
        "build_stages": [
            {"stage": "foundation", "show": ["Foundation", "Site", "Crane"]},
            {"stage": "level_1", "show": ["+ Floor_1/Struct_1", "Gates", "Lifts", "Scaffold_1"]},
            {"stage": "level_2", "show": ["+ Floor_2/Struct_2", "Scaffold_2"], "hide": ["Scaffold_1"]},
            {"stage": "level_3", "show": ["+ Floor_3/Struct_3", "Scaffold_3"], "hide": ["Scaffold_2"]},
            {"stage": "level_4", "show": ["+ Floor_4/Struct_4", "Scaffold_4"], "hide": ["Scaffold_3"]},
            {"stage": "level_5", "show": ["+ Floor_5/Struct_5", "Floor_Roof/Roof_Struct", "Scaffold_5"], "hide": ["Scaffold_4"]},
            {"stage": "dome_frame", "show": ["+ Dome/Dome_Frame"], "hide": ["Scaffold_5", "Crane"]},
            {"stage": "dome_glass", "show": ["+ Dome/Dome_Glass", "Dome/Dome_Lights"]},
            {"stage": "fitout", "show": ["+ Shell_<n>, Lamps_<n>, Unit_<n>_<s>, Atrium, Promenade, Roof_Garden, Roof_Lamps"],
             "hide": ["Site"]},
            {"stage": "fitout_<venue>", "show": ["+ Venue_<id>, VenueLamps_<id> (one per venue, in any order)"]}],
        "venues_L1": [{"id": v[0], "label": v[1], "sectors": [v[2], v[3]], "sign": v[4]} for v in dome_floors.L1_VENUES],
        "venues_L2": [{"id": v[0], "label": v[1], "sectors": [v[2], v[3]], "sign": v[4]} for v in dome_l2.L2_VENUES],
        "units": {"L3": "24 hotel rooms", "L4": "24 standard / family units", "L5": "6 executive units (2 sectors) + 12 hotel rooms",
                  "anchors": "Anchor_Unit_<floor>_<s>, Anchor_Bed_<floor>_<s>_<k> (extras head +Y / -Y mirror), Anchor_Seat_..., Anchor_Desk_..."},
        "anchor_kinds": {
            "Anchor_Venue_<id>": "venue door point in the colonnade, +X into the venue",
            "Anchor_Work_<id>_<k>": "staff stand point", "Anchor_Seat_<id>_<k>": "customer seat / stand point",
            "Anchor_Lift_<i>_<floor>": "lift door on that floor (floor 6 = roof)", "Anchor_Unit_<floor>_<s>": "accommodation unit door",
            "Anchor_Lounger_<k>": "pool lounger (lounge_pool)", "Anchor_Swim_<k>": "in the pool at the water line (swim)",
            "Anchor_SlideTop / Anchor_SlideEnd": "water slide", "Anchor_Lifeguard": "lifeguard chair (sit)",
            "Anchor_Bench_<k>": "benches (sit_bench)", "Anchor_Stage": "event stage centre", "Anchor_Plaza_<k>": "plaza stand points",
            "Anchor_Gate_<i> / Anchor_GateIn_<i>": "the 12 gates, outside and inside", "Anchor_Crown": "dome top",
            "Anchor_Lamp_<floor>_<s>_<k>": "hotel room lamp light point (role lamp, colour, range_m, optional)",
            "Anchor_Bouncer_club_0": "club door bouncer post (adults_only)",
        },
        "anchor_extras": "every anchor has {floor, height}; venue anchors add venue; lift anchors add lift",
    }
    json.dump(m, open(D.MANIFEST, "w", encoding="utf-8"), indent=1)
    print("  manifest:", D.MANIFEST)


def main():
    dome_shell.main()
    sys.argv = [a for a in sys.argv if a != "--"]
    for n in (1, 2, 3, 4, 5):
        lamps = ["Lamps_%d" % n] + ["VenueLamps_%s" % v[0] for v in dome_floors.L1_VENUES + dome_l2.L2_VENUES] + [
            "Roof_Lamps", "ArcadeScreen_PrismShift"]
        D.build_file("dome_floor%d.glb" % n, dome_floors.build_floor(n), ao={"dist": 1.2, "samples": 10, "skip": lamps})
    dome_atrium.main()
    dome_stages.main()
    manifest()


if __name__ == "__main__":
    main()
