extends RefCounted
## One place to play interface sounds. The audio manager (ui/audio.gd) registers itself;
## with no manager, or no sound files, every call is silent.

static var audio = null

static func play(name: String) -> void:
	if audio != null and is_instance_valid(audio):
		audio.play_ui(name)
