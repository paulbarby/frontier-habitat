extends SceneTree
## RENDER: builds the terrain for a 256 m and an 810 m world headless and prints the build
## times, chunk count and level counts. CPU cost only (the headless renderer draws nothing).
##   node tools/godot.mjs script res://tools/render_terrain_test.gd [size]

const Sim = preload("res://sim/sim.gd")
const FxTerrain = preload("res://presentation/fx_terrain.gd")
const Instancer = preload("res://presentation/fx_instancer.gd")

func _init() -> void:
	var sizes: Array = [256, 810]
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		sizes = [int(args[0])]
	for size in sizes:
		var sim = Sim.new()
		for sc in sim.content["scenarios"]:
			sim.content["scenarios"][sc]["map_size"] = size
		var t0: int = Time.get_ticks_usec()
		sim.new_game(1001)
		var t1: int = Time.get_ticks_usec()
		var root := Node3D.new()
		get_root().add_child(root)
		var inst = Instancer.new()
		root.add_child(inst)
		var ter = FxTerrain.new()
		root.add_child(ter)
		var t2: int = Time.get_ticks_usec()
		ter.build(sim, inst, 2)
		var t3: int = Time.get_ticks_usec()
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.global_position = Vector3(sim.world.center.x, 60.0, sim.world.center.y + 40.0)
		for i in 60:
			ter.update_lod(0.25, cam)
		var t4: int = Time.get_ticks_usec()
		var built := [0, 0, 0, 0]
		for c in ter.chunks:
			for k in 4:
				if c["lods"][k] != null:
					built[k] += 1
		print("map %d: sim.new_game %.0f ms, terrain.build %.0f ms %s, 60 lod updates %.0f ms, chunks %d, built per level %s, shown per level %s, pebble batches %d, rocks %d" % [
			size, (t1 - t0) / 1000.0, (t3 - t2) / 1000.0, JSON.stringify(ter.timings), (t4 - t3) / 1000.0, ter.chunks.size(), str(built), str(ter.lod_counts), ter._pebbles.size(), sim.world.rocks.size()])
		root.queue_free()
	quit(0)
