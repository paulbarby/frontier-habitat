extends PanelContainer
## Floor selector (V5_DESIGN §7, §10): while a multi-storey building is selected (apartment block 3
## floors, super dome 5), a small strip on the right of the view with one button per floor (top
## floor at the top) and "All". The overview camera then cuts the building away above that floor
## (RENDER view.set_view_floor(building_id, k): k = floor + 1, 0 = all). PgUp / PgDn step one floor.
## Data: sim.floors.floors_of(b).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")

var hud
var building := -1
var floor_shown := -1        # -1 = every floor (tests)
var _box: VBoxContainer
var _n := 0

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -80
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(4)
	add_child(v)
	v.add_child(Kit.head("Floor", P.TEXT_2, 11))
	_box = Kit.vbox(3)
	v.add_child(_box)
	v.add_child(Kit.label("PgUp / PgDn", "SmallLabel", 11, P.TEXT_3))

func _process(_d: float) -> void:
	if hud == null or hud.main == null or hud.main.view == null:
		return
	var v = hud.main.view
	var id: int = int(v.selected_id) if String(v.selected_kind) == "building" else -1
	var n := 1
	var s = hud.main.sim
	if id >= 0 and s.get("floors") != null and s.state["buildings"].has(id):
		n = int(s.floors.floors_of(s.state["buildings"][id]))
	if id != building or n != _n:
		if building >= 0 and id != building:
			set_floor(-1)
		building = id
		_n = n
		_build()
	visible = building >= 0 and _n > 1 and not hud.main.in_follow()
	# Left of the inspector, not under it (2026-10-02: at 1280x720 the strip lay behind the inspector's venue list).
	offset_right = -maxf(80.0, hud.right_inset() + 8.0)

func _build() -> void:
	Kit.clear(_box)
	floor_shown = -1
	if _n <= 1:
		return
	for i in range(_n - 1, -1, -1):
		var f: int = i
		var b: Button = Kit.button("%d" % (f + 1) if f > 0 else "G", func(): set_floor(f), "Floor %s\nShows this floor: the floors above it are cut away." % ("%d" % (f + 1) if f > 0 else "G (ground)"), "ChipButton")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(40, 28)
		b.set_meta("floor", f)
		_box.add_child(b)
	var all: Button = Kit.button("All", func(): set_floor(-1), "All floors\nShows the whole building.", "ChipButton")
	all.toggle_mode = true
	all.set_meta("floor", -1)
	all.custom_minimum_size = Vector2(40, 28)
	_box.add_child(all)
	_sync()

func set_floor(f: int) -> void:
	floor_shown = f
	var v = hud.main.view
	if v != null and v.has_method("set_view_floor") and building >= 0:
		v.set_view_floor(building, f + 1 if f >= 0 else 0)   # RENDER: k 1..n = that floor, 0 = off (all)
	_sync()

func step(d: int) -> void:
	if not visible:
		return
	var f: int = (_n - 1) if floor_shown < 0 else floor_shown
	f = clampi(f + d, 0, _n - 1)
	set_floor(-1 if d > 0 and f == _n - 1 and floor_shown == _n - 1 else f)

func _sync() -> void:
	for b in _box.get_children():
		(b as Button).set_pressed_no_signal(int(b.get_meta("floor")) == floor_shown)
