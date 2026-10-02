# Animation audit (mocap_test)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | f1 |
|---|---|---|
| idle | sinks 3.7 cm; floats 3.5 cm; snap 11.3 deg/f (shin.R f2) | sinks 1.6 cm; floats 3.5 cm; snap 9.1 deg/f (shin.R f2) |
| sit_idle | slide 1.2 cm (R f8); snap 7.5 deg/f (foot.L f36) | slide 1.3 cm (R f8); snap 7.4 deg/f (foot.L f36) |
| talk_idle | snap 6.4 deg/f (chest f70) | floats 1.0 cm; snap 6.4 deg/f (chest f70) |

Faults per body: m1 6, f1 7
