"""
Frontier Habitat 5.0 - ART-NPC: the people part of npc_verify on its own (fast, prints to the console, no report).

  NPC_ONLY=m1,f2,suit,pairs blender --background --factory-startup --python tools/blender/npc_verify_people.py

NPC_ONLY: bodies (m1..f3, c1, c2, suit, indoor) and "pairs" for the paired clips; empty = everything.
"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_verify as NV         # noqa: E402
import people_verify as PV      # noqa: E402

RES = []


def check(name, ok, detail="", pending=False, info=False):
    st = "info" if info else ("pending" if pending else ("pass" if ok else "FAIL"))
    RES.append(st)
    print("%s | %s | %s" % (st, name, detail))


PV.run(check, NV.gltf_facts)
print("SUMMARY %d checks, %d FAIL" % (len(RES), RES.count("FAIL")))
