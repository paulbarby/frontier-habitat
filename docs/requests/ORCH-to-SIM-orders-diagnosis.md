# ORCH to SIM and UI: why a repair order does not work (diagnosis and fix plan)

Date: 2026-10-04. Request: Paul, after playtesting. Design: `docs/V5_DESIGN.md` section 18.1 to 18.4.
Paul's words: "when I give orders and instruct NPCs to repair worn systems, it seems to be the last thing they
ever do. In fact I can't even get them to do it." And: an order is carried out at once, even if the colonist is
at a party. The colonist does not sleep first. He does not finish his routine first.

All file references are relative to `C:\Users\paulb\Claude\frontier-habitat`.

## 0. How to read this file

| Term | Meaning |
|---|---|
| Baseline | The code before 06:14 on 2026-10-04. It equals git HEAD 0ba38d0 for `sim/`. A copy is in `C:\Users\paulb\AppData\Local\Temp\claude\C--Users-paulb-Claude\3e85b8ec-b327-451b-9189-747f18841889\scratchpad\baseline`. |
| Now | The working tree at about 06:30. Another process (SIM and UI work for section 18) edits it. Sections 1 and 2 use baseline line numbers. Sections 3 and 4 say "now" when they use current line numbers. |
| Probe U, S, R | The three investigations. U = UI paths. S = SIM order latency. R = reproduction run. |
| Probe O | A new probe by ORCH on the working tree (section 3). |
| Test save | `content/saves/showcase_v5.fhsave` (day 18, 36 technicians). It is not Paul's playtest save. Paul's autosave is day 0.5 and holds no playtest state. |

No game file was edited by the investigations. Scratch scripts are in `tests/dev/diag_*.gd`.

## 1. Confirmed root causes

Each cause has file:line (baseline) and the evidence. A cause is "confirmed" when at least two probes agree or
one probe ran it and the code agrees.

### RC1. There is no repair order. "Maintain now" is a flag, not an order.

- `sim/orders.gd:21` KINDS = go, stay, return, board, work_at, survey. No repair kind. `ui/v4_data.gd:133-134` maps the same six kinds.
- "Maintain now" sends command `maintain`. `sim/hazards.gd:1109-1117` (`cmd_maintain`) only sets `b["maint_first"] = true` and returns ok. It picks no colonist. It makes no task. It frees no part.
- `maint_first` only raises the task emergency to 6 (`sim/jobs.gd:855-857`, score +300 at `jobs.gd:1192-1221`). The score ranks a task that must already exist.
- Evidence. Probe U: 4 machines, command ok, 240 s, no maintain task, wear rises, stat `maintenance` stays 1. Probe R `maintain_now_nospares`: 900 s, `maint_first` true, 0 tasks.

### RC2. A `work_at` order never interrupts a plan, and the colonist reads it last.

- `sim/orders.gd:240-241`: `abort_plan` runs for every kind except `work_at`.
- `sim/agents.gd:509-510`: a non-empty plan returns before the order code. `orders.think` runs only at line 517 when the plan is empty.
- After that the colonist runs the needs ladder: drink and eat (525-528), sleep (529, `_wants_sleep` at 735-738: fatigue 60, or 40 at night), heal (531), duties (535: class, protest, HR visit, patrol, venue shift), then `_try_work` (537).
- Roles `hr` and `security` never reach `_try_work` (`agents.gd:537`). The order is accepted for them (`orders.gd:164-167` checks only that the structure exists).
- Measured delay before the ordered colonist starts work (Probe S, other technicians set to repair priority 0):

| Colonist state at order time | Start of work |
|---|---|
| Sleeping | +98 s |
| Party guest (160 s party) | +153 s |
| Harvesting | +43 s |
| 60 s recreation | +53 s |
| Shop staff (leisure.gd:281-299 starts a 60 s shift again and again) | never in 200 s |
| Security or HR | never; patrol or desk 60 s after the order |
| In class (Probe U) | plan stays `class` for 122 s |

- The same orders `go`, `stay`, `return`, `board`, `survey` call `abort_plan` and start at once (Probe S: +1 s; Probe R: +1 s). Only `work_at` does not.
- The goal label says "Working at X (order)" at once (`orders.gd:243`). The colonist is asleep or at a party. The label is false.

### RC3. Parties take ordered colonists and ignore the order.

- `sim/party.gd:456-457` calls `agents._start_personal(a, "party", ...)`, which calls `abort_plan` (`agents.gd:674`). `_recruit` (`party.gd:484-514`) does not test `a["order"]`. It skips the plan check for honoured people and friends (`party.gd:503-506`).
- Probe S S16: a colonist in the middle of a `work_at` repair is pulled to a party. He returns after 160 s and resumes.
- A party length is 100 to 220 s (`content/society.json:130-135`).

### RC4. `work_at` is a task filter, not a command, and it never ends.

- `sim/orders.gd:293-300` `allows()` returns true only for a task at that structure. `orders.think` for `work_at` returns false and clears the order only when the structure is gone (`orders.gd:338-341`).
- No task is made. If no task exists at the structure, the order does nothing, and the player gets no warning.
- After the work is done the colonist keeps the order. He takes no other task (`agents.gd:946-948`).
- Evidence. Probe S S2: repair done after 82 s, then 400 s idle with the order held; a second worn structure was ignored. Probe R: order active 900 of 900 s in 5 runs. Task seconds in 900 s: 0 to 75 for `work_at`, 86 to 186 for `go` (a `go` order ends on arrival).
- Result for the player: one `work_at` order removes a colonist from the colony workforce until the player clears the order.

### RC5. In the real game, another technician takes the new task first.

- `agents.gd:944` skips any task with an owner. In Probe R, with parts in stock and 36 technicians, another colonist owns a new maintain task at t+5 s. The ordered colonist (asleep, at leisure, or at a party) owns nothing.
- The colonies maintain worn machines without any order when parts exist. Probe R control: 4 worn machines done at t+100 to t+134 s, no order given.
- So the order has nothing to do, and still holds its colonist (RC4).

### RC6. Spare parts block repair and maintenance, and nothing tells the player.

This is the cause of "I cannot get them to maintain things" in the test save. Six parts of it:

1. **Reservation order.** `jobs.gd:46` runs `_gen_repair` before `_gen_hazard_work`. `_gen_repair` (`jobs.gd:805-833`) loops `for id in blds` (line 808). It gives one part to every structure with health under 70 or state broken. The lowest building ids get the parts first. It does not rank by urgency. No part is left for maintenance (`_item_task`, `jobs.gd:888-899`, returns false without a message). Probe R probe6: 6 parts, 6 repair tasks in 1 s, no maintain task. Probe S S14: 6 of 10 parts held by 2 broken greenhouses and 4 non-urgent repairs.
2. **No source in the test save.** `showcase_v5` has no Workshop. Nothing makes spare parts (recipe `spares`: 1 metal + 1 polymer gives 2 parts, `content/recipes.json:7`, `buildings.json:28`).
3. **The only 4 parts are unreachable.** They lie in ground pile 3639 (landing pod). `nav.plan` gives `no_path` for all 36 technicians (Probe S S21). `find_source` skips a resting pile (`jobs.gd:232`, `source_unreachable` at 1056-1065, `SOURCE_REST_SECONDS` 60). Probe U watched the cycle: at tick+524 the pile rest ends, `_gen_repair` makes 4 repair tasks on pile 3639, 4 ticks later the tasks are gone and the pile rests again.
4. **Silent failure.** `jobs.gd:821-824` sets `block = "no_spares"` only for a broken structure. A worn structure gets no block. The alert "machines need maintenance soon" (`alerts.gd:575-577`) does not check stock. The alert for a broken structure (`alerts.gd:273-279`) says "Make or buy some" and names no Workshop and no chain.
5. **Threshold.** A structure gets a repair task at health under 70 (`balance.json:80`). Health falls 2 a day from day 5 (`balance.json:76-77`). The wait is about 15 days. A machine gets a maintain task at wear 75 percent of `fail_at` (`hazards.gd:968-971`). One repair gives +25 health (`balance.json:81`). A structure at health 18 needs 3 parts, one after the other.
6. **Stock chip.** The dashboard chip "N of M" uses the colony total (`dashboard_screen.gd:709-711`). It counts parts that are reserved or that nobody can reach.

Not a cause: job score (`jobs.gd:1192-1221`). Open worn repairs score 189 to 229. Build tasks score 179. Hauls score 28 to 62. Probe S S18 (no orders, parts in stock): technicians claim worn repairs in 2 to 30 s and finish in 50 to 110 s. Repair needs no skill (`balance.json:82`, `agents.gd:1546-1555`).

### RC7. A hard role gate.

- Repair, maintain, patch, upgrade and vbuild tasks carry role `technician` (`jobs.gd:828, 893`). `_try_work` drops other roles (`agents.gd:950-951`). Only `work_at` skips it.
- A repair order to a non-technician must run too. The order, not the role, decides.

### RC8. The UI hides the failure and offers no repair verb.

- **Optimistic toast.** "Maintenance of X is the next technician job." shows before the sim answers (`inspector_sections.gd:1286-1290`, `dashboard_screen.gd:714-717`). The sim answers ok with no part and no technician.
- **No pending state.** No marker, no assignee, no time estimate. `ui/data.gd:941` computes a `first` flag. No UI reads it.
- **No button for a broken machine.** "Maintain now" needs `state == "active"` (`inspector_sections.gd:1286`, `hazards.gd:1109-1117`). The dashboard card (`dashboard_screen.gd:619-640`) uses `at_risk()` (`hazards.gd:1044-1062`), which lists only active machines. The card can say "No machine is near failure" while one is broken.
- **`work_at` is the only order that reaches repair.** The path is inspector footer "Orders...", then "Work at...", then a map click (`orders_window.gd:92, 216-237`). The order row shows "Order: work at" with no structure name (`v4_data.order_of` returns target null for `work_at`).
- **Other screens.** The person window has no Orders button. Right click gives no menu (`main.gd:1325-1335`). The WORN badge is not clickable (`world_view.gd:3201-3204`). The alerts panel and the Advisor have only "Show". The Priorities tab sets a preference, not an order. The Crew screen has no team orders.
- **Pick bug.** An agent within 1.6 m of the click wins the pick (`world_view.gd:3593-3606`). "Work at..." then says "that is not a structure" (`orders_window.gd:217-220`).
- **Wrong tooltip.** "3 is first. 0 is never." (`inspector_sections.gd:1300`, now 1325). The building priority is clamped to 1..3 (`jobs.gd:1208`). 0 never excludes a task.
- **WORN badge threshold.** `world_view.gd:3203` hard-codes 0.75. The sim uses `risk_frac()` (`hazards.gd:968-971`), which research can change.

## 2. Disagreements between the investigations

| # | Point | Probe U | Probe S | Probe R | Which the evidence supports |
|---|---|---|---|---|---|
| D1 | Why "Maintain now" makes no task in the test save | `_gen_repair` makes 4 repair tasks on pile 3639. They vanish after 4 ticks. Reason not read. | `find_source` returns -1. The pile is unreachable (`no_path`, S21). | Same as S. `find_source` is -1 for Habitat 1. | All three agree. The pile is unreachable. U saw the 60 s rest cycle of `source_unreachable`. S and R saw the result between cycles. No conflict. |
| D2 | Does the ordered colonist do the work? | Not measured. | Yes, after 43 to 153 s. | No. Another technician finishes first. Task seconds 0. | Both are right for different set-ups. S set the other technicians' repair priority to 0, so only the ordered colonist could take the task. R left them free. The real game is R. The order is lost in the race (RC5) and the colonist stays tied (RC4). |
| D3 | Size of the delay for a party guest | Not measured. | +153 s (party ran its full 160 s). | 118 s (thirst 85 ended the party). | Not a conflict. The cause of the end differs. Both show the order waits. |
| D4 | Delay for a sleeping colonist | Not measured. | +98 s (fatigue 80). | Sleeps until t+61 s, then drinks and eats (fatigue 55). | Not a conflict. Sleep length depends on fatigue. |
| D5 | Is `work_at` the repair order? | `work_at` is the only colonist order that can reach repair. Maintain now is a flag. | `work_at` is a filter. There is no repair order. | Same as S. | All three agree. `work_at` is not a repair order (RC1, RC4). |
| D6 | Does a test save show Paul's failure? | Not stated. | No. Paul's autosave is day 0.5 with 8 parts. | Used `showcase_v5`. | Not proven. See section 5. The code causes (RC1, RC2, RC4) hold in any save. RC6 holds in the test save. |
| D7 | Role gate | An `hr` colonist accepts a `work_at` order and ignores it (run, 122 s). | `hr` and `security` accept it and ignore it (run, S10). | Code reading only. | Run by U (hr) and S (hr, security). Confirmed. |

No investigation contradicts another on a fact. D2 is the one that changes the fix. A fix that only makes
`work_at` interrupt sleep would not help the player. Another technician already takes the task. The order must
make or take the task itself (section 4, S1 and S6).

Probe U's `diag_ui_orders_e2e.gd` is invalid. It ran while `agents.gd` called `orders.drive` before `orders.gd`
had the function. Do not use it.

## 3. State of the working tree (checked 2026-10-04, about 06:30)

Another process has already coded much of section 18. Probe O ran on this tree. The tree was still changing.

### 3.1 What is in the tree now (read, not all run)

| Item | Where (now) |
|---|---|
| New order kinds `repair`, `maintain`, `build`, `haul`, `task`. `TEAM_KINDS` | `sim/orders.gd:25-27` |
| `repair_need(b)`: repair if health under 99.5 or broken; patch; clean; maintain | `sim/orders.gd:429` |
| `_imminent`: air, drink and eat at 42.5, sleep at 85, heal under 30 | `sim/orders.gd:443` |
| `drive(a)`: aborts any other plan, then calls `think` | `sim/orders.gd:463` |
| `agents._think` calls `drive` after the critical needs, before the plan-empty return | `sim/agents.gd:509-512` |
| `jobs.order_task` takes an open task, takes a task from a colonist who only walks to it, or makes one; returns `missing` or `busy` | `sim/jobs.gd:840` |
| `agents.start_task_for` | `sim/agents.gd` (new function, after `_try_work`) |
| Team order to a department head | `sim/orders.gd:246`, `sim/workq.gd:80` |
| Work queue and score adjust | `sim/workq.gd`, `sim/jobs.gd` end of `score` |
| Chains and missing-item alerts | `sim/chains.gd`, `sim/alerts.gd:25` |
| UI: `SIM_KIND` has repair, maintain, build, haul; Work window; Assign window; Chain window; "Repair now" opens the assign window | `ui/v4_data.gd:133`, `ui/hud/work_window.gd`, `assign_window.gd`, `chain_window.gd`, `inspector_sections.gd:1306-1312` |

A department head who gets an order gives it to subordinates. Probe O saw this: "Captain of Maintenance Oren
assigned Carlos and Hana to work at HR Office 4." The probe then used `direct: true` to give an order to one
colonist.

### 3.2 Two defects that Probe O found in the tree (run, not inferred)

Probe: `tests/dev/diag_orch_thrash.gd`. Subject: Teo Lindqvist (technician, not a head), fatigue set to 70.

**T1. `drive` drops the colonist's plan every second when the order has nothing to do.**

- `drive` (`sim/orders.gd:463-479`) aborts every plan that is not imminent. It does this before it knows if `think` can make a plan. When the order is blocked, or `work_at` has no task, `think` returns false. The needs ladder then starts a new plan. One second later `drive` aborts it again.
- The comment on `is_blocked` says the colonist "works as usual meanwhile". `drive` does not read `is_blocked`.

| Scenario (90 s) | Plan changes | Seconds asleep | Fatigue at end |
|---|---|---|---|
| Control (no order) | 3 | 53.1 | 42.9 |
| `work_at` on a structure with no task | 79 | 30.1 | 63.2 |
| `repair` order, no part (blocked `no_item`) | 79 | 30.1 | 63.2 |

From t+36 s the log shows "Going to bed" and "Sleeping" once a second, in turn.
The baseline did not have this behaviour. It comes from the new `drive`. The colonist has an order that does nothing, and his own plans are dropped.

**T2. An order says "missing" when parts exist but other repairs hold them.**

- Set-up: 6 parts added to Storehouse 1, 3 s run. Result: 10 parts, 6 reserved, 6 repair tasks (as RC6.1).
- A `repair` order on Kitchen & Mess 8 (health 1.2, no repair task) gives `blocked = no_item`. `order_task` (`jobs.gd:840`, branch "repair") calls `find_source`. All free parts are held by other repair tasks, so it returns -1 and the order reports "missing".
- Effect: `chains.report_missing` (`orders.gd:485-498`) raises the "build a Parts Works" alert. The real cause is reservation. The text is wrong, and the order never runs while the other 6 repairs hold the parts.

### 3.3 Not yet checked in the tree (reading only)

- `work_at` is still a filter. `orders.think` returns false for it (`orders.gd:404-407`). It never ends (RC4). Roles hr and security never run it (RC2).
- `party._recruit` still recruits ordered colonists (`party.gd:484-514`). `drive` now drops the party plan one second later, but the party counts the colonist as a guest.
- `_gen_repair` is unchanged. It still gives parts in building id order and stays silent for worn structures (RC6.1, RC6.4).
- "Maintain now" for a machine that is not yet worn still sends the `maintain` flag command (`inspector_sections.gd:1311-1315`, `dashboard_screen.gd:714-717`). The toast text is unchanged.
- The WORN badge threshold and the priority tooltip are unchanged (`world_view.gd:3203`, `inspector_sections.gd:1325`).

## 4. Fix plan

Order of work: S1 to S4 first (they fix the bug Paul reports). Then S5 to S7 (supply). Then U1 to U7.
Every item has an acceptance test in 4.4.

### 4.1 SIM

**S1. One repair path for every order that repairs.**
- Keep the kinds `repair`, `maintain`, `build`, `haul`, `task`. Keep `repair_need`.
- Make `work_at` use the same path. In `orders.think`, `work_at` takes the best open task at that structure with `agents.start_task_for` (role does not matter). When no task is left at the structure, call `_finished`. The order then ends. The colonist returns to routine (RC4).
- A `work_at` order is then valid for hr and security (RC2). Their `_try_work` exclusion at `agents.gd:537` stays for their own routine.
- `check()` for `work_at` (`orders.gd:176`) says `no_work` when the structure has no task and no repair need. The UI shows that text.

**S2. An order interrupts every plan except an imminent death need.**
- Keep `drive` before the plan-empty return (`agents.gd:511`). Keep `_imminent` as it is: air (`safety`), thirst or hunger at 42.5 while the colonist drinks or eats, fatigue at 85, health under 30.
- The critical needs at `agents.gd:498-507` already come before `drive`. Do not change them.
- After an imminent plan ends, `drive` resumes the order at the next think.

**S3. Fix T1 (no plan thrash).** `drive` must decide first and abort second.
- Add `orders.can_act(a)`: a check without side effects. It returns true when `think` would make a plan now (a task exists or can be made, a way exists). Use `order_task` in a dry mode, or cache the last answer in `o["blocked"]`.
- In `drive`: if the plan is not an order plan and `can_act` is false (blocked, no task), return false and leave the plan alone. The colonist works as usual (`_try_work` already ignores a blocked order, `agents.gd:941`).
- Re-check a blocked order every 5 s, not every second. `find_source` runs for every ordered colonist each time.
- A blocked order that waits for an item keeps its text on the colonist ("Waiting for spare part to repair X (order)"). It does not set the goal while the colonist does something else.

**S4. The order ends and the colonist returns to routine.**
- `_finished` (`orders.gd:508`) clears the order. A `maintain` standing order goes to `workq.standing_wait`.
- A repair order loops until `repair_need` is empty (one repair gives +25 health, `balance.json:81`). It makes a new task after each task.
- After the order ends, the colonist starts a normal plan at the next think. A party or a sleep does not resume unless the ladder picks it (V5_DESIGN 18.1.2).
- A blocked order that cannot ever run (no way, `missing.is_empty()`) ends after 120 fails (already in `_blocked`). A blocked order that waits for an item stays, and it is visible in the Work window.

**S5. Parties and duties skip ordered colonists.**
- `party._recruit` (`party.gd:484-514`) skips a colonist with `a.has("order")` and not blocked, even for honoured people and friends.
- `leisure.gd:281-299` (venue shift) and `people.gd:418-436` (duties) need no change if S3 is right. Test them (T-F).

**S6. A repair order gets a part, even when others hold all of them.**
- In `jobs.order_task` branch "repair", "maintain", "patch": when `find_source` returns -1, look for an unowned open task of kind repair or maintain that holds the item (`t["hold_out"]`). Release the hold of the least urgent one (`inventory.gd:112` `release`; lowest `emergency`, then the highest building id). Set that task back to "no part yet" or delete it. Its structure gets a new task later. Then take the part.
- Return `missing` only when the total free plus released stock is 0. Add the reason: `reserved`, `unreachable` (pile in `unreach_src`), or `none` (no producer).
- `chains.report_missing` is called only for reason `none`. For `reserved` the order simply takes the part. For `unreachable` the alert says where the parts are.

**S7. Part allocation and thresholds.**
- `_gen_repair` (`jobs.gd:805-833`): sort the structures by urgency before it gives parts: broken life support, broken, then lowest health, then id. Today it uses building id order (line 808).
- Keep the last N parts for maintenance when a machine is at risk (`hazards.at_risk()` not empty). N = 1 is enough for the first version. Set it in `balance.json`.
- `_gen_repair` and `_gen_hazard_work` set `b["block"]` for every structure that needs a part and has none, not only a broken one (`jobs.gd:821-824`). `alerts.gd` reads it.
- Add an alert "Spare parts lie where nobody can reach them (N parts)" when `source_unreachable` holds the only stock. Show button: select the pile.
- Add an alert for a worn structure (health under 70, or at risk) with no part: "X needs a part. Spare parts: 0 free." with the chain (V5_DESIGN 18.4).
- Make `at_risk()` and `cmd_maintain` accept a broken machine (`hazards.gd:1044-1062, 1109-1117`): a broken machine gets a repair order, not "not_active".
- Keep `repair_trigger_health` 70 for the automatic repair. A player order works from health 99.5 (`repair_need`). The UI says so (U2).

### 4.2 UI (all UI items depend on SIM S1 and S3)

**U1. "Maintain now" becomes a real order.**
- Both buttons (`inspector_sections.gd:1311-1315`, `dashboard_screen.gd:714-717`) open the same Assign window that "Repair now" opens. Choices: "Maintenance team" (team order to the head) or one colonist.
- The button also shows for a broken machine (RC8).
- Remove the toast "is the next technician job". Show the sim answer: accepted, refused with the sim's text, or "waiting for spare part" (S6 reason).

**U2. Order verbs in the Orders window.**
- `ui/hud/orders_window.gd`: add "Repair...", "Maintain...", "Build...", "Haul..." (`SIM_KIND` already has them). Keep "Work at...".
- The window says: "Repair works from health 99. The colony repairs by itself below health 70."
- The structure pick ignores agents (`world_view.gd:3593-3606`): a click near a colonist still picks the structure under it.
- The order row shows the target name and the state: "going", "working", "waiting for spare part", "no way". `v4_data.order_of` returns the structure name for every kind.

**U3. Pending state on the structure.** The inspector and the Work window show who has the job, the state (waiting for part, on the way, working) and the time. Use the `first` flag (`ui/data.gd:941`) or the new order data.

**U4. Stock chip.** `dashboard_screen.gd:709-711` shows "free and reachable / total" and the number held and unreachable.

**U5. Dashboard card.** `at_risk()` rows include broken machines. The card never says "No machine is near failure" when one is broken.

**U6. Alerts.** The alerts panel shows the new SIM alerts (S7) with "Show" and "Show chain" (`chain_window.gd`). The text names the chain: "Spare parts: ore, Mine, Refinery, metal, Workshop, spare parts".

**U7. Small fixes.**
- Tooltip `inspector_sections.gd:1325`: "Priority 1 is last. 3 is first." (0 does not exclude a task.)
- WORN badge `world_view.gd:3203`: use `hazards.risk_frac()` instead of 0.75.

### 4.3 Content and saves

- Old saves: an old `order` dictionary has no `blocked`, `tid`, `left`, `standing`. Code reads them with `get()` (the tree does in `is_blocked`). Add a load test.
- `showcase_v5` shows RC6 (no Workshop, unreachable pile). Do not change the save for the bug fix. Add a second save or a test set-up with a Workshop for the order tests.
- Find out why the landing-pod pile 3639 has no path (26 m from air, `no_path`). If it is a nav bug, it is a separate request to SIM.

### 4.4 Tests (headless, `tests/`, deterministic)

Set-up for every test: `showcase_v5`, parts in a reachable store with `inv.add_new_forced`, subject is a technician and not a head, order with `direct: true`.

| ID | Test | Pass condition |
|---|---|---|
| T-A | An idle, a partying, a sleeping (fatigue 55 and 80) and a working colonist each get a `repair` order on a worn structure | The colonist owns the repair task within 5 s. The structure health or wear improves. The order is cleared. Within 3 s after that the plan is not `order` or `task` for this structure. |
| T-B | Same, but thirst 50 when the order comes | The colonist drinks first. He resumes the order within 60 s. |
| T-C | Probe O scenarios `work_at_idle` and `repair_blocked` | At most 6 plan changes in 90 s. Seconds asleep within 5 s of the control. |
| T-D | 6 parts all held by 6 open repair tasks, repair order on a seventh structure | The order gets a part. No `missing` report. One of the 6 tasks loses its hold. |
| T-E | Only parts in an unreachable pile | The order is blocked. The alert says the parts are unreachable and where they are. |
| T-F | A security colonist and an hr colonist get a `repair` order and a `work_at` order | Both do the work. Routine returns after. |
| T-G | Order to a department head, and a `direct` order to a subordinate | The head gives the work to subordinates and reports. The direct order goes to one colonist only. |
| T-H | A `work_at` order on a structure with no task | `check` refuses with `no_work`. After the last task at a structure, the order ends. |
| T-I | A party starts while a colonist has an order | The colonist is not a guest. |
| T-J | Save and load with an active order and with a blocked order | The state is the same after load. |
| T-K | A machine with wear and parts in stock, no order | The colony maintains it by itself (control of RC5). The order does not slow it down. |

Also run the full suite (`node tools/godot.mjs test`) and the campaign check. A change to `drive` runs for
every ordered colonist every second.

## 5. Not verified, and limits

- **Paul's own game.** No investigation had his playtest save. `autosave_1.fhsave` is day 0.5 with 8 parts. RC6.2 and RC6.3 (no Workshop, unreachable pile) are facts of `showcase_v5` only. In Paul's tutorial start 8 parts last for about 8 repairs. Then a Workshop is needed. The in-game alert must say this (S7). RC1, RC2, RC3, RC4 and RC7 are code facts and hold in any save.
- **Moving tree.** Sections 1 and 2 are baseline. Probe O ran on the tree at about 06:30. SIM can change `drive` and `order_task` after that. Run `tests/dev/diag_orch_thrash.gd` again after each change.
- **Single-source claims.** The WORN threshold (`world_view.gd:3203`) and the priority clamp (`jobs.gd:1208`) were read by ORCH in the code. The tooltip text was read at `inspector_sections.gd:1325`.
- **The 6 parts probe (T2).** The target (Kitchen & Mess 8) also has a patch task. The result `no_item` is still caused by the reservation. A target without a patch task is a cleaner test.
- Probe U `diag_ui_orders_e2e.gd` is invalid (section 2).

## 6. Evidence and how to run it

Run from `C:\Users\paulb\Claude\frontier-habitat`. Set `FH_ORCHESTRATOR=1`. Never open a window.

```
FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/<name>.gd [args]
```

| Probe | File | What it shows |
|---|---|---|
| U | `tests/dev/diag_ui_paths.gd`, `diag_ui_maintain_why.gd`, `diag_ui_maintain_why2.gd`, `diag_ui_maintain_trace.gd`, `diag_ui_maintain_tick.gd`, `diag_ui_maintain_tick2.gd` | UI route of "Maintain now" and "Work at", the 60 s pile cycle, `class` plan under a `work_at` order |
| S | `tests/dev/diag_sim_a_state.gd`, `diag_sim_b_orders.gd` (scenarios s1 to s21), `diag_sim_c_source.gd`, `diag_sim_d_paul_save.gd`, `diag_sim_e_spares.gd` | Latency by state, the needs ladder, parts held by repairs, unreachable pile |
| R | `tests/dev/diag_repair_order.gd` (12 scenarios), `diag_repair_probe.gd` to `diag_repair_probe6.gd` | 900 s runs of `work_at`, `go` and no order; no Workshop; 6 repair tasks hold 6 parts |
| O | `tests/dev/diag_orch_thrash.gd` (`control`, `work_at_idle`, `repair_blocked`, `parts_held`) | T1 and T2 on the working tree |

Probe S and Probe R per-second logs are in
`C:\Users\paulb\AppData\Local\Temp\claude\C--Users-paulb-Claude\3e85b8ec-b327-451b-9189-747f18841889\scratchpad\diag\diag_<scenario>.log`.
Run the S and R probes against the baseline copy to get baseline results. Against the working tree the results
now differ, because RC2 and RC1 are partly fixed there.
