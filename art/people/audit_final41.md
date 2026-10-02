# Animation audit (final41)

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
| child_play | - | - | - | - | - | - | floats 4.3 cm | ok | - | - |
| child_run | - | - | - | - | - | - | snap 15.3 deg/f (shin.R f9) | ok | - | - |
| collapse | ok | ok | ok | ok | snap 15.0 deg/f (shin.L f54) | ok | ok | ok | ok | ok |
| dance_a | ok | ok | ok | ok | floats 2.1 cm | ok | ok | floats 1.5 cm | - | - |
| dance_b | floats 1.0 cm | ok | ok | ok | floats 2.0 cm | floats 2.4 cm | ok | floats 1.5 cm | - | - |
| dance_c | floats 1.8 cm | ok | floats 2.6 cm | floats 2.1 cm | floats 1.9 cm; slide 1.5 cm (R f58) | floats 2.0 cm | floats 1.2 cm; slide 2.9 cm (R f71) | floats 1.7 cm; slide 3.2 cm (R f62) | - | - |
| dead | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| drink_bar | snap 8.5 deg/f (forearm.R f59) | snap 8.5 deg/f (forearm.R f59) | snap 8.5 deg/f (forearm.R f59) | snap 8.4 deg/f (forearm.R f59) | snap 8.5 deg/f (forearm.R f59) | snap 8.4 deg/f (forearm.R f59) | - | - | - | - |
| drive_sit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| escort_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| fall_down | ok | ok | ok | ok | ok | snap 14.8 deg/f (forearm.L f21) | ok | ok | - | - |
| fight_idle | slide 2.6 cm (R f22); elbow 152 deg | slide 2.7 cm (R f21); elbow 151 deg | slide 2.5 cm (R f29); elbow 152 deg | slide 2.6 cm (R f29); elbow 152 deg | slide 2.5 cm (R f26); elbow 152 deg | slide 2.7 cm (R f28); elbow 152 deg | - | - | - | - |
| flirt_lean | ok | ok | ok | ok | ok | ok | - | - | - | - |
| get_up | ok | ok | ok | snap 7.2 deg/f (shin.L f2) | snap 6.2 deg/f (shin.L f2) | ok | snap 7.1 deg/f (shin.L f2) | ok | - | - |
| handcuffed_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| handshake | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hit_react | ok | ok | ok | ok | ok | ok | - | - | - | - |
| hold_hands_walk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hold_hands_walk_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hug | ok | ok | ok | ok | ok | ok | - | - | - | - |
| idle | ok | ok | ok | ok | ok | snap 6.1 deg/f (shin.L f100) | ok | ok | ok | ok |
| idle_look | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| injured_walk | ok | ok | ok | snap 16.5 deg/f (shin.R f20) | snap 16.9 deg/f (shin.R f20) | ok | ok | ok | ok | ok |
| jog | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| kiss_brief | ok | ok | ok | ok | ok | ok | - | - | - | - |
| kneel_enter | floats 1.4 cm | floats 1.2 cm | floats 1.4 cm | floats 1.7 cm | floats 1.6 cm | floats 1.8 cm | floats 1.4 cm | floats 1.7 cm | slide 2.2 cm (R f33) | slide 2.2 cm (R f33) |
| kneel_exit | floats 1.2 cm; slide 2.2 cm (L f49) | floats 1.0 cm; slide 2.2 cm (L f53) | floats 1.1 cm; slide 2.2 cm (L f48) | floats 1.5 cm; slide 2.0 cm (L f48) | floats 1.4 cm; slide 2.0 cm (L f48) | floats 1.6 cm; slide 2.1 cm (L f49) | floats 1.4 cm; slide 1.7 cm (L f48) | floats 1.7 cm; slide 1.6 cm (L f49) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) | slide 1.6 cm (R f30); snap 6.2 deg/f (forearm.R f15) |
| laugh | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_enter | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_enter_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lie_exit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| lie_exit_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| listen_nod | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lounge_pool | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| lounger_enter | slide 1.6 cm (L f5) | slide 1.6 cm (L f5) | slide 1.3 cm (R f4) | slide 1.5 cm (L f5) | slide 1.5 cm (L f5) | slide 1.6 cm (L f5) | ok | ok | - | - |
| lounger_exit | ok | slide 1.1 cm (L f133) | ok | slide 1.1 cm (L f133) | ok | slide 1.1 cm (L f133) | ok | ok | - | - |
| play_arcade | ok | ok | ok | ok | ok | ok | snap 10.8 deg/f (forearm.R f100) | ok | - | - |
| protest_fist | ok | ok | ok | ok | ok | ok | - | - | - | - |
| punch | ok | elbow 150 deg | ok | ok | elbow 150 deg | ok | - | - | - | - |
| repair_kneel | floats 1.2 cm | floats 1.0 cm | floats 1.1 cm | floats 1.5 cm | floats 1.4 cm | floats 1.6 cm | floats 1.2 cm | floats 1.6 cm | ok | ok |
| ride_sit | - | - | - | - | - | - | - | - | ok | ok |
| run | snap 14.1 deg/f (foot.L f17) | ok | snap 14.0 deg/f (shin.L f18) | ok | ok | ok | ok | snap 14.3 deg/f (shin.L f8) | step 30.2 deg (shin.L f18) | step 30.2 deg (shin.L f18) |
| shop_browse | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| shout | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bar_stool | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bench | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_class | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| sit_eat | ok | ok | ok | ok | ok | snap 7.4 deg/f (hand.R f66) | snap 10.1 deg/f (hand.R f14) | ok | snap 7.2 deg/f (upper_arm.R f66) | snap 7.2 deg/f (upper_arm.R f66) |
| sit_enter | slide 1.5 cm (L f47) | slide 1.5 cm (L f46) | slide 1.5 cm (R f42) | slide 1.4 cm (L f56) | slide 1.3 cm (L f54) | slide 1.4 cm (R f41) | ok | slide 1.1 cm (R f43) | ok | ok |
| sit_exit | slide 1.5 cm (L f50) | slide 1.5 cm (L f45) | slide 1.5 cm (R f46) | slide 1.4 cm (L f48) | slide 1.3 cm (L f43) | slide 1.4 cm (R f50) | ok | ok | ok | ok |
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
| stool_enter | slide 1.6 cm (L f5) | slide 1.5 cm (L f5) | slide 1.6 cm (L f5) | slide 1.5 cm (L f5); snap 10.5 deg/f (shin.R f23) | slide 1.4 cm (L f5); snap 10.2 deg/f (shin.R f38) | slide 1.5 cm (L f5) | - | - | - | - |
| stool_exit | slide 1.2 cm (L f51) | slide 1.1 cm (L f51) | slide 1.2 cm (L f51) | slide 1.1 cm (L f52); snap 10.2 deg/f (shin.R f27) | slide 1.1 cm (L f52); snap 10.3 deg/f (shin.R f12) | slide 1.1 cm (L f52) | - | - | - | - |
| suit_swap | - | - | - | - | - | - | - | - | snap 9.3 deg/f (forearm.R f44) | snap 9.3 deg/f (forearm.R f44) |
| sulk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| swim | snap 9.6 deg/f (forearm.L f18); neck 71 deg | snap 9.6 deg/f (forearm.R f18); neck 71 deg | snap 10.2 deg/f (forearm.L f19); neck 71 deg | snap 11.4 deg/f (shin.L f15); neck 71 deg | snap 11.1 deg/f (shin.L f15); neck 71 deg | snap 11.3 deg/f (shin.R f15); neck 71 deg | snap 10.7 deg/f (thigh.R f39); neck 71 deg | snap 11.0 deg/f (forearm.L f19); neck 71 deg | - | - |
| swim_enter | ok | ok | ok | snap 10.8 deg/f (shin.L f36) | snap 10.7 deg/f (shin.L f65) | snap 10.6 deg/f (shin.L f36) | snap 9.9 deg/f (shin.L f66) | snap 7.4 deg/f (shin.R f67) | - | - |
| swim_exit | snap 11.9 deg/f (shin.R f45) | snap 7.3 deg/f (shin.L f38) | snap 10.2 deg/f (shin.L f87) | snap 11.6 deg/f (shin.L f4) | snap 11.8 deg/f (shin.R f4) | snap 11.3 deg/f (shin.L f4) | snap 10.4 deg/f (shin.R f45) | snap 11.1 deg/f (shin.L f3) | - | - |
| talk | ok | ok | ok | ok | snap 8.7 deg/f (forearm.L f44) | snap 8.8 deg/f (forearm.L f44) | snap 8.7 deg/f (forearm.L f44) | snap 8.9 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) | snap 9.3 deg/f (forearm.L f44) |
| talk_gesture_a | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_gesture_b | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| talk_idle | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| teach | ok | ok | ok | ok | ok | ok | - | - | - | - |
| walk | ok | ok | ok | ok | ok | ok | ok | snap 14.6 deg/f (shin.L f16) | ok | ok |
| wave | ok | ok | ok | ok | ok | ok | wrist 75 deg | ok | - | - |
| work_bench | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| work_console | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |

Faults per body: m1 18, m2 17, m3 17, f1 22, f2 27, f3 23, c1 17, c2 16, suit 9, indoor 9
