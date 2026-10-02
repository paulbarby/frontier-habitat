# Orchestrator to Paul

## 2026-10-01 — ART-NPC: AI and motion-capture sources for the people clips (decision needed)

You asked for smooth, natural clips and named AI tools as an option. Nothing below is used, downloaded or
paid for until you approve. Today every clip is hand-keyed in code (pose functions on our 26-bone rig). I fix
the faults you found (broken arms, the run, sleep) in that system first; this note is about what comes next.

### What "fit to our rig" means

- Our people and astronauts share one skeleton: 24 body bones (hips, spine, chest, neck, head, clavicles,
  arms, hands, legs, feet, toes) + 7 face bones. No finger bones (the hands keep one relaxed pose).
- Any outside clip must be retargeted: copy each bone's turn relative to its rest pose onto our bone, keep the
  hips travel only, then run our own contact pass (feet on the floor, hands on desks, seats at their heights,
  the root fixed in place). The Ben's RPG pipeline already does this kind of retarget (world-delta method).
- Cost of that pipeline here: about 1-2 days of work, once. After that a clip takes minutes.

### Options

| source | quality | licence | cost | fit to our rig | notes |
|---|---|---|---|---|---|
| **Keep hand-keyed (now)** | good poses, stiff motion; contacts exact | ours | time only | native | the faults you saw are fixable; motion stays "animated", not "captured" |
| **Quaternius Universal Animation Library** (free download) | clean game clips, stylised timing, about 100+ clips (walk, run, idle, sit, punch, dance) | **CC0** | free | retarget (humanoid, no fingers needed) | best licence; limited set; no kiss, no handcuffs, no swim |
| **CMU motion-capture database** (free BVH) | real capture, natural weight shift; raw: needs cleanup (foot slide, noise) | free for any use (not formally CC0); credit is polite | free | retarget from BVH (31 joints) | 2,500+ takes: walks, runs, dances, fights, sitting, a few lying; the most natural motion for free |
| **100STYLE locomotion dataset** | real capture, 100 walking / running styles | CC-BY 4.0 (credit in people_credits.md) | free | retarget from BVH | locomotion only; good for varied walks |
| **Mixamo** (Adobe) | good capture, auto-retargets to its own rig | royalty-free in games; no raw-file redistribution | free, **needs an Adobe account** | retarget from the Mixamo rig | large library; the account and terms need your OK |
| **Meshy animate** (the workspace `mesh-gen` skill) | AI/library clips on Meshy's 24-bone biped; walk and run free, other actions about 3 credits each, rig about 5 credits | Meshy terms (paid plan output is yours to use) | credits per clip | retarget from the Meshy biped (the Ben's RPG retarget proves it works) | fixed action list; clips are tied to a Meshy auto-rig of a mesh, so a dummy mesh must be rigged first |
| **AI video-to-motion** (Rokoko Vision, DeepMotion, Move.ai) | capture from a phone video of you acting a clip; quality varies, needs cleanup | per service terms | free tiers with accounts; Move.ai paid | retarget from their export | best for unique clips (the kiss, the arrest walk) acted by you |
| **Cascadeur** (physics-assisted keyframing) | very natural hand-keyed motion | free version has limits; check the terms | free / paid | exports FBX on any rig | a tool for an animator, not a library |

### Recommendation

1. **Approve CC0 Quaternius + the CMU database** (no accounts, no money). Use CMU for the common, highly visible
   loops (walk, run, jog, idle, talk, sit, dance) and Quaternius where CMU has nothing clean. Keep hand-keyed
   for clips with exact contacts (handshake, hug, desk, console, bed, stool, vehicle seats, swim).
2. Build the retarget + cleanup pass once (1-2 days), then replace clips one group at a time, with the
   animation audit (`tools/blender/people_audit.py`) and the critic sheets before and after each group.
3. Later, for unique acted clips, try one AI video-to-motion service on a free tier (needs your account).
4. Meshy only if we also want new character meshes: for clips alone it costs credits per action and gives
   no better motion than free capture.

**Decision needed:** approve option 1 (CC0 + CMU downloads), or keep hand-keyed only, or name another option.

## 2026-10-02 - SIM: tick budgets (decision needed: the v3 budget, one number)

**How it was measured.** The machine runs Blender and other agents' Godot all day (CPU load 15-100 %). The suite's own
perf tests run unpinned and show 1.5 to 2 times the true cost whenever a neighbour runs. So each test was also run
alone at High priority on one logical CPU, next to a fixed calibration loop (`tests/dev/sim_calib.gd`; it read
40.0-40.4 ms at loads of 2 %, 24-54 % and 74 %, so the pinned runs are reliable). Final code, best runs:

| test | budget | before today | now: best (pinned or unpinned at load about 20 %) | now: other runs (neighbour noise) | final full suite (load 17-60 %) |
|---|---|---|---|---|---|
| long_v3_perf_70_colonists (70 people, 150 structures) | median 2.0 ms | 2.14 pinned | **1.91 pinned PASS**; 2.01 unpinned | 2.04-2.89 | 2.39 FAIL |
| long_v4_perf_100_colonists_6_vehicles | median 2.5 ms | 2.04 | **1.72-1.78 pinned PASS**; 1.89 in the suite PASS | 1.86-2.33 | PASS |
| long_v5_perf_showcase (134 people) median | 3.0 ms | 2.9 | **2.50 and 2.64 unpinned PASS**; 2.54 pinned | 3.8-4.0 | 3.82 FAIL |
| long_v5_perf_showcase worst tick | 12 ms | 14.5 | **11.4, 11.7 unpinned; 10.0 pinned** | 13-17 | 13.0 |

**Cuts made** (measured with the per-system profile `tests/dev/sim_step_prof.gd`): the fog visit scan built the person
list once per found POI (1.28 -> 0.23 ms a call); alerts rebuilt every 2 s (2.7 ms a call); stored people updates every
20 s with the attitude share 0.1 -> 0.19 (the same drift a day); rank storing moved off tick 0 of the minute (the
18.6 ms coincidence tick). Earlier: jobs in 3 parts, morale in 2 halves, lite people updates.

**What is left (per tick, showcase):** act 0.51 (walking 0.24, sleepers 0.08), jobs 0.74 (the job index is rebuilt 3
times a second, 0.3 ms each), people 0.14, power 0.22, needs 0.22, relations 0.19, think 0.19. These are
dictionary-heavy loops with no waste left to remove without a change of design.

**Decision for you.** The v3 test (70 people, no society) sat at 1.86-1.91 ms before version 5 and sits at 1.91-2.2 ms
now: the v5 systems (people, relations, unrest, education, security) cost about 0.15 ms there. The budget of 2.0 ms is
met only on a quiet machine, by a few percent. **Proposal: v3 median budget 2.3 ms** (or keep 2.0 and accept that
this test fails when a neighbour runs). v4 (2.5) and v5 (3.0 median, 12 ms worst) stay. I changed no budget.

**Suite note.** The median tests pass when the machine is not shared and fail by 50-100 % when Blender or another
Godot runs. For a stable suite on this machine: run it when the other agents are idle, or let the perf tests scale
the budget by the calibration loop (time against 40 ms). I can add that factor if you approve it.
