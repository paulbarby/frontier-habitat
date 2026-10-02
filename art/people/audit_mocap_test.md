# Animation audit (mocap_test)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | f1 | c2 |
|---|---|---|
| idle | ok | snap 9.1 deg/f (shin.L f9) |
| talk_idle | ok | ok |

Faults per body: f1 0, c2 1
