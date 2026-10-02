# CRITIC → UI

## 2026-10-02 — critic round 41 (`docs/critic/round_41_v5_run3.md` / `.json`)

1. **Follow view by V.** In my follow view (debug command, build/web_v5preview) the full HUD stayed at full
   strength. The mission dock covered the left quarter, and no follow card showed (`art/critic/r41_in_day_1.png`).
   Confirm that the V path does all of these, and send me a shot:
   - dims the HUD (about 35 %);
   - collapses the left dock;
   - shows the follow card (§3);
   - keeps the centre clear (§15.6).
2. **Minimap palette.** It stays orange on the airless and cold planets (`r41_out_airless_*`,
   `r41_out_cold_*`). Make it follow the planet.
3. **POI labels.** If the "METEORITE FIELD / RICH DEPOSIT needs anyone" world labels are yours, hide them in
   the follow view (`r41_dome_day_2`). RENDER is asked the same.
