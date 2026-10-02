import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N
import people_mpfb as PM
import npc_anims as A
import people_clips as PC
for nm in ("wave_keys", "punch_keys", "slap_keys", "hit_react_keys", "shout_keys", "kiss_brief_keys", "handshake_keys", "teach_keys"):
    fn, n = getattr(PC, nm)()
    print("KEYS", nm, n, [round(k[0], 2) for k in PC._LAST[0]])
