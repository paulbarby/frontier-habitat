# Animation audit (t42)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | f2 | c1 |
|---|---|---|---|
| argue | ok | ok | - |
| bunk_enter | ok | ok | ok |
| bunk_exit | ok | ok | ok |
| carry_idle | ok | ok | ok |
| carry_walk | ok | ok | ok |
| cheer | ok | ok | ok |
| child_play | - | - | floats 4.3 cm |
| child_run | - | - | snap 15.3 deg/f (shin.R f9) |
| collapse | ok | snap 15.0 deg/f (shin.L f54) | ok |
| dance_a | ok | floats 2.1 cm | ok |
| dance_b | floats 1.0 cm | floats 2.0 cm | ok |
| dance_c | floats 1.8 cm; slide 2.0 cm (R f60) | floats 1.9 cm; slide 1.9 cm (R f60) | floats 1.2 cm; slide 2.8 cm (R f71) |
| dead | ok | ok | ok |
| drink_bar | snap 8.5 deg/f (forearm.R f59) | snap 8.5 deg/f (forearm.R f59) | - |
| drive_sit | ok | ok | ok |
| escort_walk | ok | ok | - |
| fall_down | ok | ok | ok |
| fight_idle | slide 2.4 cm (R f29); elbow 152 deg | slide 2.4 cm (R f21); elbow 152 deg | - |
| flirt_lean | slide 2.1 cm (R f56) | slide 2.6 cm (R f47) | - |
| get_up | ok | snap 6.2 deg/f (shin.L f2) | snap 7.1 deg/f (shin.L f2) |
| handcuffed_walk | ok | ok | - |
| handshake | ok | ok | ok |
| hit_react | ok | ok | - |
| hold_hands_walk | ok | ok | ok |
| hold_hands_walk_r | ok | ok | ok |
| hug | ok | ok | - |
| idle | ok | ok | ok |
| idle_look | ok | ok | ok |
| injured_walk | ok | snap 16.9 deg/f (shin.R f20) | ok |
| jog | ok | ok | ok |
| kiss_brief | ok | ok | - |
| kneel_enter | floats 1.4 cm; slide 2.5 cm (R f42) | floats 1.6 cm; slide 2.7 cm (R f47) | floats 1.4 cm; slide 2.7 cm (R f40) |
| kneel_exit | floats 1.2 cm; slide 3.7 cm (R f30) | floats 1.4 cm; slide 3.9 cm (R f31) | floats 1.2 cm; slide 3.3 cm (R f31) |
| laugh | ok | ok | ok |
| lie_enter | ok | ok | ok |
| lie_enter_r | ok | ok | ok |
| lie_exit | ok | ok | ok |
| lie_exit_r | ok | ok | ok |
| listen_nod | ok | ok | ok |
| lounge_pool | ok | ok | ok |
| lounger_enter | slide 1.6 cm (L f5) | slide 1.5 cm (L f5) | ok |
| lounger_exit | ok | ok | ok |
| play_arcade | ok | ok | snap 10.8 deg/f (forearm.R f100) |
| protest_fist | ok | ok | - |
| punch | ok | elbow 150 deg | - |
| repair_kneel | floats 1.2 cm | floats 1.4 cm | floats 1.2 cm |
| run | snap 14.1 deg/f (foot.L f17) | ok | ok |
| shop_browse | ok | ok | ok |
| shout | ok | ok | - |
| sit_bar_stool | ok | ok | - |
| sit_bench | ok | ok | ok |
| sit_class | ok | ok | ok |
| sit_eat | ok | ok | snap 10.1 deg/f (hand.R f14) |
| sit_enter | slide 1.5 cm (L f47) | slide 1.3 cm (L f54) | ok |
| sit_exit | slide 1.5 cm (L f50) | slide 1.3 cm (L f43) | ok |
| sit_idle | ok | ok | ok |
| sit_type | ok | ok | ok |
| slap | ok | ok | - |
| sleep | ok | ok | ok |
| sleep_cell | ok | ok | - |
| sleep_r | ok | ok | ok |
| sleep_turn | ok | ok | ok |
| stool_enter | slide 1.6 cm (L f5) | slide 1.4 cm (L f5); snap 10.2 deg/f (shin.R f38) | - |
| stool_exit | slide 1.2 cm (L f51) | slide 1.1 cm (L f52); snap 10.3 deg/f (shin.R f12) | - |
| sulk | ok | ok | ok |
| swim | snap 9.6 deg/f (forearm.L f18); neck 71 deg | snap 11.1 deg/f (shin.L f15); neck 71 deg | snap 10.7 deg/f (thigh.R f39); neck 71 deg |
| swim_enter | ok | snap 10.7 deg/f (shin.L f65) | snap 9.9 deg/f (shin.L f66) |
| swim_exit | snap 11.9 deg/f (shin.R f45) | snap 11.8 deg/f (shin.R f4) | snap 10.4 deg/f (shin.R f45) |
| talk | ok | snap 8.7 deg/f (forearm.L f44) | snap 8.7 deg/f (forearm.L f44) |
| talk_gesture_a | ok | ok | ok |
| talk_gesture_b | ok | ok | ok |
| talk_idle | ok | ok | ok |
| teach | ok | ok | - |
| walk | ok | ok | ok |
| wave | ok | ok | wrist 75 deg |
| work_bench | ok | ok | ok |
| work_console | ok | ok | ok |

Faults per body: m1 21, f2 29, c1 18
