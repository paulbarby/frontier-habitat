extends "res://ui/screens/screen.gd"
## Trade with a landed ship (docs/V3_1_DESIGN.md §6.1, §6.5). arg = the arrival id.
## Left: what the ship sells (price, units on board, how many to buy). Right: what it buys
## (price, units it still wants, free units in the colony, how many to sell). Footer: credits
## now, cost, income, credits after, and the free storage for the bought goods.
## Buying pays at once; the goods land as a pile at the pad and carriers store them.
## Selling orders units; carriers take them to the ship and each unit is paid when it arrives.
## Confirm sends the command trade {id, buy, sell}; the simulation checks it again.

var ship_id := -1
var _buy := {}      # item -> n
var _sell := {}     # item -> n
var _rows_b: VBoxContainer
var _rows_s: VBoxContainer
var _sum: GridContainer
var _vals := {}
var _warn: Label
var _confirm: Button
var _sig := ""

func _init() -> void:
	icon = "crate"
	title = "Trade"
	pauses = true

func _ready() -> void:
	ship_id = int(arg) if arg != null else -1
	if ship_id < 0:
		# No id: the first landed ship that trades.
		for r in hud.data.traffic_ships():
			var o: Dictionary = r.get("offer", {})
			if String(r.get("phase", "")) == "landed" and (o.has("sells") or o.has("buys")):
				ship_id = int(r["id"])
				break
	super._ready()

func _row() -> Dictionary:
	return hud.data.traffic_row(ship_id)

func build() -> void:
	var d = hud.data
	var r: Dictionary = _row()
	if r.is_empty() or String(r.get("phase", "")) != "landed":
		content.add_child(Kit.wrap("No ship to trade with. A trader or a science ship must stand on a landing pad.", 15, P.TEXT_2))
		return
	set_subtitle("%s on the pad  ·  leaves in %s  ·  credits %d" % [String(r.get("name", "")), Kit.clock(float(r.get("t_s", 0.0))), hud.data.credits()])
	var cols: HBoxContainer = Kit.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var lb: VBoxContainer = card("Buy from the ship", "crate", P.CYAN)
	var lp: PanelContainer = card_panel(lb)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(lp)
	_rows_b = Kit.vbox(4)
	lb.add_child(_cols_head(["Item", "Price", "On board", "In colony", "Buy"]))
	lb.add_child(Kit.scroll(_rows_b))
	var rb: VBoxContainer = card("Sell to the ship", "trend_up", P.GOLD)
	var rp: PanelContainer = card_panel(rb)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rp)
	_rows_s = Kit.vbox(4)
	rb.add_child(_cols_head(["Item", "Price", "It wants", "Free here", "Sell"]))
	rb.add_child(Kit.scroll(_rows_s))
	# Footer
	var foot: PanelContainer = Kit.panel("WellPanel", false)
	content.add_child(foot)
	var fr: HBoxContainer = Kit.hbox(24)
	foot.add_child(fr)
	_sum = Kit.grid(10, 10, 2)
	fr.add_child(_sum)
	for spec in [["now", "Credits now"], ["cost", "Cost"], ["income", "Income (on delivery)"], ["after", "Credits after"], ["store", "Free storage"]]:
		_sum.add_child(Kit.dim(spec[1], 12))
		var v: Label = Kit.num("", 15, P.TEXT, true)
		_sum.add_child(v)
		_vals[spec[0]] = v
	fr.add_child(Kit.spacer())
	_warn = Kit.label("", "SmallLabel", 12, P.AMBER)
	fr.add_child(_warn)
	fr.add_child(Kit.button("Clear", func():
		_buy = {}
		_sell = {}
		_fill(), "Clear\nSet every amount to 0.", "", "close", 14))
	_confirm = Kit.button("Trade", func(): _do_trade(), "Trade\nPays for what you buy now. Sold goods are paid as carriers deliver them.", "PrimaryButton", "check", 16)
	_confirm.custom_minimum_size.x = 160
	fr.add_child(_confirm)
	_fill()

func _cols_head(names: Array) -> HBoxContainer:
	var h: HBoxContainer = Kit.hbox(8)
	var widths := [190, 70, 80, 80, 150]
	for i in names.size():
		var l: Label = Kit.head(String(names[i]), P.TEXT_3, 10)
		l.custom_minimum_size.x = widths[i]
		h.add_child(l)
	return h

## The rows: one per item the ship sells (left) and buys (right).
func _fill() -> void:
	var d = hud.data
	var r: Dictionary = _row()
	if r.is_empty() or _rows_b == null:
		return
	_sig = _row_sig(r)
	Kit.clear(_rows_b)
	Kit.clear(_rows_s)
	var offer: Dictionary = r.get("offer", {})
	var stock: Dictionary = r.get("stock", {})
	var orders: Dictionary = r.get("orders", {})
	var totals: Dictionary = d.totals()
	var sells: Dictionary = offer.get("sells", {})
	if sells.is_empty():
		_rows_b.add_child(Kit.label("This ship sells nothing.", "", 13, P.TEXT_3))
	for it in sells:
		var on_board: int = int(stock.get(it, sells[it].get("units", 0)))
		_rows_b.add_child(_item_row(String(it), int(sells[it].get("price", 0)), on_board, d.total_of(String(it), totals), _buy, on_board))
	var buys: Dictionary = offer.get("buys", {})
	if buys.is_empty():
		_rows_s.add_child(Kit.label("This ship buys nothing.", "", 13, P.TEXT_3))
	for it in buys:
		var wants: int = maxi(0, int(buys[it].get("units", 0)) - int(orders.get(it, {}).get("n", 0)))
		var free: int = maxi(0, d.free_units(String(it), totals))
		_rows_s.add_child(_item_row(String(it), int(buys[it].get("price", 0)), wants, free, _sell, mini(wants, free)))
	_update_sum()

static func _row_sig(r: Dictionary) -> String:
	return "%s|%s|%s" % [r.get("phase", ""), str(r.get("stock", {})), str(r.get("orders", {}))]

func _item_row(item: String, price: int, a: int, b: int, target: Dictionary, most: int) -> HBoxContainer:
	var d = hud.data
	var h: HBoxContainer = Kit.hbox(8)
	var nm: HBoxContainer = Kit.hbox(6)
	nm.custom_minimum_size.x = 190
	nm.add_child(Kit.icon(Icons.item(item), 18, d.item_color(item)))
	nm.add_child(Kit.label(d.item_name(item), "", 13, P.TEXT))
	h.add_child(nm)
	for pair in [[price, 70, P.GOLD], [a, 80, P.TEXT], [b, 80, P.TEXT_2]]:
		var l: Label = Kit.num("%d" % int(pair[0]), 13, pair[2])
		l.custom_minimum_size.x = pair[1]
		h.add_child(l)
	var q: HBoxContainer = Kit.hbox(2)
	q.custom_minimum_size.x = 150
	var n: Label = Kit.num("%d" % int(target.get(item, 0)), 14, P.TEXT, true)
	n.custom_minimum_size.x = 34
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var set_n := func(v: int):
		v = clampi(v, 0, maxi(0, most))
		if v == 0:
			target.erase(item)
		else:
			target[item] = v
		n.text = "%d" % v
		_update_sum()
	q.add_child(Kit.icon_button("minus", func(): set_n.call(int(target.get(item, 0)) - 1), "1 less", "GhostButton", 12, 26))
	q.add_child(n)
	q.add_child(Kit.icon_button("plus", func(): set_n.call(int(target.get(item, 0)) + 1), "1 more", "GhostButton", 12, 26))
	q.add_child(Kit.button("+5", func(): set_n.call(int(target.get(item, 0)) + 5), "5 more", "GhostButton"))
	q.add_child(Kit.button("All", func(): set_n.call(most), "As many as possible: %d" % most, "GhostButton"))
	for c in q.get_children():
		if c is Button:
			(c as Button).custom_minimum_size.y = 26
			(c as Button).add_theme_font_size_override("font_size", 11)
	h.add_child(q)
	return h

## Totals from the chosen amounts, and what is wrong with them (plain words).
func _update_sum() -> void:
	if _sum == null:
		return
	var d = hud.data
	var r: Dictionary = _row()
	var offer: Dictionary = r.get("offer", {})
	var cost := 0
	var units_in := 0
	for it in _buy:
		cost += int(_buy[it]) * int(offer.get("sells", {}).get(it, {}).get("price", 0))
		units_in += int(_buy[it])
	var income := 0
	for it in _sell:
		income += int(_sell[it]) * int(offer.get("buys", {}).get(it, {}).get("price", 0))
	var now: int = d.credits()
	var store: int = d.storage_free()
	(_vals["now"] as Label).text = "%d" % now
	(_vals["cost"] as Label).text = ("-%d" % cost) if cost > 0 else "0"
	(_vals["income"] as Label).text = ("+%d" % income) if income > 0 else "0"
	(_vals["after"] as Label).text = "%d" % (now - cost + income)
	(_vals["store"] as Label).text = "%d units" % store
	var w: Array = []
	if cost > now:
		w.append("Not enough credits: %d short." % (cost - now))
	if units_in > store:
		w.append("Storage has room for %d units; %d are bought. The rest stays on the ground at the pad." % [store, units_in])
	_warn.text = " ".join(w)
	(_vals["after"] as Label).add_theme_color_override("font_color", P.RED if cost > now else P.GREEN)
	_confirm.disabled = cost > now or (_buy.is_empty() and _sell.is_empty())

func _do_trade() -> void:
	var cid = hud.main.submit("trade", {"id": ship_id, "buy": _buy.duplicate(), "sell": _sell.duplicate()})
	var res: Dictionary = hud.main.sim.cmds.results.get(cid, {})
	if not res.is_empty() and not bool(res.get("ok", false)):
		return   # main.gd toasts the refusal
	Kit.sfx("trade_chime")
	hud.toast("Trade done%s. Bought goods land at the pad; carriers take sold goods to the ship." % ((": %d credits paid" % int(res["cost"])) if int(res.get("cost", 0)) > 0 else ""), "good", "crate")
	_buy = {}
	_sell = {}
	_fill()

func refresh() -> void:
	var r: Dictionary = _row()
	if r.is_empty() or String(r.get("phase", "")) != "landed":
		if _rows_b != null:
			_warn.text = "The ship is leaving. Trade is closed."
			_confirm.disabled = true
		return
	set_subtitle("%s on the pad  ·  leaves in %s  ·  credits %d" % [String(r.get("name", "")), Kit.clock(float(r.get("t_s", 0.0))), hud.data.credits()])
	# Stock or orders changed (a carrier delivered, another trade): rebuild, keep the amounts.
	if _rows_b != null and _row_sig(r) != _sig:
		_fill()
