# Critic round 40 — people pilot rebuilt on MPFB / MakeHuman (from zero)

Date: 2026-09-30 · Critic · Rubric: `docs/critic/v5_rubrics.md` §3.1–3.3 · Pass ≥ 0.65. Blender
evidence; provisional. The full detail is in `round_40_people_mpfb.json`.

## Scores

| subject | cons. | appeal | style | score | round 31 (procedural) | result |
|---|---|---|---|---|---|---|
| people_closeup | 0.72 | 0.70 | 0.72 | **0.71** | 0.59 | PASS, provisional |
| people_outfits | 0.55 | 0.66 | 0.60 | **0.60** | 0.61 | **FAIL** |
| people_animation | 0.70 | 0.60 (cap) | 0.70 | **0.67** | 0.67 | PASS, provisional |
| robot_dancer (re-check) | 0.78 | 0.72 | 0.76 | **0.75** | 0.72 | PASS, provisional |

## people_closeup — 0.71 PASS

**What works.** At 1.5 m the faces now read as real people:
- sculpted cheekbones, brows, lids, nose and lips;
- textured skin;
- f1's strand-card bob.

The mannequin look is gone.

**The maker's weak points, checked.**

| weak point | result |
|---|---|
| m1 hard hairline | **True.** A ragged cut-out edge, the first thing the eye reads. |
| f1 pale skin | **True.** Almost white, and doll-like with the red hair and green eyes. |

**Your notes, checked.**

| note | result |
|---|---|
| Eyebrows thin and sparse | **True.** Dotted lines; f1's are faint red dashes. |
| Laugh barely reads | **True.** The mouth opens a few millimetres and the eyes do not narrow. |

**I also found:**
- a lighter skin band at the base of m1's neck (a seam);
- f1's wide, fixed stare in the front view.

## people_outfits — 0.60 FAIL

**What works.** Real cloth: denim and cargo folds and pockets, ribbed necklines, soled shoes.

**Faults.**
- **Not to contract.** uniform_engineering is a department-coloured polo with cargo jeans, with no
  coverall, stripe or tool belt. At the room camera it reads as a tourist in a yellow polo.
- **Ragged hems.** The polo and tee hems are torn and uneven; the cut step damaged the edge.
- **Midriff gap.** The casual tees end above the jeans, so skin shows at the waist from every side.
- **A-pose.** The idle arms hang out with splayed fingers.

## people_animation — 0.67 PASS

- **Cap applied.** In the hug the partners pass through each other: her forearm comes out through
  his back (frames 41–62), and her head enters his face (frame 82). Appeal is capped at 0.60.
- **What works.** Talk, laugh (the body), argue and bar stool read on the new bodies. The checks
  pass, and the hug choreography is right.
- **Still weak.** The A-pose idle. dance_a is a sway. Argue and talk look alike.

## robot_dancer — 0.75 (round-38 fixes)

- **Landed:** the hip block with a panel line and caps, thicker thighs, knee plates, and a dance_b
  step routine with a turn.
- **Tone:** PASS, unchanged.

## Gap to "stunning"

- **Now 0.71.** MPFB has already reached the ceiling I gave the procedural route.
- **0.80 is reachable with MPFB:**
  - soft alpha hairlines;
  - real brows;
  - warmer, varied skin;
  - expression shape keys (smile, laugh with teeth and narrowed eyes, frown);
  - the neck seam fixed;
  - relaxed hands;
  - contract uniforms with clean hems.
- **0.90 needs more than MPFB defaults:**
  - skin shading with subsurface in Godot;
  - wet eye highlights and lid shadow;
  - anisotropic hair;
  - hand-authored uniforms per variant.

## Fixes (ART-NPC), most important first

1. **Uniforms to contract.** A coverall or work jacket with coverall trousers, the amber department
   stripe on the chest and sleeves, a tool belt and boots. Derive the other uniforms from this cut.
2. **Hems and length.** Clean every hem with a hem strip, and lengthen the casual tops to cover the
   waistband by 4–6 cm.
3. **m1 hairline.** Alpha hair cards, or a proxy hair with a soft edge.
4. **Eyebrows.** Full brow meshes or textures on every variant.
5. **Skin.** A warmer f1 default and a visible tint range. Fix the m1 neck seam.
6. **Expressions.** Shape keys for smile, laugh, frown and surprise, driven in the clips.
7. **Hug and hands.** Hug overlap ≤ 2 cm. A relaxed idle with curled fingers, and arms 8–10° from the
   body.
8. **dance_a and argue.** Hip and knee motion in dance_a. A pointing hand and a lean-in for argue.
