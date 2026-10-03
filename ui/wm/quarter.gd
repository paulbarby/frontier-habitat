extends RefCounted
## Windows that open in the right quarter of the view (Paul, 2026-10-03: nothing opens over the centre zone, the middle
## half of the width and of the height; dragging stays free). A window with this helper is as wide as the right quarter
## allows (its left edge at or right of 75 % of the view width), never wider than its design width `base` and never
## narrower than MIN_W. Narrow, a long label wraps or is cut (the tooltip has it), a fixed minimum width is the content
## width, a row that cannot shrink scrolls sideways, and the scroll area gives up height so the window stays inside the
## work area. Used by the advisor, Find, Orders, Reactor and the personnel file (the inspector has its own copy).
## Call `fit` while the window is visible (each frame or each refresh: it does nothing when nothing changed).

const MIN_W := 236.0

## The width the right quarter allows.
static func width_for(hud, base: float) -> float:
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var right: float = hud.wm.work_area().end.x if hud.wm != null else vp.x - 78.0
	return clampf(floorf(right - vp.x * 0.75) - 1.0, MIN_W, base)

## Sets the window width; `scroll` (a ScrollContainer in the window, or null) takes `w - pad`; `body` is its content.
## `chrome_extra`: height of the rows outside the scroll that the window cannot measure by itself.
static func fit(win: Control, hud, id: String, base: float, scroll: ScrollContainer, body: Control, pad: float, max_h: float = 560.0) -> void:
	var w: float = width_for(hud, base)
	# Narrow when the quarter is narrower than the design, or when the content is wider than the quarter allows.
	var narrow: bool = w < base - 0.5 or win.get_combined_minimum_size().x > w + 0.5
	var changed: bool = absf(float(win.get_meta("qw", -1.0)) - w) > 0.5
	if changed:
		win.set_meta("qw", w)
		win.custom_minimum_size.x = w
		if scroll != null:
			scroll.custom_minimum_size.x = w - pad
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if narrow else ScrollContainer.SCROLL_MODE_DISABLED
		win.reset_size()
		_replace(win, hud, id)
	# A size left over from a wider moment (the content grew and shrank): back to the content.
	if win.size.x > w + 0.5 and win.size.x > win.get_combined_minimum_size().x + 0.5:
		win.reset_size()
		_replace(win, hud, id)
	if narrow:
		relax(win, w - pad, int(w))
		if scroll != null and body != null:
			var h0: float = scroll.custom_minimum_size.y
			fit_height(win, hud, scroll, body, max_h)
			if absf(scroll.custom_minimum_size.y - h0) > 0.5:
				win.reset_size()
				_replace(win, hud, id)

## A window at its default place (never dragged) goes back to it once its size settles.
static func _replace(win: Control, hud, id: String) -> void:
	var rec: Dictionary = hud.wm._wins.get(id, {})
	if not rec.is_empty() and bool(rec.get("auto", false)) and win.visible:
		hud.wm.place(id)

## An icon button with thin margins (a 26 px square): a header row of three stays under 100 px.
static func thin(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var st: StyleBox = b.get_theme_stylebox(state)
		if st != null:
			var d: StyleBox = st.duplicate()
			d.content_margin_left = 4.0
			d.content_margin_right = 4.0
			d.content_margin_top = 4.0
			d.content_margin_bottom = 4.0
			b.add_theme_stylebox_override(state, d)
	b.custom_minimum_size = Vector2(26, 26)

## A narrow window: nothing wider than the content width.
static func relax(n: Node, avail: float, tag: int) -> void:
	for c in n.get_children():
		if not (c is Control):
			continue
		var ctl: Control = c
		if int(ctl.get_meta("narrow", -1)) != tag:
			ctl.set_meta("narrow", tag)
			if ctl.custom_minimum_size.x > avail:
				ctl.custom_minimum_size.x = avail
			if ctl is Label:
				var lb: Label = ctl
				if lb.autowrap_mode == TextServer.AUTOWRAP_OFF and not lb.clip_text and lb.text.length() > 6:
					if n is VBoxContainer and lb.text.length() > 40:
						lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					else:
						lb.clip_text = true
						lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
						if lb.tooltip_text == "":
							lb.tooltip_text = lb.text
			elif ctl is OptionButton:
				(ctl as OptionButton).fit_to_longest_item = false
				(ctl as Button).clip_text = true
				ctl.custom_minimum_size.x = minf(ctl.custom_minimum_size.x, avail * 0.8)
			elif ctl is Button and (ctl as Button).text.length() > 10:
				(ctl as Button).clip_text = true
				(ctl as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				if (ctl as Button).tooltip_text == "":
					(ctl as Button).tooltip_text = (ctl as Button).text
		relax(c, avail, tag)

## The scroll area takes what is left of the work area (the rows around it measured; they wrap in a narrow window).
static func fit_height(win: Control, hud, scroll: ScrollContainer, body: Control, max_h: float) -> void:
	var wa: Rect2 = hud.wm.work_area()
	var chrome := 120.0
	var col: Node = win.get_child(0) if win.get_child_count() > 0 else null
	if col is VBoxContainer:
		var hsum := 0.0
		var cnt := 0
		for c in col.get_children():
			if c is Control and (c as Control).visible and not (c == scroll or (c as Node).is_ancestor_of(scroll)):
				hsum += (c as Control).get_combined_minimum_size().y
				cnt += 1
		chrome = maxf(120.0, hsum + float(cnt) * 8.0 + 27.0 + 30.0)
	var room: float = wa.end.y - win.global_position.y - chrome
	scroll.custom_minimum_size.y = clampf(minf(body.get_combined_minimum_size().y + 4.0, room), 60.0, max_h)
	var excess: float = win.get_combined_minimum_size().y - wa.size.y
	if excess > 0.0:
		scroll.custom_minimum_size.y = maxf(60.0, scroll.custom_minimum_size.y - excess - 2.0)
