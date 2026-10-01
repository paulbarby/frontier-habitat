# Animation audit (m1fix)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 |
|---|---|
| argue | step 10.7 deg (hand.R f32); snap 4.1 deg/f (hand.R f35); wrist 75 deg; self 11.2 cm (forearm.R-torso f31) |
| carry_idle | ok |
| carry_walk | ok |
| cheer | step 11.9 deg (upper_arm.L f19) |
| collapse | step 22.3 deg (forearm.L f23); snap 7.5 deg/f (forearm.L f22); wrist 104 deg; self 6.4 cm (forearm.R-torso f56) |
| dance_a | step 9.2 deg (upper_arm.R f90) |
| dance_b | floats 1.3 cm |
| dance_c | step 20.0 deg (thigh.R f74); snap 5.6 deg/f (upper_arm.L f113) |
| dead | self 5.9 cm (forearm.R-torso f0) |
| drink_bar | step 17.1 deg (forearm.R f65); wrist 116 deg; self 7.7 cm (forearm.R-torso f48) |
| drive_sit | ok |
| escort_walk | ok |
| fall_down | step 31.3 deg (forearm.L f17); snap 20.8 deg/f (forearm.L f19); wrist 108 deg; self 6.3 cm (forearm.R-torso f39) |
| fight_idle | step 20.1 deg (upper_arm.R f7); snap 5.2 deg/f (upper_arm.R f2); elbow 155 deg; wrist 124 deg; self 10.6 cm (forearm.R-torso f5) |
| flirt_lean | slide 1.7 cm (R f6); step 7.0 deg (upper_arm.L f112) |
| get_up | step 15.1 deg (upper_arm.L f26); wrist 85 deg; self 5.9 cm (forearm.R-torso f1) |
| handcuffed_walk | ok |
| handshake | step 7.5 deg (upper_arm.R f61) |
| hit_react | step 28.1 deg (upper_arm.L f24); snap 10.7 deg/f (upper_arm.L f28); wrist 101 deg |
| hold_hands_walk | ok |
| hold_hands_walk_r | ok |
| hug | wrist 75 deg |
| idle | step 9.9 deg (forearm.L f75) |
| idle_look | ok |
| injured_walk | snap 15.6 deg/f (shin.R f23); self 11.4 cm (forearm.L-torso f36) |
| jog | snap 13.1 deg/f (shin.R f22) |
| kiss_brief | step 23.9 deg (forearm.L f18); snap 10.4 deg/f (forearm.R f15) |
| kneel_enter | slide 2.8 cm (R f43); step 9.5 deg (hand.R f40) |
| kneel_exit | slide 3.5 cm (R f30); step 12.5 deg (forearm.L f37) |
| laugh | step 9.3 deg (forearm.R f11); self 11.3 cm (forearm.R-torso f18) |
| lie_enter | step 10.0 deg (thigh.L f75); self 11.5 cm (forearm.R-torso f89) |
| lie_enter_r | step 10.0 deg (thigh.R f75); self 11.5 cm (forearm.L-torso f89) |
| lie_exit | step 12.1 deg (hand.L f50); snap 4.5 deg/f (forearm.L f48); wrist 79 deg; self 11.2 cm (forearm.R-torso f20) |
| lie_exit_r | step 12.1 deg (hand.R f50); snap 4.5 deg/f (forearm.R f48); wrist 79 deg; self 11.2 cm (forearm.L-torso f20) |
| listen_nod | step 6.6 deg (upper_arm.L f9) |
| lounge_pool | wrist 96 deg |
| play_arcade | ok |
| protest_fist | step 13.5 deg (forearm.R f12); snap 8.6 deg/f (forearm.R f11); self 2.9 cm (forearm.R-torso f7) |
| punch | slide 6.1 cm (L f45); step 39.4 deg (hand.R f15); snap 20.3 deg/f (forearm.R f12); elbow 167 deg; self 11.2 cm (forearm.L-torso f12) |
| repair_kneel | ok |
| run | snap 16.6 deg/f (shin.L f7) |
| shop_browse | step 12.6 deg (hand.R f38); wrist 81 deg; self 6.2 cm (forearm.R-torso f63) |
| shout | step 26.3 deg (forearm.R f28); snap 17.7 deg/f (forearm.R f27); elbow 158 deg |
| sit_bar_stool | self 5.3 cm (forearm.R-torso f82) |
| sit_bench | ok |
| sit_class | step 6.1 deg (upper_arm.R f141) |
| sit_eat | step 9.0 deg (hand.R f11); snap 4.8 deg/f (upper_arm.R f14) |
| sit_enter | slide 1.5 cm (L f46); step 7.2 deg (forearm.L f38) |
| sit_exit | slide 1.5 cm (L f45); step 10.3 deg (forearm.L f30) |
| sit_idle | ok |
| sit_type | ok |
| slap | step 47.0 deg (upper_arm.R f14); snap 23.8 deg/f (upper_arm.R f13); wrist 80 deg; self 7.8 cm (forearm.R-torso f28) |
| sleep | self 11.1 cm (forearm.R-torso f48) |
| sleep_cell | self 11.1 cm (forearm.R-torso f48) |
| sleep_r | self 11.1 cm (forearm.L-torso f48) |
| sulk | floats 5.9 cm |
| swim | step 20.3 deg (forearm.L f18); snap 9.3 deg/f (forearm.R f17); neck 72 deg |
| talk | step 13.3 deg (forearm.L f45) |
| talk_gesture_a | step 10.0 deg (forearm.R f8); self 3.6 cm (forearm.R-torso f72) |
| talk_gesture_b | step 9.6 deg (forearm.R f54); self 6.7 cm (forearm.R-torso f21) |
| talk_idle | ok |
| teach | step 20.0 deg (hand.R f138); wrist 107 deg |
| walk | ok |
| wave | step 18.2 deg (forearm.R f9); snap 5.5 deg/f (hand.R f53); wrist 84 deg |
| work_bench | self 4.4 cm (forearm.R-torso f30) |
| work_console | self 2.5 cm (forearm.R-torso f32) |

Faults per body: m1 108
