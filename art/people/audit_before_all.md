# Animation audit (before_all)

Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).

| clip | m1 | m2 | m3 | f1 | f2 | f3 | c1 | c2 | suit | indoor |
|---|---|---|---|---|---|---|---|---|---|---|
| alight | - | - | - | - | - | - | - | - | snap 7.4 deg/f (hand.L f45); wrist 92 deg | snap 7.4 deg/f (hand.L f45); wrist 92 deg |
| alight_r | - | - | - | - | - | - | - | - | snap 7.4 deg/f (hand.R f45); wrist 92 deg | snap 7.4 deg/f (hand.R f45); wrist 92 deg |
| argue | wrist 158 deg | floats 1.7 cm; wrist 158 deg | wrist 158 deg | floats 1.1 cm; wrist 158 deg | floats 1.1 cm; wrist 158 deg | floats 1.2 cm; wrist 158 deg | - | - | - | - |
| board | - | - | - | - | - | - | - | - | snap 8.9 deg/f (forearm.R f5) | snap 8.9 deg/f (forearm.R f5) |
| board_r | - | - | - | - | - | - | - | - | snap 8.9 deg/f (forearm.L f5) | snap 8.9 deg/f (forearm.L f5) |
| carry_idle | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |
| carry_walk | ok | ok | ok | ok | ok | ok | ok | ok | snap 14.9 deg/f (shin.L f32) | snap 14.9 deg/f (shin.L f32) |
| cheer | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |
| child_play | - | - | - | - | - | - | floats 5.1 cm; slide 2.6 cm (R f81) | floats 4.7 cm; slide 3.2 cm (L f80) | - | - |
| child_run | - | - | - | - | - | - | step 28.4 deg (shin.L f8); snap 24.2 deg/f (shin.R f17) | step 28.9 deg (shin.R f17); snap 23.4 deg/f (shin.R f17) | - | - |
| collapse | snap 18.0 deg/f (upper_arm.R f51); wrist 104 deg | snap 17.7 deg/f (upper_arm.R f51); wrist 102 deg | snap 17.6 deg/f (upper_arm.R f51); wrist 101 deg | wrist 107 deg | wrist 108 deg | wrist 108 deg | wrist 104 deg | wrist 101 deg | snap 18.4 deg/f (upper_arm.R f51); wrist 107 deg | snap 18.4 deg/f (upper_arm.R f51); wrist 107 deg |
| dance_a | ok | floats 1.7 cm | floats 1.3 cm | floats 3.2 cm | floats 2.9 cm | floats 2.8 cm | ok | floats 2.4 cm | - | - |
| dance_b | floats 1.3 cm | floats 2.4 cm | floats 1.7 cm | floats 3.2 cm | floats 2.9 cm | floats 3.3 cm | ok | floats 2.7 cm | - | - |
| dance_c | floats 1.2 cm; slide 2.2 cm (R f60); snap 9.2 deg/f (upper_arm.L f38) | floats 2.5 cm; slide 3.9 cm (R f66); snap 10.4 deg/f (upper_arm.L f93) | floats 1.7 cm; slide 1.2 cm (L f58); snap 9.2 deg/f (upper_arm.L f38) | floats 1.8 cm; slide 1.3 cm (L f58); snap 9.9 deg/f (upper_arm.L f38) | floats 1.8 cm; slide 1.7 cm (R f59); snap 10.4 deg/f (upper_arm.L f93) | floats 2.0 cm; slide 1.7 cm (R f59); snap 9.3 deg/f (upper_arm.R f38) | slide 3.3 cm (L f64); snap 11.6 deg/f (upper_arm.L f38) | floats 1.3 cm; slide 4.6 cm (R f68); snap 11.3 deg/f (upper_arm.L f38) | - | - |
| dead | wrist 85 deg | wrist 86 deg | wrist 80 deg | wrist 86 deg | wrist 86 deg | wrist 87 deg | wrist 84 deg | wrist 88 deg | wrist 83 deg | wrist 83 deg |
| drink_bar | snap 9.5 deg/f (forearm.R f59) | snap 9.5 deg/f (forearm.R f59) | snap 9.5 deg/f (forearm.R f59) | snap 9.5 deg/f (forearm.R f59) | snap 9.5 deg/f (forearm.R f59) | snap 9.5 deg/f (forearm.R f59) | - | - | - | - |
| drive_sit | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| escort_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| fall_down | step 31.3 deg (forearm.L f17); snap 20.8 deg/f (forearm.L f19); wrist 108 deg | step 31.8 deg (forearm.L f18); snap 20.7 deg/f (forearm.L f19); wrist 106 deg | step 31.0 deg (upper_arm.L f26); snap 19.6 deg/f (forearm.L f19); wrist 104 deg | step 37.9 deg (forearm.L f18); snap 26.0 deg/f (forearm.L f19); wrist 112 deg | step 41.0 deg (forearm.L f18); snap 29.6 deg/f (forearm.L f19); wrist 113 deg | step 44.6 deg (forearm.L f18); snap 33.3 deg/f (forearm.L f19); wrist 113 deg | step 32.0 deg (forearm.L f17); snap 19.6 deg/f (forearm.L f19); wrist 108 deg | snap 15.7 deg/f (forearm.L f19); wrist 104 deg | - | - |
| fight_idle | slide 1.2 cm (L f4); elbow 152 deg | floats 1.7 cm; slide 1.2 cm (L f4); elbow 152 deg | slide 1.6 cm (R f5); elbow 152 deg | floats 1.1 cm; slide 1.6 cm (R f5); elbow 152 deg | floats 1.1 cm; slide 1.6 cm (R f5); elbow 152 deg | floats 1.2 cm; slide 1.2 cm (L f4); elbow 152 deg | - | - | - | - |
| flirt_lean | slide 1.7 cm (R f6) | floats 1.7 cm; slide 2.3 cm (R f7) | slide 2.6 cm (R f8) | floats 1.1 cm; slide 7.6 cm (R f56) | floats 1.1 cm; slide 7.4 cm (R f26) | floats 1.2 cm; slide 2.2 cm (R f7) | - | - | - | - |
| get_up | wrist 92 deg | wrist 92 deg | wrist 92 deg | snap 7.5 deg/f (shin.L f2); wrist 92 deg | snap 7.2 deg/f (shin.L f2); wrist 92 deg | wrist 92 deg | snap 10.3 deg/f (shin.L f3); wrist 92 deg | wrist 92 deg | - | - |
| handcuffed_walk | ok | ok | ok | ok | ok | ok | - | - | - | - |
| handshake | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | - | - |
| hit_react | slide 8.4 cm (R f64) | floats 1.7 cm; slide 8.3 cm (R f64) | slide 8.7 cm (R f64) | floats 1.1 cm; slide 8.3 cm (R f65) | floats 1.1 cm; slide 7.6 cm (R f65) | floats 1.2 cm; slide 8.7 cm (R f65) | - | - | - | - |
| hold_hands_walk | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hold_hands_walk_r | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| hug | wrist 75 deg | floats 1.7 cm; wrist 75 deg | wrist 75 deg | floats 1.1 cm; wrist 75 deg | floats 1.1 cm; wrist 75 deg | floats 1.2 cm; wrist 75 deg | - | - | - | - |
| idle | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |
| idle_look | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |
| injured_walk | snap 15.6 deg/f (shin.R f23) | snap 15.0 deg/f (shin.R f23) | snap 14.7 deg/f (shin.R f23) | snap 18.2 deg/f (hand.L f2) | snap 18.4 deg/f (hand.L f4) | ok | snap 17.6 deg/f (hand.L f23) | ok | ok | ok |
| jog | ok | ok | ok | ok | ok | ok | ok | ok | - | - |
| kiss_brief | wrist 104 deg | floats 1.7 cm; wrist 104 deg | wrist 104 deg | floats 1.1 cm; wrist 104 deg | floats 1.1 cm; wrist 104 deg | floats 1.2 cm; wrist 104 deg | - | - | - | - |
| kneel_enter | slide 2.8 cm (R f47) | floats 2.2 cm; slide 3.2 cm (R f46) | floats 1.4 cm; slide 2.6 cm (R f44) | floats 2.0 cm; slide 3.1 cm (R f43) | floats 1.7 cm; slide 3.0 cm (R f43) | floats 1.8 cm; slide 3.2 cm (R f41) | floats 1.7 cm; slide 3.0 cm (R f44) | floats 2.2 cm; slide 2.8 cm (R f43) | slide 2.2 cm (R f33) | slide 2.2 cm (R f33) |
| kneel_exit | slide 3.5 cm (R f30) | floats 2.0 cm; slide 3.4 cm (R f30) | floats 1.2 cm; slide 3.7 cm (R f30) | floats 1.8 cm; slide 3.8 cm (R f31) | floats 2.8 cm; slide 3.7 cm (R f31) | floats 2.9 cm; slide 3.4 cm (R f30) | floats 1.6 cm; slide 3.7 cm (R f32) | floats 2.1 cm; slide 3.5 cm (R f32) | slide 1.6 cm (R f30) | slide 1.6 cm (R f30) |
| laugh | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | - | - |
| lie_enter | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg |
| lie_enter_r | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | elbow 152 deg; wrist 112 deg | - | - |
| lie_exit | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg |
| lie_exit_r | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | elbow 168 deg; wrist 116 deg | - | - |
| listen_nod | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | - | - |
| lounge_pool | wrist 96 deg | wrist 97 deg | wrist 98 deg | wrist 97 deg | wrist 96 deg | wrist 94 deg | wrist 93 deg | wrist 90 deg | - | - |
| play_arcade | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | snap 11.7 deg/f (forearm.R f98) | ok | - | - |
| protest_fist | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | - | - | - | - |
| punch | slide 8.4 cm (L f86); elbow 163 deg | floats 1.7 cm; slide 7.7 cm (L f86); elbow 163 deg | slide 8.7 cm (L f86); elbow 163 deg | floats 1.1 cm; slide 6.7 cm (L f86); elbow 163 deg | floats 1.1 cm; slide 12.6 cm (L f42); elbow 163 deg | floats 1.2 cm; slide 7.5 cm (L f86); elbow 163 deg | - | - | - | - |
| repair_kneel | ok | floats 2.0 cm | floats 1.2 cm | floats 1.8 cm | floats 1.5 cm | floats 1.6 cm | floats 1.6 cm | floats 2.1 cm | wrist 78 deg | wrist 78 deg |
| ride_sit | - | - | - | - | - | - | - | - | ok | ok |
| run | step 43.6 deg (shin.L f9); snap 29.5 deg/f (shin.R f20) | step 42.7 deg (shin.R f19); snap 28.7 deg/f (shin.R f20) | step 39.0 deg (shin.L f9); snap 25.2 deg/f (shin.R f20) | step 48.2 deg (shin.L f9); snap 32.9 deg/f (shin.L f10) | step 47.0 deg (shin.R f19); snap 31.4 deg/f (shin.L f10) | step 46.7 deg (shin.L f9); snap 31.0 deg/f (shin.R f20) | step 44.6 deg (shin.L f9); snap 30.3 deg/f (shin.L f10) | step 45.6 deg (shin.L f9); snap 29.6 deg/f (shin.L f10) | step 47.2 deg (shin.L f9); snap 31.2 deg/f (shin.L f10) | step 47.2 deg (shin.L f9); snap 31.2 deg/f (shin.L f10) |
| shop_browse | wrist 106 deg | floats 1.7 cm; wrist 106 deg | wrist 106 deg | floats 1.1 cm; wrist 106 deg | floats 1.1 cm; wrist 106 deg | floats 1.2 cm; wrist 106 deg | wrist 106 deg | wrist 106 deg | - | - |
| shout | elbow 158 deg | floats 1.7 cm; elbow 158 deg | elbow 158 deg | floats 1.1 cm; elbow 158 deg | floats 1.1 cm; elbow 158 deg | floats 1.2 cm; elbow 158 deg | - | - | - | - |
| sit_bar_stool | ok | ok | ok | ok | ok | ok | - | - | - | - |
| sit_bench | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | floats 6.5 cm | floats 7.6 cm | - | - |
| sit_class | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | floats 6.6 cm | floats 7.8 cm | - | - |
| sit_eat | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | floats 6.6 cm; snap 9.1 deg/f (upper_arm.R f6) | floats 7.8 cm; snap 6.0 deg/f (hand.R f13) | snap 6.3 deg/f (upper_arm.R f14) | snap 6.3 deg/f (upper_arm.R f14) |
| sit_enter | slide 1.5 cm (L f38) | floats 1.7 cm; slide 1.5 cm (L f50) | slide 1.5 cm (L f53) | floats 1.1 cm; slide 1.4 cm (L f48) | floats 1.1 cm; slide 1.3 cm (L f53) | floats 1.2 cm; slide 1.4 cm (L f40) | floats 6.7 cm | floats 7.9 cm; slide 1.1 cm (R f52) | ok | ok |
| sit_exit | slide 1.5 cm (R f39) | floats 1.7 cm; slide 1.5 cm (L f41) | slide 1.5 cm (L f37) | floats 1.1 cm; slide 1.4 cm (L f46) | floats 1.1 cm; slide 1.3 cm (R f46) | floats 1.2 cm; slide 1.4 cm (L f43) | floats 6.6 cm | floats 7.8 cm; slide 1.1 cm (L f50) | ok | ok |
| sit_idle | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | floats 6.6 cm | floats 7.8 cm | ok | ok |
| sit_type | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | floats 6.6 cm | floats 7.8 cm | ok | ok |
| slap | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | - | - | - | - |
| sleep | wrist 114 deg | wrist 114 deg | wrist 111 deg | wrist 120 deg | wrist 121 deg | elbow 151 deg; wrist 121 deg | wrist 114 deg | wrist 115 deg | wrist 112 deg | wrist 112 deg |
| sleep_cell | wrist 114 deg | wrist 114 deg | wrist 111 deg | wrist 120 deg | wrist 121 deg | elbow 151 deg; wrist 121 deg | - | - | - | - |
| sleep_r | wrist 114 deg | wrist 114 deg | wrist 111 deg | wrist 120 deg | wrist 121 deg | elbow 151 deg; wrist 121 deg | wrist 114 deg | wrist 115 deg | - | - |
| sleep_turn | wrist 179 deg | wrist 179 deg | wrist 179 deg | wrist 179 deg | wrist 179 deg | wrist 179 deg | wrist 179 deg | wrist 179 deg | - | - |
| step_down | - | - | - | - | - | - | - | - | snap 7.2 deg/f (upper_arm.R f22) | snap 7.2 deg/f (upper_arm.R f22) |
| step_down_r | - | - | - | - | - | - | - | - | snap 7.2 deg/f (upper_arm.L f22) | snap 7.2 deg/f (upper_arm.L f22) |
| step_up | - | - | - | - | - | - | - | - | snap 10.5 deg/f (hand.R f5); wrist 89 deg | snap 10.5 deg/f (hand.R f5); wrist 89 deg |
| step_up_r | - | - | - | - | - | - | - | - | snap 10.5 deg/f (hand.L f5); wrist 89 deg | snap 10.5 deg/f (hand.L f5); wrist 89 deg |
| suit_swap | - | - | - | - | - | - | - | - | snap 8.7 deg/f (forearm.R f44) | snap 8.7 deg/f (forearm.R f44) |
| sulk | floats 5.9 cm | floats 6.6 cm | floats 6.6 cm | floats 7.4 cm | floats 7.1 cm | floats 7.7 cm | floats 4.1 cm | floats 5.7 cm | - | - |
| swim | snap 11.1 deg/f (shin.L f15); neck 72 deg | snap 10.4 deg/f (shin.L f15); neck 72 deg | snap 11.5 deg/f (forearm.R f19); neck 72 deg | snap 11.3 deg/f (shin.R f15); neck 72 deg | snap 11.0 deg/f (shin.R f15); neck 72 deg | snap 11.2 deg/f (shin.R f15); neck 72 deg | snap 11.7 deg/f (shin.R f15); neck 72 deg | snap 10.5 deg/f (shin.R f14); neck 72 deg | - | - |
| talk | snap 6.3 deg/f (forearm.L f42) | floats 1.7 cm; snap 6.5 deg/f (forearm.L f42) | ok | floats 1.1 cm; snap 6.7 deg/f (forearm.L f42) | floats 1.1 cm; snap 6.8 deg/f (forearm.L f42) | floats 1.2 cm; snap 6.8 deg/f (forearm.L f42) | snap 7.1 deg/f (forearm.L f42) | snap 7.1 deg/f (forearm.L f42) | ok | ok |
| talk_gesture_a | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | - | - |
| talk_gesture_b | wrist 91 deg | floats 1.7 cm; wrist 91 deg | wrist 91 deg | floats 1.1 cm; wrist 91 deg | floats 1.1 cm; wrist 91 deg | floats 1.2 cm; wrist 91 deg | wrist 91 deg | wrist 91 deg | - | - |
| talk_idle | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | - | - |
| teach | wrist 107 deg | floats 1.7 cm; wrist 107 deg | wrist 107 deg | floats 1.1 cm; wrist 107 deg | floats 1.1 cm; wrist 107 deg | floats 1.2 cm; wrist 107 deg | - | - | - | - |
| walk | ok | ok | ok | ok | ok | ok | ok | ok | snap 14.6 deg/f (shin.L f32) | snap 14.6 deg/f (shin.L f32) |
| wave | wrist 83 deg | floats 1.7 cm; wrist 83 deg | wrist 83 deg | floats 1.1 cm; wrist 83 deg | floats 1.1 cm; wrist 83 deg | floats 1.2 cm; wrist 83 deg | wrist 83 deg | wrist 83 deg | - | - |
| work_bench | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |
| work_console | ok | floats 1.7 cm | ok | floats 1.1 cm | floats 1.1 cm | floats 1.2 cm | ok | ok | ok | ok |

Faults per body: m1 50, m2 88, m3 53, f1 88, f2 88, f3 89, c1 49, c2 50, suit 29, indoor 29
