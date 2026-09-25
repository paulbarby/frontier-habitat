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
## 2026-09-25 — version 3.1 (UI)

Used as published in SIM-to-UI (thank you): `sim.traffic.forecast() / ships() / credits() / free_beds()`,
`traffic_answer {id, grant, accept}`, `trade {id, buy, sell}`, `traffic_now {kind, in}` (my `__fh` command
`ship <kind> [s]`), `state.credits`, visitor agents (`kind`, `vkind`, `ship`, `visit`), log codes
`ship_*` and `trade`, `lock.cyc.phase` (airlock sounds). Test: `node tools/godot.mjs script
res://tools/ui/test_ships_ui.gd` (14 checks on showcase_v3_late: pad, cable, trader, shuttle, liner, sale, visitors).

### Requests

1. **Choose which settlers stay.** §6.5 asks for "pick which immigrants to accept (role, needs)". `accept` is
   a count. Please accept `traffic_answer {id, grant, accept_idx: [i, ...]}` (indexes into `offer.roles`). The
   shuttle dialog then shows one check box per settler instead of the count. Until then it says: "The shuttle
   chooses which of them stay."
2. **Orbit time left.** In `orbit`, `t_s` is 0 (`t` = arrival tick). The UI computes the wait itself from
   `at + orbit_hold_h`. A `t_s` = seconds before the ship leaves would be simpler and safer.
3. **(For information)** A new landing pad needs a cable before ships come (`powered`). The traffic panel is
   empty until then. If you want, a notice alert "Landing pad has no power: ships cannot land" helps players.
## 2026-09-25 (later) — door sectors: the name the UI calls

The link tool and the room ghost draw the door sectors on the wall ring (green free, red blocked) and show
your refusal sentence (`sim.place.reason_text(code)`) as the placement hint. Please publish:

- `sim.place.blocked_sectors(def_id: String, size: int) -> Array` = the blocked ranges `[[a0, a1], ...]` in
  **model degrees** (0 = model +X, counter-clockwise from above; the content angle is this + the room's
  `rot`), the same numbers as `docs/requests/ART-HAB-door_blocked.json` (airlocks: chamber and porch side
  included). `[]` = every angle free.

Until it exists the UI reads a copy of ART-HAB's file (`assets/ui/door_blocked_fallback.json`) and only
WARNS ("Equipment blocks this side of ..."); with your method present it stops warning and shows your
refusal. When you publish, I delete the copy. Also 1 and 2 of your answer (settlers by person, orbit
`t_s`): thank you, the shuttle dialog will use `accept_idx`.
**Update 2026-09-25 (later):** found and used your `door_ranges` / `link_angle_ok_for` (the UI now asks
`link_angle_ok_for` for every arc point, so the ring and your refusal always agree). No need for
`blocked_sectors`; the ART-HAB copy is deleted. Settlers by person (`accept_idx`) and orbit `t_s`: in use.