extends SceneTree
## Diagnostic probe (read-only on game files): after spares are added, why is no maintain task made?
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	sim.inv.add_new_forced(342, "spare_parts", 6, "diag")
	sim.run_seconds(2.0)
	sim.jobs._index(true)
	var b: Dictionary = sim.state["buildings"][108]
	print("inv 342: ", sim.state["inventories"][342]["items"].get("spare_parts"), " held_out ", sim.state["inventories"][342]["held_out"], " cap ", sim.state["inventories"][342]["cap"], " total ", sim.inv.total(342), " free ", sim.inv.free_space(342))
	print("_src_index spare_parts: ", sim.jobs._src_index.get("spare_parts", "none"))
	var src: int = sim.jobs.find_source("spare_parts", b["pos"])
	print("find_source -> ", src, " available ", sim.inv.available(src, "spare_parts") if src != -1 else "n/a")
	print("wants_maintenance(108) ", sim.hazards.wants_maintenance(b), " _count maintain:108 ", sim.jobs._count.get("maintain:108", 0), " parked ", sim.jobs._parked(b))
	print("is_machine ", sim.hazards.is_machine(b), " in wear dict ", sim.hazards.hs()["wear"].has(108), " demolish ", b["demolish"])
	var tasks_before: int = sim.state["tasks"].size()
	var ok: bool = sim.jobs._item_task("maintain", 108, "spare_parts", 1, 1)
	print("_item_task -> ", ok, " tasks ", tasks_before, " -> ", sim.state["tasks"].size())
	var ho: int = sim.inv.hold_out(342, "spare_parts", 1, 999999)
	print("hold_out direct -> ", ho)
	print("level ", sim.hazards.level())
	# Run the generator exactly as the sim does and look again
	sim.jobs.tick_part(1)
	var n := 0
	for tid in sim.state["tasks"]:
		if sim.state["tasks"][tid]["kind"] == "maintain":
			n += 1
			print("  maintain task ", sim.state["tasks"][tid])
	print("maintain tasks after tick_part(1): ", n)
	sim.dispose()
	quit(0)
