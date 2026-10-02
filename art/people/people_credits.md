# People: sources and credits

## Bodies, skins, hair, clothes (MPFB 2.0.17 / MakeHuman)

- MPFB 2.0.17 (Blender extension) and the MakeHuman system assets, skins, hair, eyebrows, eyelashes, eyes, teeth and
  clothes packs: CC0 1.0. Downloaded to `D:\Tools\mpfb\` (outside the repo) on 2026-09-30.
- The exported people files (`assets/models/people_*.glb`) are CC0.

## Motion capture

- The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF
  EIA-0196217. (CMU Graphics Lab Motion Capture Database; BVH conversion by B. Hahne, via
  github.com/una-dinosauria/cmu-mocap.) Free for any use.
  - Used in the people files: `walk` (take 143_32) and `run` (take 143_01), retargeted by
    `tools/blender/npc_mocap.py` to our skeleton (feet, ground and loop cleanup).
  - Extracted, not used yet: jog (143_42), idle (140_06), talk_idle (18_08), talk (18_08), talk_gesture_a (19_08),
    sit_idle (114_05), dance_a (141_12), dance_b (113_04).
- Quaternius Universal Animation Library (Standard): CC0 1.0. Downloaded to `D:\Tools\mocap\quaternius\`; not used yet.
- Downloads: by the orchestrator on 2026-10-02 after Paul's approval; files, sizes, SHA-256 and sources in
  `D:\Tools\mocap\MANIFEST.json`.
