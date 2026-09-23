extends Button
## Button of the design system: wrapped tooltips with an optional bold first line
## ("Title\nbody"), a hover and click sound, and a pointing cursor.

const Tip = preload("res://ui/widgets/tip.gd")
const Sfx = preload("res://ui/sfx.gd")

var sound := "click"

func _ready() -> void:
	mouse_entered.connect(_on_hover)
	pressed.connect(_on_press)

func _on_hover() -> void:
	if not disabled:
		Sfx.play("hover")

func _on_press() -> void:
	if sound != "":
		Sfx.play(sound)

func _make_custom_tooltip(for_text: String) -> Object:
	return Tip.make(for_text)
