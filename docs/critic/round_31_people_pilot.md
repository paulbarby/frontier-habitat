# Critic round 31 — v5.0 people pilot (m1, f1; Blender, provisional)

Date: 2026-09-29 · Critic (did not build the work) · Rubric: `docs/critic/v5_rubrics.md` §3.1–3.3 ·
Pass ≥ 0.65. Judged strictly against Paul's "stunningly modelled" aim (0.80–0.90 at 1.5 m). The full
detail is in `round_31_people_pilot.json`.

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| people_closeup | 0.66 | 0.52 | 0.58 | **0.59** | **FAIL** |
| people_outfits | 0.66 | 0.54 | 0.62 | **0.61** | **FAIL** |
| people_animation | 0.70 | 0.62 | 0.68 | **0.67** | PASS, provisional |

## Evidence

- `art/people/people_closeup.png`, `people_outfits.png`, `people_faces.png`, `people_clips.png`.
- `assets/models/people_m1.glb`, `people_f1.glb`, `people_manifest.json`, `npc_pairs.json`.
- The maker's log: `docs/progress/ART-NPC.md` (v5).
- My crops: `art/critic/r31_hug.png`, `r31_bar.png`.

## The maker's weak points, checked

| weak point | verified |
|---|---|
| Mannequin faces | **True.** |
| One open hand pose | **True.** |
| Puffy or blocky shoulders | **True.** |
| Simple mouth interior | **True.** A dark hole with ragged lips. |

I found more (below).

## people_closeup — 0.59 FAIL

**What works.**
- Human proportions, with two distinct variants.
- Eyes with an iris and a highlight, brows, nose, lips, ears, eyelids, a jaw bone, five-finger hands.
- Within budget.

**Faults at 1.5 m.**
- **Faces.** Flat planes with no cheekbone, brow ridge or nasolabial form, painted lips, a blocky jaw.
- **f1's eyes.** Too large, saturated blue, with a sclera ring all round, under a stern brow. The stare
  leans uncanny.
- **Hair.** A helmet cap with a jagged stair-step hairline (m1), and flat cards with gaps (f1).
- **Seams.** Jagged at the neck base, the tee neckline and the hairline.
- **Skin.** Flat, painted plastic.

## people_outfits — 0.61 FAIL

- **What works.** The coverall reads as work wear: collar, zip, pockets, belt, amber stripe. The casual
  wear reads as off duty.
- **No cloth folds** at elbows, knees or waist.
- **Shoulders.** Blocky pads on the uniform; balloon sleeves on the tee.
- **f1 casual.** The navy tee and jeans read as one onesie, and the hips bulge behind.
- **Surface detail.** Pockets are flat boxes, and the neckline is ragged.

## people_animation — 0.67 PASS, provisional

- **What works.** Six clips read. The verify checks pass (441/0, 165 PASS). The hug meets.
- **Hug overlap.** The bodies overlap more than 2 cm at the hold, and one thumb sticks up behind the
  back.
- **Arm line.** The arms hang 25–30° out with splayed hands, so the v3 A-pose fault is back.
- **Small gestures.** Argue and talk look alike, and dance_a barely moves.

## Can the procedural approach reach 0.80–0.90 at 1.5 m?

**No, in my judgement.**

- With the fixes below it can reach about **0.65–0.72**: an acceptable stylised crowd.
- 0.80+ needs sculpted form (cheekbones, eyelid folds, lip volume, cloth folds) and authored textures
  (skin variation, normal maps, alpha hair cards). Primitive-based scripts do not produce these.
- **Two realistic routes:**
  1. A hand-sculpted, retopologised base head and body per sex, varied by shape keys.
  2. A licensed stylised base mesh, or an AI generator such as the Meshy pipeline used in town-sim.
- Both are outside V5 §0 ("no downloads, no installs").

**Recommendation to the orchestrator:** raise a decision-needed task for Paul. Choose between:
- the procedural stylised look near 0.70; or
- one authored or generated base mesh per sex, with the source named, to aim at 0.80+.

## Fixes (ART-NPC), most important first

1. **Faces.** Form by shape keys or displacement: cheekbones, brow ridge, nasolabial fold, jaw curve,
   lip volume. For f1: iris to about 45% of the opening, less sclera, and a neutral brow.
2. **Hair.** Alpha cards with a soft hairline. The f1 bob in 12–16 curled cards; the m1 crop with a
   fade.
3. **Seams.** Weld and smooth every one: the neck base, hairline and neckline.
4. **Skin.** Colour variation, a faint noise normal, and AO in the eye sockets and under the nose.
5. **Mouth interior.** Teeth rows and a tongue, and clean lip edges.
6. **Hands and arms.** A relaxed curl, a fist, a point, a grip. Arms 8–10° from the body in idle.
7. **Cloth.** Folds at elbows, knees, waist and armpits. Set-in sleeves instead of pads and balloons.
8. **f1 casual.** Two values for the top and jeans, a waistband, less rear hip volume.
9. **Pockets and belt.** Flaps, stitching and a buckle. Different roughness for canvas, knit and denim.
10. **Animation.** The hug overlap to ≤ 2 cm, with the thumb in. A larger, asymmetric argue. Hip and
    knee motion in dance_a.

**Evidence gap:** the 1.5 m sheet frames the torso, so the head is about 110 px. The rubric's face
check (300–450 px) comes from `people_faces.png`.
