# Animation audit (r41)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | m2 | m3 | f1 | f2 | f3 | c1 | c2 | suit | indoor |
|---|---|---|---|---|---|---|---|---|---|---|
| alight | - | - | - | - | - | - | - | - | ok | ok |
| alight_r | - | - | - | - | - | - | - | - | ok | ok |
| argue | ok | ok | ok | ok | ok | ok | - | - | - | - |
| board | - | - | - | - | - | - | - | - | snap 7.6 deg/f (forearm.R f5) | snap 7.6 deg/f (forearm.R f5) |
| board_r | - | - | - | - | - | - | - | - | snap 7.6 deg/f (forearm.L f5) | snap 7.6 deg/f (forearm.L f5) |
| bunk_enter | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| bunk_exit | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| carry_idle | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| carry_walk | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| cheer | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| child_play | - | - | - | - | - | - | floats 4.3 cm; slide 2.6 cm (R f77) | floats 1.4 cm; slide 3.2 cm (L f75) | - | - |
| child_run | - | - | - | - | - | - | snap 15.3 deg/f (shin.R f9) | ok | - | - |
| collapse | ok | ok | ok | ok | snap 15.0 deg/f (shin.L f54) | ok | ok | ok | ok | ok |
| dance_a | ok | ok | ok | ok | floats 2.1 cm | ok | ok | floats 1.5 cm | - | - |
| dance_b | floats 1.0 cm | ok | ok | ok | floats 2.0 cm | floats 2.4 cm | ok | floats 1.5 cm | - | - |
| dance_c | floats 4.5 cm; slide 1.1 cm (R f58) | floats 4.4 cm; slide 1.9 cm (R f60) | floats 4.7 cm | floats 4.2 cm; slide 1.3 cm (R f58) | floats 4.1 cm; slide 1.2 cm (R f58) | floats 4.4 cm; slide 1.2 cm (R f58) | floats 3.5 cm; slide 2.3 cm (R f90) | floats 3.4 cm; slide 2.3 cm (R f61) | - | - |
| dead | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| drink_bar | snap 9.0 deg/f (forearm.R f59) | snap 8.9 deg/f (forearm.R f59) | snap 9.0 deg/f (forearm.R f59) | snap 9.0 deg/f (forearm.R f59) | snap 9.0 deg/f (forearm.R f59) | snap 9.0 deg/f (forearm.R f59) | - | - | - | - |
| drive_sit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| escort_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| fall_down | snap 18.6 deg/f (upper_arm.R f36) | snap 18.5 deg/f (upper_arm.R f36) | step 30.1 deg (upper_arm.L f26) | step 33.0 deg (forearm.L f18); snap 16.9 deg/f (forearm.L f19) | step 36.1 deg (forearm.L f18); snap 20.1 deg/f (forearm.L f19) | step 38.4 deg (forearm.L f18); snap 22.2 deg/f (forearm.L f19) | step 30.1 deg (upper_arm.L f26); snap 15.1 deg/f (forearm.L f19) | snap 18.6 deg/f (upper_arm.R f36) | - | - |
| fight_idle | floats 3.7 cm; slide 1.2 cm (L f4); elbow 152 deg | floats 3.6 cm; slide 1.2 cm (L f4); elbow 151 deg | floats 3.9 cm; slide 1.1 cm (R f4); elbow 152 deg | floats 3.5 cm; slide 1.2 cm (L f4); elbow 152 deg | floats 3.4 cm; slide 1.6 cm (R f5); elbow 152 deg | floats 3.6 cm; slide 1.2 cm (L f4); elbow 152 deg | - | - | - | - |
| flirt_lean | floats 3.7 cm; slide 1.2 cm (R f5) | floats 3.6 cm; slide 1.2 cm (R f5) | floats 3.9 cm; slide 1.6 cm (R f6) | floats 3.5 cm; slide 1.5 cm (R f6) | floats 3.4 cm; slide 1.5 cm (R f6) | floats 3.6 cm; slide 1.6 cm (R f6) | - | - | - | - |
| get_up | ok | ok | ok | snap 9.5 deg/f (shin.L f2) | snap 7.1 deg/f (shin.L f3) | ok | snap 11.6 deg/f (shin.L f3) | ok | - | - |
| handcuffed_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| handshake | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hit_react | floats 3.7 cm; slide 1.5 cm (R f63) | floats 3.6 cm; slide 1.5 cm (R f63) | ok | floats 3.5 cm; slide 2.4 cm (R f64) | floats 3.4 cm; slide 2.3 cm (R f64) | floats 3.6 cm; slide 2.0 cm (R f64) | - | - | - | - |
| hold_hands_walk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hold_hands_walk_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hug | ok | ok | ok | ok | ok | ok | - | - | - | - |
| idle | ok | ok | ok | ok | ok | snap 6.1 deg/f (shin.L f100) | ok | ok | ok | ok |
| idle_look | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| injured_walk | ok | ok | ok | snap 16.5 deg/f (shin.R f20) | snap 16.9 deg/f (shin.R f20) | ok | ok | ok | ok | ok |
| jog | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| kiss_brief | ok | ok | ok | ok | ok | ok | - | - | - | - |
| kneel_enter | floats 1.4 cm; slide 2.5 cm (R f42) | floats 1.2 cm; slide 2.9 cm (R f41) | floats 1.4 cm; slide 2.2 cm (R f42) | floats 1.7 cm; slide 2.8 cm (R f42) | floats 1.6 cm; slide 2.7 cm (R f47) | floats 1.8 cm; slide 2.8 cm (R f40) | floats 1.4 cm; slide 2.7 cm (R f40) | floats 1.7 cm; slide 2.9 cm (R f47) | slide 2.2 cm (R f33) | slide 2.2 cm (R f33) |
| kneel_exit | floats 1.2 cm; slide 3.7 cm (R f30); snap 6.1 deg/f (forearm.R f16) | floats 1.2 cm; slide 3.6 cm (R f30) | floats 1.3 cm; slide 3.9 cm (R f30); snap 6.1 deg/f (forearm.R f16) | floats 1.5 cm; slide 3.4 cm (R f30) | floats 1.4 cm; slide 3.8 cm (R f31) | floats 1.6 cm; slide 3.5 cm (R f30) | floats 1.2 cm; slide 3.3 cm (R f31); snap 6.2 deg/f (forearm.R f16) | floats 1.6 cm; slide 3.7 cm (R f32) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) |
| laugh | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_enter | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_enter_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_exit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_exit_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| listen_nod | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lounge_pool | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| play_arcade | ok | ok | ok | ok | ok | ok | snap 11.1 deg/f (forearm.R f104) | ok | - | - |
| protest_fist | ok | ok | ok | ok | ok | ok | - | - | - | - |
| punch | floats 3.7 cm; slide 4.4 cm (L f41) | floats 3.6 cm; slide 4.3 cm (L f41); elbow 150 deg | floats 3.9 cm; slide 4.2 cm (L f41) | floats 3.5 cm; slide 5.2 cm (L f71) | floats 3.4 cm; slide 8.5 cm (L f84); elbow 150 deg | floats 3.6 cm; slide 5.0 cm (L f70) | - | - | - | - |
| repair_kneel | floats 1.2 cm | floats 1.0 cm | floats 1.1 cm | floats 1.5 cm | floats 1.4 cm | floats 1.6 cm | floats 1.2 cm | floats 1.6 cm | ok | ok |
| ride_sit | - | - | - | - | - | - | - | - | ok | ok |
| run | snap 14.1 deg/f (foot.L f17) | ok | snap 14.0 deg/f (shin.L f18) | ok | ok | ok | ok | snap 14.3 deg/f (shin.L f8) | step 30.2 deg (shin.L f18) | step 30.2 deg (shin.L f18) |
| shop_browse | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| shout | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bar_stool | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bench | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_class | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_eat | snap 8.8 deg/f (forearm.R f66) | snap 8.8 deg/f (forearm.R f66) | snap 9.6 deg/f (forearm.R f66) | snap 9.9 deg/f (forearm.R f66) | snap 9.9 deg/f (forearm.R f66) | snap 9.8 deg/f (forearm.R f66) | snap 9.2 deg/f (forearm.R f15) | snap 9.3 deg/f (forearm.R f85) | snap 7.2 deg/f (upper_arm.R f66) | snap 7.2 deg/f (upper_arm.R f66) |
| sit_enter | slide 1.5 cm (L f47) | slide 1.5 cm (L f46) | slide 1.5 cm (R f42) | slide 1.4 cm (L f56) | slide 1.3 cm (L f54) | slide 1.4 cm (R f41) | ok | slide 1.1 cm (R f43) | ok | ok |
| sit_exit | slide 1.5 cm (L f50) | slide 1.5 cm (L f45) | slide 1.5 cm (R f46) | slide 1.4 cm (L f48) | slide 1.3 cm (L f43) | slide 1.4 cm (R f50) | ok | slide 1.1 cm (L f51) | ok | ok |
| sit_idle | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| sit_type | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| slap | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sleep | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| sleep_cell | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sleep_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sleep_turn | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| step_down | - | - | - | - | - | - | - | - | ok | ok |
| step_down_r | - | - | - | - | - | - | - | - | ok | ok |
| step_up | - | - | - | - | - | - | - | - | ok | ok |
| step_up_r | - | - | - | - | - | - | - | - | ok | ok |
| stool_enter | slide 1.6 cm (L f5) | slide 1.5 cm (L f5) | slide 1.7 cm (L f5) | slide 1.5 cm (L f5); snap 11.4 deg/f (shin.L f20) | slide 1.4 cm (L f5); snap 10.3 deg/f (shin.R f38) | slide 1.5 cm (L f5) | - | - | - | - |
| stool_exit | slide 1.1 cm (L f49) | slide 1.1 cm (L f49) | slide 1.2 cm (L f49) | snap 11.8 deg/f (shin.L f30) | snap 10.4 deg/f (shin.R f12) | slide 1.1 cm (L f49) | - | - | - | - |
| suit_swap | - | - | - | - | - | - | - | - | snap 8.2 deg/f (forearm.R f44) | snap 8.2 deg/f (forearm.R f44) |
| sulk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| swim | snap 9.8 deg/f (forearm.R f18); neck 71 deg | snap 9.7 deg/f (forearm.R f18); neck 71 deg | snap 10.9 deg/f (forearm.R f19); neck 71 deg | snap 11.3 deg/f (shin.R f15); neck 71 deg | snap 11.1 deg/f (shin.L f15); neck 71 deg | snap 11.3 deg/f (shin.R f15); neck 71 deg | snap 11.8 deg/f (shin.L f15); neck 71 deg | snap 11.6 deg/f (forearm.R f19); neck 71 deg | - | - |
| swim_enter | snap 6.3 deg/f (shin.R f36) | snap 6.1 deg/f (shin.L f36) | ok | snap 10.8 deg/f (shin.R f36) | snap 10.5 deg/f (shin.L f65) | snap 11.1 deg/f (shin.L f65) | snap 11.3 deg/f (shin.R f36) | snap 9.1 deg/f (shin.R f67) | - | - |
| swim_exit | snap 7.4 deg/f (shin.L f38) | snap 7.9 deg/f (shin.L f38) | snap 10.3 deg/f (shin.L f38) | snap 11.3 deg/f (shin.L f4) | snap 11.5 deg/f (shin.R f4) | snap 11.9 deg/f (shin.R f4) | snap 9.9 deg/f (shin.R f45) | snap 11.3 deg/f (shin.R f3) | - | - |
| talk | snap 9.1 deg/f (forearm.L f44) | snap 9.1 deg/f (forearm.L f44) | snap 8.8 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) | snap 9.4 deg/f (forearm.L f44) | snap 9.5 deg/f (forearm.L f44) | snap 9.4 deg/f (forearm.L f44) | snap 9.7 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) |
| talk_gesture_a | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_gesture_b | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_idle | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| teach | ok | ok | ok | ok | ok | ok | - | - | - | - |
| walk | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| wave | ok | ok | ok | ok | ok | ok | wrist 75 deg | ok | - | - |
| work_bench | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| work_console | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |

Faults per body: m1 31, m2 29, m3 26, f1 32, f2 36, f3 31, c1 22, c2 21, suit 9, indoor 9
