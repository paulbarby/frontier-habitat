extends StyleBox
const PG = preload("res://ui/poly_guard.gd")
## GlassFrame (docs/V4_DESIGN.md §7, "space-age glass"): the version-4 panel look.
## Layers, back to front (the frosted blur itself is ui/widgets/glass.gd, behind the panel):
##   1. glass tint: a translucent cool gradient inside the frame, lighter at the top. About 50%
##      at the top to 64% at the bottom, over a blur that is itself 20% smoked: the scene shows
##      through, blurred (critic round 15, fix 1);
##   2. sheen: a light band over the top of the glass, and a 1 px inner highlight at its top edge;
##   3. title plate (windows): a brushed-metal bar with an engraved seam, then a seam hairline
##      across the glass and an accent line in the family or window colour under it;
##   4. the metal frame: one nine-patch (ui/theme/metal.gd) with bevel, rivets, seam lines and
##      chamfered corners. One texture per kind, shared by every panel: few draw commands.
## A panel too small for the nine-patch (under 2 x MARGIN on a side, e.g. a one-line toast) gets
## the 2 px bevelled metal rim of ui/theme/rim.gd instead: the same metal, no rivets.

const Metal = preload("res://ui/theme/metal.gd")
const Rim = preload("res://ui/theme/rim.gd")
const Bake = preload("res://ui/theme/bake.gd")

var kind := "window"                      # "window" | "hud"
var tint_top := Color(0.10, 0.17, 0.27, 0.50)
var tint_bottom := Color(0.04, 0.07, 0.12, 0.64)
var shadow := Color(0.0, 0.0, 0.0, 0.32)  # soft drop shadow (windows)
var sheen := Color(0.75, 0.9, 1.0, 0.10)
var highlight := Color(0.80, 0.94, 1.0, 0.30) # 1 px line at the top edge of the glass
var header_h := 0.0                       # title plate height (0 = none)
var accent := Color(0.24, 0.88, 1.0, 0.8) # line under the title plate (alpha 0 = none)
var accent_left := Color(0, 0, 0, 0)      # bar down the left of the glass (toasts; alpha 0 = none)
var frame_modulate := Color.WHITE         # e.g. brighter for the focused window
var glow := Color(0, 0, 0, 0)             # outer glow (award popup; alpha 0 = none)
## Full screens (critic round 21, fix 3): a frosted border zone `frost_border` px wide in the lighter
## tint, and the body inside it in `body_tint` (about 88 % with the blur), so a full screen reads as
## the same glass family and stays readable. 0 = one tint.
var frost_border := 0.0
var body_tint := Color(0.035, 0.06, 0.11, 0.85)

func _init() -> void:
	content_margin_left = 14
	content_margin_right = 14
	content_margin_top = 12
	content_margin_bottom = 12

func band() -> float:
	return float(Metal.frame_band(kind))

func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 12.0 or rect.size.y < 12.0:
		return
	var small: bool = rect.size.x < 2.0 * Metal.MARGIN or rect.size.y < 2.0 * Metal.MARGIN
	var b: float = 2.0 if small else band()
	var inner: Rect2 = rect.grow(-b + 1.0)
	var ch_out: float = minf(Metal.CHAMFER, minf(rect.size.x, rect.size.y) * 0.3)
	var ch: float = maxf(0.0, ch_out - b * 0.6)
	var FhStyle = load("res://ui/theme/fh_style.gd")
	var outline := PackedFloat32Array([ch_out, 0.0, ch_out, 0.0])
	# 0. drop shadow (windows only): one baked soft nine-patch (ui/theme/bake.gd)
	if kind == "window" and shadow.a > 0.0 and not small:
		Bake.draw(ci, Rect2(rect.position + Vector2(1.5, 4.0), rect.size).grow(6.0), Bake.shadow_tex(Color(shadow.r, shadow.g, shadow.b, shadow.a * 0.85)))
	if glow.a > 0.0:
		for i in 3:
			var g: float = 3.0 * float(i + 1)
			var gp: PackedVector2Array = FhStyle.shape(rect.grow(g), PackedFloat32Array([ch_out + g * 0.41, 0.0, ch_out + g * 0.41, 0.0]))
			gp.append(gp[0])
			RenderingServer.canvas_item_add_polyline(ci, gp, PackedColorArray([Color(glow.r, glow.g, glow.b, glow.a * (0.55 - 0.16 * float(i)))]), 2.0, true)
	# 1–2. glass tint, sheen and the 1 px highlight: one baked nine-patch when the panel is large
	# enough (the draw-call budget), else the polygons below.
	var body_top: float = inner.position.y + (header_h + 1.0 if header_h > 0.0 else 0.0)
	var body := Rect2(inner.position.x, body_top, inner.size.x, inner.end.y - body_top)
	var gb: Dictionary = Bake.glass_fill_tex(tint_top, tint_bottom, sheen, highlight, ch, header_h <= 0.0)
	# HUD panels without a plate: glass and frame are one baked nine-patch, drawn in step 4.
	var combined: bool = kind == "hud" and header_h <= 0.0 and not small
	if combined:
		pass
	elif not small and Bake.fits(body, gb):
		Bake.draw(ci, body, gb)
	else:
		var pts: PackedVector2Array = FhStyle.shape(inner, PackedFloat32Array([ch, 0.0, ch, 0.0]))
		var cols := PackedColorArray()
		for p in pts:
			cols.append(tint_top.lerp(tint_bottom, clampf((p.y - inner.position.y) / inner.size.y, 0.0, 1.0)))
		if PG.ok(pts, "glass_frame:tint"):
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)
		var sh_h: float = minf((inner.end.y - body_top) * 0.35, 90.0)
		if sh_h > 2.0:
			var shr := Rect2(inner.position.x, body_top, inner.size.x, sh_h)
			var sp: PackedVector2Array = FhStyle.shape(shr, PackedFloat32Array([ch if header_h <= 0.0 else 0.0, 0.0, 0.0, 0.0]))
			var sc := PackedColorArray()
			for p in sp:
				var t: float = clampf((p.y - shr.position.y) / maxf(1.0, sh_h), 0.0, 1.0)
				sc.append(Color(sheen.r, sheen.g, sheen.b, sheen.a * (1.0 - t)))
			if PG.ok(sp, "glass_frame:sheen"):
				RenderingServer.canvas_item_add_polygon(ci, sp, sc)
		if highlight.a > 0.0 and header_h <= 0.0:
			var hx: float = inner.position.x + ch
			RenderingServer.canvas_item_add_rect(ci, Rect2(hx, inner.position.y, inner.end.x - hx, 1.0), highlight)
	if frost_border > 0.0 and not small:
		var br: Rect2 = body.grow(-frost_border)
		var bt: Dictionary = Bake.glass_fill_tex(body_tint, body_tint, Color(0, 0, 0, 0), Color(0, 0, 0, 0), maxf(0.0, ch - frost_border * 0.4), false)
		if Bake.fits(br, bt):
			Bake.draw(ci, br, bt)
	if accent_left.a > 0.0 and not combined:
		RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position.x, inner.position.y + ch, 3.0, maxf(0.0, inner.size.y - 2.0 * ch)), accent_left)
	# 3. title plate, the seam under it, the accent line
	if header_h > 0.0 and not small:
		var plate: Texture2D = Metal.plate_tex(int(header_h))
		var pr := Rect2(rect.position.x + b - 1.0, rect.position.y + b - 1.0, rect.size.x - 2.0 * b + 2.0, header_h)
		RenderingServer.canvas_item_add_nine_patch(ci, pr, Rect2(Vector2.ZERO, plate.get_size()), plate.get_rid(),
			Vector2(16, 0), Vector2(16, 0), RenderingServer.NINE_PATCH_TILE_FIT, RenderingServer.NINE_PATCH_STRETCH, true)
		Rim.seam_h(ci, pr.position.x, pr.end.x, pr.end.y)
		RenderingServer.canvas_item_add_rect(ci, Rect2(pr.position.x, pr.end.y + 2.0, pr.size.x, 1.0), highlight * Color(1, 1, 1, 0.6))
		if accent.a > 0.0:
			RenderingServer.canvas_item_add_rect(ci, Rect2(pr.position.x + 10.0, pr.end.y, minf(160.0, pr.size.x * 0.4), 2.0), accent)
	# 4. metal frame
	if small:
		Rim.bevel(ci, rect, outline, 2.0, true, frame_modulate)
		return
	var m := float(Metal.MARGIN)
	if combined:
		var fg: Texture2D = Bake.frame_glass_tex(kind, tint_top, tint_bottom, sheen, highlight)
		RenderingServer.canvas_item_add_nine_patch(ci, rect, Rect2(Vector2.ZERO, fg.get_size()), fg.get_rid(),
			Vector2(m, m), Vector2(m, m), RenderingServer.NINE_PATCH_TILE_FIT, RenderingServer.NINE_PATCH_TILE_FIT, true, frame_modulate)
		if accent_left.a > 0.0:
			RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position.x + 1.0, inner.position.y + ch, 3.0, maxf(0.0, inner.size.y - 2.0 * ch)), accent_left)
		return
	var ft: Texture2D = Metal.frame_tex(kind)
	RenderingServer.canvas_item_add_nine_patch(ci, rect, Rect2(Vector2.ZERO, ft.get_size()), ft.get_rid(),
		Vector2(m, m), Vector2(m, m), RenderingServer.NINE_PATCH_TILE_FIT, RenderingServer.NINE_PATCH_TILE_FIT, false, frame_modulate)
