# Animation audit (after_mocap)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | m2 | m3 | f1 | f2 | f3 | c1 | c2 | suit | indoor |
|---|---|---|---|---|---|---|---|---|---|---|
| alight | - | - | - | - | - | - | - | - | snap 6.1 deg/f (shin.R f48) | snap 6.1 deg/f (shin.R f48) |
| alight_r | - | - | - | - | - | - | - | - | snap 6.1 deg/f (shin.L f48) | snap 6.1 deg/f (shin.L f48) |
| argue | ok | ok | ok | ok | ok | ok | - | - | - | - |
| board | - | - | - | - | - | - | - | - | snap 8.9 deg/f (forearm.R f5) | snap 8.9 deg/f (forearm.R f5) |
| board_r | - | - | - | - | - | - | - | - | snap 8.9 deg/f (forearm.L f5) | snap 8.9 deg/f (forearm.L f5) |
| carry_idle | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| carry_walk | ok | ok | snap 16.2 deg/f (shin.R f16) | ok | ok | ok | ok | ok | snap 14.9 deg/f (shin.L f32) | snap 14.9 deg/f (shin.L f32) |
| cheer | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| child_play | - | - | - | - | - | - | floats 4.3 cm; slide 2.6 cm (R f77) | slide 3.2 cm (L f75) | - | - |
| child_run | - | - | - | - | - | - | step 31.4 deg (shin.L f17); snap 18.4 deg/f (shin.R f9) | snap 15.9 deg/f (shin.R f9) | - | - |
| collapse | ok | ok | ok | ok | ok | snap 14.7 deg/f (forearm.L f25) | ok | ok | snap 18.3 deg/f (upper_arm.R f51) | snap 18.3 deg/f (upper_arm.R f51) |
| dance_a | ok | ok | ok | ok | floats 2.1 cm | ok | ok | floats 1.5 cm | - | - |
| dance_b | floats 1.0 cm | ok | ok | ok | floats 2.0 cm | floats 2.4 cm | ok | floats 1.5 cm | - | - |
| dance_c | slide 2.2 cm (R f60); snap 6.2 deg/f (upper_arm.R f54) | slide 3.9 cm (R f66) | floats 1.0 cm; slide 1.2 cm (L f58); snap 6.2 deg/f (upper_arm.L f54) | slide 1.3 cm (L f58); snap 6.1 deg/f (upper_arm.R f54) | slide 1.7 cm (R f59); snap 6.1 deg/f (upper_arm.L f61) | slide 1.7 cm (R f59); snap 6.1 deg/f (upper_arm.R f54) | slide 3.3 cm (L f64); snap 6.4 deg/f (upper_arm.R f61) | slide 4.6 cm (R f68); snap 7.4 deg/f (upper_arm.L f61) | - | - |
| dead | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| drink_bar | snap 9.6 deg/f (forearm.R f59) | snap 9.6 deg/f (forearm.R f59) | snap 9.6 deg/f (forearm.R f59) | snap 9.6 deg/f (forearm.R f59) | snap 9.6 deg/f (forearm.R f59) | snap 9.6 deg/f (forearm.R f59) | - | - | - | - |
| drive_sit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| escort_walk | ok | ok | snap 16.0 deg/f (shin.R f16) | ok | ok | ok | - | - | - | - |
| fall_down | step 32.1 deg (forearm.L f18); snap 21.7 deg/f (forearm.L f19) | step 32.4 deg (forearm.L f18); snap 21.1 deg/f (forearm.L f19) | step 31.8 deg (forearm.L f18); snap 20.5 deg/f (forearm.L f19) | step 39.9 deg (forearm.L f18); snap 27.8 deg/f (forearm.L f19) | step 44.1 deg (forearm.L f18); snap 32.5 deg/f (forearm.L f19) | step 45.7 deg (forearm.L f18); snap 34.2 deg/f (forearm.L f19) | step 31.2 deg (upper_arm.L f26); snap 20.5 deg/f (forearm.L f19) | snap 18.0 deg/f (upper_arm.R f36) | - | - |
| fight_idle | slide 1.2 cm (L f4); elbow 152 deg | slide 1.2 cm (L f4); elbow 151 deg | slide 1.6 cm (R f5); elbow 152 deg | slide 1.6 cm (R f5); elbow 152 deg | slide 1.6 cm (R f5); elbow 152 deg | slide 1.2 cm (L f4); elbow 152 deg | - | - | - | - |
| flirt_lean | slide 2.2 cm (R f7) | slide 2.2 cm (R f7) | slide 2.6 cm (R f8) | slide 7.3 cm (R f89) | slide 7.2 cm (R f86) | slide 2.7 cm (R f8) | - | - | - | - |
| get_up | ok | ok | ok | snap 7.4 deg/f (shin.L f2) | snap 7.2 deg/f (shin.L f2) | ok | snap 10.0 deg/f (shin.L f3) | ok | - | - |
| handcuffed_walk | ok | ok | snap 15.7 deg/f (shin.R f16) | ok | ok | ok | - | - | - | - |
| handshake | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hit_react | slide 8.4 cm (R f64) | slide 8.3 cm (R f64) | slide 8.7 cm (R f64) | slide 8.3 cm (R f65) | slide 7.6 cm (R f65) | slide 8.7 cm (R f65) | - | - | - | - |
| hold_hands_walk | ok | ok | snap 16.2 deg/f (shin.L f32) | ok | ok | ok | ok | ok | - | - |
| hold_hands_walk_r | ok | ok | snap 16.2 deg/f (shin.L f16) | ok | ok | ok | ok | ok | - | - |
| hug | ok | ok | ok | ok | ok | ok | - | - | - | - |
| idle | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| idle_look | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| injured_walk | ok | ok | ok | snap 15.6 deg/f (shin.R f20) | snap 16.4 deg/f (shin.R f20) | snap 16.7 deg/f (shin.R f20) | ok | snap 16.7 deg/f (shin.R f22) | ok | ok |
| jog | snap 14.4 deg/f (shin.L f10) | snap 14.4 deg/f (shin.R f22) | snap 14.5 deg/f (shin.L f10) | ok | ok | ok | snap 14.1 deg/f (shin.L f10) | ok | - | - |
| kiss_brief | ok | ok | ok | ok | ok | ok | - | - | - | - |
| kneel_enter | floats 1.4 cm; slide 2.5 cm (R f40) | floats 1.2 cm; slide 2.9 cm (R f47) | floats 1.4 cm; slide 2.2 cm (R f44) | floats 1.7 cm; slide 2.8 cm (R f43) | floats 1.6 cm; slide 2.6 cm (R f49) | floats 1.8 cm; slide 2.8 cm (R f42) | floats 1.4 cm; slide 3.1 cm (R f48) | floats 1.7 cm; slide 2.9 cm (R f47) | slide 2.2 cm (R f33) | slide 2.2 cm (R f33) |
| kneel_exit | floats 1.2 cm; slide 3.6 cm (R f30); snap 6.5 deg/f (forearm.R f15) | floats 1.0 cm; slide 3.5 cm (R f30); snap 6.4 deg/f (forearm.R f15) | floats 1.1 cm; slide 3.8 cm (R f30); snap 6.6 deg/f (forearm.R f15) | floats 1.5 cm; slide 3.3 cm (R f30) | floats 1.4 cm; slide 3.2 cm (R f30) | floats 1.6 cm; slide 3.4 cm (R f30) | floats 1.2 cm; slide 3.2 cm (R f31); snap 6.7 deg/f (forearm.R f15) | floats 1.6 cm; slide 3.6 cm (R f32) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) |
| laugh | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_enter | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_enter_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_exit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_exit_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| listen_nod | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lounge_pool | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| play_arcade | ok | ok | ok | ok | ok | ok | snap 11.0 deg/f (forearm.R f104) | ok | - | - |
| protest_fist | ok | ok | ok | ok | ok | ok | - | - | - | - |
| punch | slide 8.4 cm (L f84) | slide 7.7 cm (L f84); elbow 150 deg | slide 8.8 cm (L f84) | slide 6.7 cm (L f84) | slide 12.6 cm (L f41); elbow 150 deg | slide 7.6 cm (L f84) | - | - | - | - |
| repair_kneel | floats 1.2 cm | floats 1.0 cm | floats 1.1 cm | floats 1.5 cm | floats 1.4 cm | floats 1.6 cm | floats 1.2 cm | floats 1.6 cm | ok | ok |
| ride_sit | - | - | - | - | - | - | - | - | ok | ok |
| run | snap 14.1 deg/f (foot.L f17) | ok | snap 14.0 deg/f (shin.L f18) | ok | ok | ok | ok | snap 14.3 deg/f (shin.L f8) | step 30.2 deg (shin.L f18) | step 30.2 deg (shin.L f18) |
| shop_browse | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| shout | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bar_stool | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bench | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_class | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_eat | ok | ok | ok | ok | ok | snap 7.4 deg/f (hand.R f66) | snap 10.1 deg/f (hand.R f14) | ok | snap 7.2 deg/f (upper_arm.R f66) | snap 7.2 deg/f (upper_arm.R f66) |
| sit_enter | slide 1.5 cm (L f38); snap 6.0 deg/f (forearm.L f28) | slide 1.5 cm (L f51) | slide 1.5 cm (L f51); snap 6.2 deg/f (forearm.R f28) | slide 1.4 cm (L f54) | slide 1.3 cm (L f52) | slide 1.4 cm (L f49) | snap 6.3 deg/f (forearm.L f28) | slide 1.1 cm (R f40) | ok | ok |
| sit_exit | slide 1.5 cm (L f42) | slide 1.5 cm (L f38) | slide 1.5 cm (R f41) | slide 1.4 cm (L f39) | slide 1.3 cm (L f42) | slide 1.4 cm (R f49) | ok | slide 1.1 cm (L f47) | ok | ok |
| sit_idle | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| sit_type | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| slap | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sleep | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| sleep_cell | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sleep_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sleep_turn | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| step_down | - | - | - | - | - | - | - | - | snap 7.1 deg/f (upper_arm.R f22) | snap 7.1 deg/f (upper_arm.R f22) |
| step_down_r | - | - | - | - | - | - | - | - | snap 7.1 deg/f (upper_arm.L f22) | snap 7.1 deg/f (upper_arm.L f22) |
| step_up | - | - | - | - | - | - | - | - | snap 10.3 deg/f (shin.L f24) | snap 10.3 deg/f (shin.L f24) |
| step_up_r | - | - | - | - | - | - | - | - | snap 10.3 deg/f (shin.R f24) | snap 10.3 deg/f (shin.R f24) |
| suit_swap | - | - | - | - | - | - | - | - | snap 9.3 deg/f (forearm.R f44) | snap 9.3 deg/f (forearm.R f44) |
| sulk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| swim | snap 9.8 deg/f (forearm.R f18); neck 72 deg | snap 10.8 deg/f (shin.R f15); neck 72 deg | snap 11.5 deg/f (forearm.R f19); neck 72 deg | snap 11.3 deg/f (shin.L f15); neck 72 deg | snap 11.9 deg/f (shin.L f39); neck 72 deg | snap 11.2 deg/f (shin.L f15); neck 72 deg | snap 11.7 deg/f (shin.L f15); neck 72 deg | snap 11.6 deg/f (shin.L f40); neck 72 deg | - | - |
| talk | snap 9.3 deg/f (forearm.L f44) | snap 9.4 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) | snap 9.5 deg/f (forearm.L f44) | snap 9.6 deg/f (forearm.L f44) | snap 9.8 deg/f (forearm.L f44) | snap 9.6 deg/f (forearm.L f44) | snap 9.9 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) |
| talk_gesture_a | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_gesture_b | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_idle | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| teach | ok | ok | ok | ok | ok | ok | - | - | - | - |
| walk | ok | ok | ok | ok | ok | ok | ok | step 28.4 deg (shin.L f17); snap 28.4 deg/f (shin.L f17) | snap 14.6 deg/f (shin.L f32) | snap 14.6 deg/f (shin.L f32) |
| wave | ok | ok | ok | ok | ok | ok | wrist 75 deg | ok | - | - |
| work_bench | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| work_console | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |

Faults per body: m1 25, m2 22, m3 30, f1 22, f2 25, f3 24, c1 23, c2 21, suit 18, indoor 18
