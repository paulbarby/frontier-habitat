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
