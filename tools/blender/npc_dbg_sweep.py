import sys, os, itertools
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_clipcheck as CC
import people_clips as PC
bodies = ["m1", "m2", "m3", "f1", "f2", "f3", "c1", "c2"]
for out, hx, hy in itertools.product((0.14, 0.22, 0.30), (-0.30, -0.25, -0.20), (0.18, 0.24)):
    PC.HAND_OUT, PC.HR_X, PC.HR_Y = out, hx, hy
    PC._CACHE.clear()
    w = (0.0, "")
    for b in bodies:
        rows = CC.check(b, {"sleep_turn"}, verbose=False)
        if rows[0][2][0] > w[0]:
            w = (rows[0][2][0], b + " " + rows[0][2][1])
    print("SWEEP out %.2f hx %.2f hy %.2f worst %.1f mm %s" % (out, hx, hy, w[0] * 1000, w[1]))
