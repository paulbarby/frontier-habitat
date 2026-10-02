# Animation audit (t43)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | c1 |
|---|---|---|
| argue | ok | - |
| bunk_enter | ok | ok |
| bunk_exit | ok | ok |
| carry_idle | ok | ok |
| carry_walk | ok | ok |
| cheer | ok | ok |
| child_play | - | floats 4.3 cm |
| child_run | - | snap 15.3 deg/f (shin.R f9) |
| collapse | ok | ok |
| dance_a | ok | ok |
| dance_b | floats 1.0 cm | ok |
| dance_c | floats 1.4 cm; slide 1.2 cm (R f72) | floats 1.2 cm; slide 3.8 cm (L f67) |
| dead | ok | ok |
| drink_bar | snap 8.5 deg/f (forearm.R f59) | - |
| drive_sit | ok | ok |
| escort_walk | ok | - |
| fall_down | ok | ok |
| fight_idle | slide 4.6 cm (R f53); elbow 152 deg | - |
| flirt_lean | slide 2.1 cm (R f56) | - |
| get_up | ok | snap 7.1 deg/f (shin.L f2) |
| handcuffed_walk | ok | - |
| handshake | ok | ok |
| hit_react | ok | - |
| hold_hands_walk | ok | ok |
| hold_hands_walk_r | ok | ok |
| hug | ok | - |
| idle | ok | ok |
| idle_look | ok | ok |
| injured_walk | ok | ok |
| jog | ok | ok |
| kiss_brief | ok | - |
| kneel_enter | floats 1.4 cm; slide 2.5 cm (R f42) | floats 1.4 cm; slide 2.7 cm (R f40) |
| kneel_exit | floats 1.2 cm; slide 3.7 cm (R f30) | floats 1.2 cm; slide 3.3 cm (R f31) |
| laugh | ok | ok |
| lie_enter | ok | ok |
| lie_enter_r | ok | ok |
| lie_exit | ok | ok |
| lie_exit_r | ok | ok |
| listen_nod | ok | ok |
| lounge_pool | ok | ok |
| lounger_enter | slide 1.6 cm (L f5) | ok |
| lounger_exit | ok | ok |
| play_arcade | ok | snap 10.8 deg/f (forearm.R f100) |
| protest_fist | ok | - |
| punch | ok | - |
| repair_kneel | floats 1.2 cm | floats 1.2 cm |
| run | snap 14.1 deg/f (foot.L f17) | ok |
| shop_browse | ok | ok |
| shout | ok | - |
| sit_bar_stool | ok | - |
| sit_bench | ok | ok |
| sit_class | ok | ok |
| sit_eat | ok | snap 10.1 deg/f (hand.R f14) |
| sit_enter | slide 1.5 cm (L f54) | ok |
| sit_exit | slide 1.5 cm (L f47) | ok |
| sit_idle | ok | ok |
| sit_type | ok | ok |
| slap | ok | - |
| sleep | ok | ok |
| sleep_cell | ok | - |
| sleep_r | ok | ok |
| sleep_turn | ok | ok |
| stool_enter | slide 1.6 cm (L f5) | - |
| stool_exit | slide 1.2 cm (L f51) | - |
| sulk | ok | ok |
| swim | snap 9.6 deg/f (forearm.L f18); neck 71 deg | snap 10.7 deg/f (thigh.R f39); neck 71 deg |
| swim_enter | ok | snap 9.9 deg/f (shin.L f66) |
| swim_exit | snap 11.9 deg/f (shin.R f45) | snap 10.4 deg/f (shin.R f45) |
| talk | ok | snap 8.7 deg/f (forearm.L f44) |
| talk_gesture_a | ok | ok |
| talk_gesture_b | ok | ok |
| talk_idle | ok | ok |
| teach | ok | - |
| walk | ok | ok |
| wave | ok | wrist 75 deg |
| work_bench | ok | ok |
| work_console | ok | ok |

Faults per body: m1 21, c1 18
