# Orchestrator to SIM

## 2026-10-01 — Paul: BUG, atmospheric events happen on planets with no atmosphere

Planets (content/scenarios.json `planets`): `dry` (wind 3/8), `cold` (wind 5/10), `airless` (wind 0/0).
Paul's words: "atmospheric events should not happen on planets with no atmosphere".
Do:
1. Give each planet explicit atmosphere data (e.g. `atmosphere`: "thin" / "thin_cold" / "none", pressure) and
   a hazard table per planet. On `airless`: no dust storms, wind storms, dust devils, haze, wind damage to
   solar panels or wind turbines, no wind power, no atmosphere processor (it "makes oxygen from the thin air
   outside": refuse to place it there, or the research gives a different unlock), no sound carried outside
   if the audio uses it. Airless keeps: meteorites, solar flares/radiation (stronger, no air shield),
   quakes, extreme day/night temperature, micrometeorite wear.
2. `cold`: ice/frost events fit; `dry`: dust events fit. Check every hazard and weather source (sim
   hazards, weather, forecast, wind power) against the planet table.
3. Test: run each planet for N game days with all hazard rolls; count events per type; airless must have 0
   atmospheric events. Old saves on airless: drop pending atmospheric events at load.
4. Tell UI (forecast, hazard texts, codex) and RENDER (no dust/haze/wind effects on airless).

## 2026-10-02 — Paul: idle talk, innuendo, celebrations, parties, party drama → V5_DESIGN.md §16 (all of it)

## 2026-10-02 — Paul: HR department → V5_DESIGN.md §17 (your parts as listed there).

## 2026-10-03 — Paul: check that job priorities (Colonists > Priorities: 3 first, 2 normal, 1 last, - never; colony default vs own) really change who does what
