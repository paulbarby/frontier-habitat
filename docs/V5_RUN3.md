# v5 run 3 — shared rules and the definition of done (orchestrator, 2026-10-02)

Paul: "get this amazing creation completed so we can have fun". Goal: Frontier Habitat 5.0 ready to release.

## Rules for every agent
- Read: docs/V5_DESIGN.md (all, including §15 scope change), your docs/progress/<AGENT>.md (last 3 sections),
  every docs/requests/*-to-<AGENT>.md and ORCH-to-<AGENT>.md (Paul's notes, with screenshots in
  docs/requests/shots/).
- Ownership: V5_DESIGN.md §13. Do not edit files you do not own; ask through docs/requests/<YOU>-to-<OWNER>.md
  (append, dated).
- Never open windows on the user's desktop. Blender only with --background. Godot only through
  `node tools/godot.mjs check|test|script|import|export` (env FH_ORCHESTRATOR=1). Browser only headless through
  tools/shoot.mjs and the probes.
- No git commit or push (the orchestrator commits). Export only to build/web_<agent lowercase>.
- Scratch files start with your agent prefix. Run Godot tests one at a time when you can (parallel runs share
  user settings and give false failures). If `check` fails in a file you do not own, wait and retry.
- No downloads, accounts or paid APIs.
- Prove each fix with a measurement or a test before you report it. Report numbers before/after.
- Log every milestone in your progress file (dated v5 section): what landed, numbers, not tested.
- Final reply: short factual sentences: what landed, numbers, checks with RESULT lines, what remains.

## Definition of done for 5.0 (all must hold)
1. Follow view: straight walking indoors and outdoors head jitter < 0.5 px, camera jerk < 2 mm (probe
   in1/in4/out1/dome1); roofs on; no weather inside; no body through the camera.
2. People: npc_verify 0 failures (no limb through body or bed, planted feet within 1 cm, no snaps > 5 deg);
   natural run/walk/sleep; critic people_outfits, people_closeup, people_animation >= 0.65.
3. Furniture: no seated or lying body overlaps furniture (render check, all room types).
4. Interiors: detail pass with the §15 style in every room type; jail and distillery rebuilt; critic >= 0.65.
5. UI: one panel manager; all UI tests pass; help, codex, What's new and loader tips describe every v5 feature.
6. SIM: full suite passes including perf budgets (or Paul accepts new budgets with numbers); showcase_v5
   rebuilt with no deaths; airless hazards correct.
7. Checks: code check 0 failed; path, airlock, cut, seat checks pass; audio probe passes; pck <= 200 MB.
8. Planets: airless, cold, dry each look right (shot sheet; critic >= 0.65).
