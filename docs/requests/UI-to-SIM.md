# UI → SIM

## 2026-09-24 — version 3 (V3_DESIGN §2, §4, §5, §8)

The interface calls the contract names now and falls back safely when a name is missing
(`.get()` and `has_method`). Below: what the UI reads today, what it guessed, and four small
additions it needs. File references are to `ui/data.gd` unless named.

### A. Already matched to your code (no action; tell me if a name changes)

| UI reads | your code |
|---|---|
| `sim.research.lab_info(lab: Dictionary)` → `focus, mult, mult_boosted, boosted, can_work, packs` | `sim/research.gd` |
| `sim.research.lock_reason(tech) -> String` (shown under "Why it cannot run now") | `sim/research.gd` |
| content `techs[t].packs {item: n}` (nodes and detail panel) | `content/research.json` |
| `set_focus {id, branch}` ("" = no focus) | `sim/commands.gd` |
| `sim.ship.info().cargo`, `.cargos {kind: {item: n}}` | `sim/ship.gd` |
| `ship {action: "supply_run", cargo}` | `sim/ship.gd` |
| `maintain {id}`, `shelter {on}`, `hazard_now {...}` | `sim/commands.gd` |
| issue field `live` (false while an alert waits `clear_after`) → card shows "CLEARING", dimmed | `sim/alerts.gd` |

### B. Guesses — please confirm or tell me the real name

1. **Hazard API** (§4.4): `sim.hazards.forecast()`, `active()`, `at_risk()`, `zone_at(pos)`.
   Rows read: forecast `{id, kind, name, eta_s, pos, radius, severity, countered, advice}`; active rows
   the same plus `end` (tick) or `left_s`; at_risk `{id, wear, fail_at, eta_s, fault}`; zone_at
   `{meteor, wind, quake}` (0.5..2.0). `pos` may be a Vector2 or `[x, y]`; `null` = whole map.
2. **Shelter state**: the UI reads `state.hazards.shelter` (bool, or `{on: bool}`), else
   `state.policies.shelter`. Which one is it?
3. **`hazard_now` payload** from `__fh.cmd("hazard <kind> [x y] [sev]")`:
   `{kind, severity, x, y, pos: Vector2(x, y)}` (x, y, pos only when given). Use whichever you like.
4. **Building fields**: `wear` 0..100, `fail_at`, `fault` ("mechanical" | "electrical" | "seal"),
   `breach` (bool or Dictionary), turret `charge`; turret def keys `turret: true` or
   `intercept_range` (m), `charge_cap`, `charge_per_shot`; turret `stats.intercepts`.
5. **Log codes the UI toasts once each** (`ui/hud/watchers.gd` HAZARD_LOG): `hazard_impact` or
   `impact`, `hazard_end`, `breach`, `fault`, `repaired`, `intercepted`, `maintained`. Detection and
   warnings should come as **alerts** (warning or critical): the UI toasts each alert key once, per §2.
   Tell me your codes and I change one table.
6. **Pack recipes**: the Labs page shows `recipes[<pack item id>]` (for example `recipes.pack_basic`)
   as "Recipe: water 1 -> 1 pack". Is the recipe id the item id?
7. **`options.hazards`** ("off" | "mild" | "normal" | "hard") and **`options.debug`** (bool) are passed in
   `sim.new_game(seed, "tutorial", options)` from the new-colony screen and the boot parameters
   `hazards=` and `debug=1`. `state.options.hazards` is shown on the Hazards page.

### C. Needed additions

1. **Per-lab rate.** §8 asks for "each lab's rate (base vs boosted)". `lab_info` gives multipliers only.
   Please add `rate` (RP per game day of this lab, a one-minute average like `rp_rate()`) and, if easy,
   `base_rate` (the same without packs). The UI shows them as soon as the keys exist.
2. **Set the cargo without a flight.** The Meridian panel lets the player pick the cargo. Today the only
   way to store the choice is `ship {action: "supply_run", cargo}`, which also flies. An unknown action
   keeps the cargo but returns `invalid`, so the player sees "Refused". Please accept
   `ship {action: "cargo", cargo}` → `{ok: true}`. Until then the UI keeps the pick locally and sends it
   with the next "Supply run" press.
3. **Debug on a loaded save.** `debug=1` with `load=<save>` cannot set `options.debug` (the UI must not
   write state). Please give a way: for example `sim.load_state(state, {debug: true})` or a
   `sim.set_debug(on)` that is not saved. Until then `hazard <kind>` works only in a new game started
   with `debug=1`.
4. **(Optional) `sim.hazards.info(id)`** fields the UI could show on click: `hits`, `result` after the
   event (damaged structures, breaches, people hurt) — for an "after the event" toast line.

### D. UI side of §2 (for your test)

`ui/hud/alert_gate.gd` + `tools/ui/test_alert_gate.gd`: a toast only for a new key (warning or
critical), never again for 180 s after it cleared; notices never toast; `blocked:<id>` keys count as
one alert `output_blocked`. Run: `node tools/godot.mjs script res://tools/ui/test_alert_gate.gd`.

### E. Update 2026-09-24 (later) — your hazards.gd landed; UI now uses it

Matched: `forecast()` / `active()` rows (`end_s`, `whole_map`), `info(bid)` for wear, fault,
item, breach and turret, `at_risk()`, `sheltered()`, `zone_at()`, `turret_range(b)`, log codes
`hazard_detected/start/impact/intercepted/end`, `breach_sealed`, `shelter`, `survey` (toasted
once each; `breach`, `fault`, `maintained`, `hazard_warning` are not toasted because your alerts
cover them), `load_state(state, {debug: true})`, `hazard_now {in}`. Items B1–B5 and C3 are closed.
Still open: **C1** per-lab `rate`, **C2** `ship {action: "cargo"}`.