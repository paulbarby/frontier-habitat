"""Self-test of the desk and seat rule (Paul 2026-10-01: "NPCs sit inside the desk ... desks face into each other").

Builds the research lab M in memory (no export) and proves that interior_kit.check_desk_seats
  1. passes on the real room (paired desks, chairs on the open side, seats face the screens),
  2. flags a seat anchor that lies inside a desk top (a desk turned 180 deg, so the chair is inside it),
  3. flags a seat whose screens are behind it (a chair turned away from its monitors).
Run:  blender --background --factory-startup --python tools/blender/interior_desk_selftest.py
Prints SELFTEST lines and exits with an error when a case does not behave."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K            # noqa: E402
import rooms_build as RB         # noqa: E402
import interior_rooms as IR      # noqa: E402
import interior_kit as IK        # noqa: E402


def fresh(tid="research_lab", size="m"):
    job = RB.jobs(K.load_buildings(), only=[tid], sizes=[size])[0]
    rm = K.Room(job["tid"], job["size"], job["R"], job["bdef"].get("category", "science"), job["bdef"], single=job["single"])
    rm.variant = job.get("variant")
    rm.tray_scale = RB.tray_scale(job)
    IR.build_room_v3(rm)
    return rm


def main():
    ok = True
    rm = fresh()
    base = IK.check_desk_seats(rm)
    n_seats = len(getattr(rm, "desk_seats", []))
    print("SELFTEST real room: %d desk seats, %d desk bodies, flags %s" % (n_seats, len(rm.desk_bodies), base))
    if base or n_seats < 2:
        print("SELFTEST FAIL: the real room must pass with at least 2 desk seats")
        ok = False
    # 2: a desk turned 180 deg about its own centre puts the chair inside the desk top; emulate by moving the first
    # desk body (cx, cy) onto the first Work anchor
    rm2 = fresh()
    name = rm2.desk_seats[0][0]
    anc = {a[0]: a for a in rm2.anchors}[name]
    cx, cy, hx, hy, yaw = rm2.desk_bodies[0]
    rm2.desk_bodies[0] = (anc[1][0], anc[1][1], 0.40, 0.40, yaw)
    flags2 = IK.check_desk_seats(rm2)
    print("SELFTEST desk moved onto the seat: flags %s" % flags2)
    if not any("inside a desk" in f for f in flags2):
        print("SELFTEST FAIL: a seat inside a desk top was not flagged")
        ok = False
    # 3: the screens behind the seat
    rm3 = fresh()
    name3, (sx, sy) = rm3.desk_seats[0]
    anc3 = {a[0]: a for a in rm3.anchors}[name3]
    ax, ay = anc3[1][0], anc3[1][1]
    rm3.desk_seats[0] = (name3, (2 * ax - sx, 2 * ay - sy))
    flags3 = IK.check_desk_seats(rm3)
    print("SELFTEST screens behind the seat: flags %s" % flags3)
    if not any("does not face" in f for f in flags3):
        print("SELFTEST FAIL: a seat with its screens behind it was not flagged")
        ok = False
    print("SELFTEST RESULT: %s" % ("PASS" if ok else "FAIL"))
    if not ok:
        raise SystemExit(1)


main()
