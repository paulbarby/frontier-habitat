extends SceneTree
## Probe (UI, 2026-10-03): strip cards whose content is wider than the card.
var main
var _n := 0
var _tabs := ["life", "food", "habitat", "industry", "power", "logistics", "science", "civic"]
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
	var k: int = (_n - 20) / 10
	if _n >= 20 and (_n - 20) % 10 == 0 and k < _tabs.size():
		main.hud.build_bar.toggle_tab(_tabs[k])
	if _n >= 20 and (_n - 20) % 10 == 8 and k < _tabs.size():
		for tr in main.hud.build_bar.tier_rows:
			for card in main.hud.build_bar.tier_rows[tr].get_children():
				var m: float = card.get_child(0).get_combined_minimum_size().x
				if m > card.size.x + 0.5:
					print("WIDE ", _tabs[k], " ", card.def_id, " content ", m, " card ", card.size.x, " parts ", card.get_child(0).get_child(1).get_combined_minimum_size())
					if card.def_id == "airlock":
						for kid in card.get_child(0).get_child(1).get_children():
							print("   kid ", kid.get_class(), " vis ", kid.visible, " min ", (kid as Control).get_combined_minimum_size())
							for kk in kid.get_children():
								print("      kk ", kk.get_class(), " vis ", kk.visible, " min ", (kk as Control).get_combined_minimum_size())
	if _n > 20 + 10 * _tabs.size():
		quit(0)
		return true
	return false
