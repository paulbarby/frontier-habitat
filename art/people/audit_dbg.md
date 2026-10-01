# Animation audit (dbg)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | c1 | m1 |
|---|---|---|
| fight_idle | - | step 20.1 deg (upper_arm.R f7); elbow 155 deg; wrist 124 deg; self 10.6 cm (forearm.R-torso f5) |
| hold_hands_walk | ok | ok |
| kiss_brief | - | step 23.9 deg (forearm.L f18); snap 10.4 deg/f (forearm.R f15) |
| punch | - | slide 6.1 cm (L f48); step 27.9 deg (forearm.R f8); snap 10.2 deg/f (forearm.R f5); elbow 166 deg; self 9.5 cm (forearm.R-torso f14) |
| slap | - | step 34.9 deg (upper_arm.R f17); snap 14.0 deg/f (upper_arm.R f14); wrist 80 deg; self 10.9 cm (forearm.R-torso f28) |
| sleep | wrist 89 deg | step 108.1 deg (hand.L f30); snap 107.2 deg/f (hand.L f30); wrist 89 deg; self 3.2 cm (forearm.L-torso f31) |
| wave | step 18.2 deg (forearm.R f9); wrist 84 deg | step 18.2 deg (forearm.R f9); wrist 84 deg |

Faults per body: c1 3, m1 21
