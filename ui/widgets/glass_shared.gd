extends Node2D
## One frosted-glass drawer for every HUD panel, window and toast (V4 draw-call budget).
## Each frame it gathers the outline of every registered panel that is visible, in the panel's
## own opacity, and draws them all as ONE triangle array with the blur material of
## ui/widgets/glass.gd. It is the first child of the HUD root, so it draws before the panels.
## A panel that is freed simply drops out.

const FhStyle = preload("res://ui/theme/fh_style.gd")

var _panels: Array = []     # [[weakref(panel), chamfer]]
var drawn := 0              # panels drawn last frame (tests)

func _ready() -> void:
	material = load("res://ui/widgets/glass.gd").material()
	z_index = 0

func add_panel(p: Control, ch: PackedFloat32Array) -> void:
	_panels.append([weakref(p), ch])

func remove_panel(p: Control) -> void:
	var keep: Array = []
	for rec in _panels:
		if (rec[0] as WeakRef).get_ref() != p:
			keep.append(rec)
	_panels = keep

func _process(_d: float) -> void:
	queue_redraw()

static func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a

func _draw() -> void:
	drawn = 0
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var inv: Transform2D = get_global_transform().affine_inverse()
	var keep: Array = []
	for rec in _panels:
		var p = (rec[0] as WeakRef).get_ref()
		if p == null:
			continue
		keep.append(rec)
		var c: Control = p
		if not c.is_visible_in_tree():
			continue
		var a: float = _alpha(c)
		if a <= 0.01:
			continue
		var r: Rect2 = c.get_global_rect()
		var shp: PackedVector2Array = FhStyle.shape(r, rec[1])
		var base: int = pts.size()
		for q in shp:
			pts.append(inv * q)
			cols.append(Color(1, 1, 1, a))
		for i in range(1, shp.size() - 1):
			idx.append_array(PackedInt32Array([base, base + i, base + i + 1]))
		drawn += 1
	_panels = keep
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
