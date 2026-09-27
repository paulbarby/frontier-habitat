extends Node
## Text floor (critic round 21, fix 4): no interface text under 12 screen pixels, at 80 % interface
## scale or in a 1280 x 720 window. The canvas scales the whole interface (stretch mode
## canvas_items x interface scale); this node raises the font size of each text control so that
## size x scale >= 12 px. The frames and panels scale as before: only small text grows.
## - Every Label, Button (and its kinds), LineEdit and RichTextLabel under the interface root keeps
##   its own wanted size in meta "fs_base"; the floor is applied on top of it.
## - Custom-drawn text uses P.fs(n) with P.text_scale, set here.
## - Tooltips: the theme's TooltipLabel size follows the floor.

const P = preload("res://ui/theme/palette.gd")

var hud
var _scale := -1.0
var raised := 0          # controls raised at the last pass (tests)

const RICH_KEYS := ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]

func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	get_viewport().size_changed.connect(func(): call_deferred("check"))
	call_deferred("check")

func canvas_scale() -> float:
	var s: float = get_tree().root.get_final_transform().get_scale().x
	return s if s > 0.01 else 1.0

func floor_px() -> int:
	return P.fs(1)

## Re-applies the floor when the canvas scale changed (window resize, interface scale).
func check() -> void:
	var s: float = canvas_scale()
	if absf(s - _scale) < 0.001:
		return
	_scale = s
	P.text_scale = s
	raised = 0
	if hud != null and hud.root != null:
		var t: Theme = hud.root.theme
		if t != null:
			t.set_font_size("font_size", "TooltipLabel", P.fs(13))
		for c in hud.root.find_children("*", "Control", true, false):
			_apply(c)
	# Custom-drawn text redraws with the new floor.
	get_tree().call_group("fs_redraw", "queue_redraw")

func _process(_d: float) -> void:
	# The interface scale changes content_scale_factor without a size_changed signal.
	if absf(canvas_scale() - _scale) >= 0.001:
		check()

func _on_added(n: Node) -> void:
	if not (n is Control) or hud == null or hud.root == null:
		return
	if not hud.root.is_ancestor_of(n):
		return
	_apply(n)

func _apply(c: Control) -> void:
	if c is RichTextLabel:
		for k in RICH_KEYS:
			_floor_key(c, k)
	elif c is Label or c is Button or c is LineEdit:
		_floor_key(c, "font_size")

func _floor_key(c: Control, key: String) -> void:
	var mk: String = "fs_base_" + key
	var base: int
	if c.has_meta(mk):
		base = int(c.get_meta(mk))
	else:
		base = c.get_theme_font_size(key)
		if base <= 0:
			return
		c.set_meta(mk, base)
	var want: int = P.fs(base)
	if want != base:
		raised += 1
	if c.get_theme_font_size(key) != want:
		c.add_theme_font_size_override(key, want)
