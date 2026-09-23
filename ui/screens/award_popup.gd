extends PanelContainer
## Medal card (docs/AAA_DESIGN.md §8): when state.awards gains an entry during play, a
## compact glass card joins the stack at the top centre: the animated medal in its tier
## colour, the title and the description. It lasts about four seconds, never takes the
## mouse and never pauses the game.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Medal = preload("res://ui/widgets/medal.gd")
const Sfx = preload("res://ui/sfx.gd")
const UiTheme = preload("res://ui/theme/ui_theme.gd")

const LIFE := 4.0

var hud
var award_id := ""
var first_time := true
var _medal

func _ready() -> void:
	var aw: Dictionary = hud.data.awards_def().get(award_id, {"name": award_id, "tier": "bronze", "desc": ""})
	var tier: String = String(aw.get("tier", "bronze"))
	var col: Color = P.TIER.get(tier, P.GOLD)
	var st = UiTheme.panel_style("modal")
	st.bracket = col
	st.border = P.over_panel(col, 0.6)
	st.glow = P.with_alpha(col, 0.3)
	st.glow_size = 8.0
	st.content_margin_left = 14
	st.content_margin_right = 20
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	add_theme_stylebox_override("panel", st)
	Glass.attach(self, [18, 0, 18, 0])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(460, 0)
	var h: HBoxContainer = Kit.hbox(14)
	add_child(h)
	_medal = Medal.new()
	_medal.tier = tier
	_medal.glyph = Medal.glyph_for(award_id)
	_medal.custom_minimum_size = Vector2(64, 76)
	h.add_child(_medal)
	var v: VBoxContainer = Kit.vbox(2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var pts: int = int(hud.data.award_tiers().get(tier, {}).get("points", 0))
	var head: String = "%s medal  ·  %d points" % [String(hud.data.award_tiers().get(tier, {}).get("name", tier.capitalize())), pts]
	if first_time:
		head += "  ·  first on this device"
	v.add_child(Kit.head(head, col, 11))
	v.add_child(Kit.label(String(aw.get("name", award_id)).to_upper(), "TitleLabel", 20, P.TEXT))
	v.add_child(Kit.wrap(String(aw.get("desc", "")), 13, P.TEXT_2))
	# Enter: fade in; the medal pops and turns once; a shine sweeps; then fade out.
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	_medal.pivot_offset = Vector2(32, 38)
	_medal.scale = Vector2(0.5, 0.5)
	tw.tween_property(_medal, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_medal, "spin", TAU, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_medal, "shine", 1.0, 0.8).from(0.0).set_delay(0.5)
	var life := create_tween()
	life.tween_interval(LIFE)
	life.tween_property(self, "modulate:a", 0.0, 0.35)
	life.tween_callback(queue_free)
	Sfx.play("award")
	if hud.main.view.has_method("focus_event"):
		hud.main.view.focus_event("award")

func _process(_delta: float) -> void:
	if _medal != null:
		_medal.queue_redraw()
