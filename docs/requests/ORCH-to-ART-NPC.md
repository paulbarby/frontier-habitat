# Orchestrator to ART-NPC

## 2026-10-01 — Paul: animations break realism in the over-the-shoulder view (DO FIRST on resume)

Evidence: `docs/requests/shots/paul_2026-10-01_crate_pose.png` (a person reaching into a storage crate:
the torso bends from the hips at a broken angle, shoulders hunched up into the neck, arms bent wrong).

Paul's words (summary): the bone rigging is broken in a lot of actions; they do not look natural. Sleep
animations must be much smoother. The run looks unnatural: the arms are held out and the person is not
grounded (floats). Review and fix every clip. Consider AI 3D animation tools to get smooth, seamless clips.

Do:
1. Review every clip (people m1-m3, f1-f3, c1-c2 and astronauts) on a turntable sheet with the feet at
   ground height drawn. Measure per clip: foot height when planted (target 0 +- 1 cm), foot slide when planted
   (target < 1 cm per step), joint angles out of human range, interpenetration with the body. List each fault.
2. Fix the rig: weights at shoulders, neck, spine and hips (the crate pose shows shoulder/neck collapse);
   bone rolls; IK limits.
3. Run cycle: arms close to the body with a natural swing, forward lean, a flight phase with correct ground
   contact, root height matched to leg length. Same for walk.
4. Sleep: lie-enter, sleep and lie-exit blend with no snaps (no frame-to-frame jump over 5 deg on any bone);
   breathing loop; turn-over variant.
5. Option to evaluate (needs Paul's approval before any account, download or paid API): AI or motion-capture
   sources for smooth clips, retargeted to our rig. Candidates: the Meshy API (this workspace has a
   `mesh-gen` skill with a merged animation pack, used for Ben's RPG); CC0 / free motion-capture libraries.
   Write a short comparison (quality, licence, cost, rig fit) for Paul in docs/requests/ORCH-to-PAUL.md.
6. Report numbers before/after; sheets in art/people/ for the critic.

## 2026-10-01 (later) — Paul: sleep pose, the arm goes through the body

Evidence: `docs/requests/shots/paul_2026-10-01_sleep_arm.webp` (f-variant asleep on a bed, on her side, knees
up: the lower arm passes through the torso; also seen: the tee ends above the trousers (midriff gap), the
body looks to hover above the mattress, shoes on the bed).
Paul: "don't let that happen, fix the pose".
Do: fix the sleep and lie poses of every body so no limb passes through the body or the bed (arm in front of
the chest or under the pillow); body rests ON the mattress (contact, no gap); add a self-intersection check
for every pose and every clip frame (limb capsules vs torso capsule) to npc_verify, failing at any overlap.
Also check the outfit midriff gap in the lying pose.
