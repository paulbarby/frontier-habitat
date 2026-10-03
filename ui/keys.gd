extends RefCounted
## The one list of every key and mouse control the game handles. Settings > Keys and How to play >
## Controls both draw from it (STE). The test tools/ui/test_keys.gd compares it with the code that
## handles the input: presentation/main.gd (_unhandled_input and _input) and presentation/camera_rig.gd.
## Change a key there: change the row here in the same piece of work, or the test fails.
##
## Row: g (group), keys (what the player reads), codes (the KEY_ constants the code tests),
## mouse (the MOUSE_BUTTON_ constants), short (Settings), long (How to play).
## Not listed on purpose: the Konami code (a hidden find, V5 section 4.5).

const GROUPS := ["Camera", "Time", "Building", "Windows", "People"]

const ROWS := [
	{"g": "Camera", "keys": "W A S D, arrows", "codes": ["KEY_W", "KEY_A", "KEY_S", "KEY_D", "KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT"], "mouse": [],
		"short": "move the camera", "long": "Move the camera over the colony. Screen-edge pan is an option in Settings."},
	{"g": "Camera", "keys": "Mouse wheel", "codes": [], "mouse": ["MOUSE_BUTTON_WHEEL_UP", "MOUSE_BUTTON_WHEEL_DOWN"],
		"short": "zoom", "long": "Zoom. Over the colony: 9 to 200 m. Over the shoulder: from a face close-up (0.5 m) to 8 m."},
	{"g": "Camera", "keys": "Middle drag", "codes": [], "mouse": ["MOUSE_BUTTON_MIDDLE"],
		"short": "turn; look round (shoulder view)", "long": "Over the colony: turn and tilt the camera. Over the shoulder: look round. The camera stays where it is."},
	{"g": "Camera", "keys": "Q E", "codes": ["KEY_Q", "KEY_E"], "mouse": [],
		"short": "turn; other shoulder (shoulder view)", "long": "Over the colony: turn the camera. Over the shoulder: change to the other shoulder."},
	{"g": "Camera", "keys": "Right drag", "codes": [], "mouse": ["MOUSE_BUTTON_RIGHT"],
		"short": "round the person (shoulder view)", "long": "Over the shoulder: go round the person in a full circle, and tilt the camera from near the floor to high above. Alt + right drag: look round. The camera goes back behind the person by itself after 4 s without input while they walk."},
	{"g": "Time", "keys": "Space", "codes": ["KEY_SPACE"], "mouse": [],
		"short": "pause", "long": "Pause. You can plan while the game is paused."},
	{"g": "Time", "keys": "1 2 3", "codes": ["KEY_1", "KEY_2", "KEY_3"], "mouse": [],
		"short": "speed 1x 2x 4x", "long": "Speed 1x, 2x, 4x."},
	{"g": "Building", "keys": "Left click", "codes": [], "mouse": ["MOUSE_BUTTON_LEFT"],
		"short": "select; place", "long": "Select a structure or a person, or place the structure you chose."},
	{"g": "Building", "keys": "Right click", "codes": [], "mouse": [],
		"short": "cancel; clear", "long": "Cancel the tool or clear the selection. Over the shoulder, right drag turns the camera instead."},
	{"g": "Building", "keys": "Shift + click", "codes": [], "mouse": [],
		"short": "keep placing", "long": "Place more than one structure, or chain corridors."},
	{"g": "Building", "keys": "R, Shift+R", "codes": ["KEY_R"], "mouse": [],
		"short": "turn 15 degrees; camera back (shoulder view)", "long": "Turn the structure you place by 15 degrees (Shift+R: the other way). Over the shoulder: the camera goes back behind the person."},
	{"g": "Building", "keys": "Z X, [ ]", "codes": ["KEY_Z", "KEY_X", "KEY_BRACKETLEFT", "KEY_BRACKETRIGHT"], "mouse": [],
		"short": "size while placing", "long": "A smaller or bigger size while you place a structure (S, M, L, XL)."},
	{"g": "Building", "keys": "Delete", "codes": ["KEY_DELETE"], "mouse": [],
		"short": "remove the selection", "long": "Remove the selected structure. A window asks you first."},
	{"g": "Building", "keys": "O", "codes": ["KEY_O"], "mouse": [],
		"short": "overlay", "long": "Step through the overlays: power, water, air, walking and the others. The last one shows the package transport network."},
	{"g": "Building", "keys": "PgUp, PgDn", "codes": ["KEY_PAGEUP", "KEY_PAGEDOWN"], "mouse": [],
		"short": "floor up, down", "long": "The floor selector of a structure with more than one floor: one floor up or down."},
	{"g": "Windows", "keys": "G T C", "codes": ["KEY_G", "KEY_T", "KEY_C"], "mouse": [],
		"short": "goals, research, colony", "long": "G: Goals. T: Research. C: the colony dashboard."},
	{"g": "Windows", "keys": "I P U", "codes": ["KEY_I", "KEY_P", "KEY_U"], "mouse": [],
		"short": "inventory, people, crew", "long": "I: Inventory. P: Colonists. U: Crew (ranks, homes, the academy, security)."},
	{"g": "Windows", "keys": "J", "codes": ["KEY_J"], "mouse": [],
		"short": "The Regolith Rag", "long": "The Regolith Rag, the colony tabloid."},
	{"g": "Windows", "keys": "M", "codes": ["KEY_M"], "mouse": [],
		"short": "work queues", "long": "The Work window: the open work of every department (build, repair, maintain, haul), in queue order. Top, Up, Down and Bottom move an item; drag a row to move it; Assign to... gives it to a person or a department head; Cancel drops it."},
	{"g": "Windows", "keys": "K", "codes": ["KEY_K"], "mouse": [],
		"short": "codex", "long": "Codex: every structure, item, research project, hazard and person topic, with crafting trees."},
	{"g": "Windows", "keys": "N", "codes": ["KEY_N"], "mouse": [],
		"short": "advisor", "long": "Advisor: the biggest problems, the next goal steps and unused potential."},
	{"g": "Windows", "keys": "/ or Ctrl+F", "codes": ["KEY_SLASH"], "mouse": [],
		"short": "find a structure", "long": "Find a structure by name or type. Click a result: the camera goes there."},
	{"g": "Windows", "keys": "L", "codes": ["KEY_L"], "mouse": [],
		"short": "the left dock", "long": "The left dock: goals, alerts, events, traffic, requests and news. Settings, Notifications, sets what pops up."},
	{"g": "Windows", "keys": "Y", "codes": ["KEY_Y"], "mouse": [],
		"short": "roofs off", "long": "Roofs off: every roof goes, so you see into every building. The roofs stay on over the shoulder."},
	{"g": "Windows", "keys": "H", "codes": ["KEY_H"], "mouse": [],
		"short": "hide the interface", "long": "Hide or show the interface."},
	{"g": "Windows", "keys": "F1", "codes": ["KEY_F1"], "mouse": [],
		"short": "how to play", "long": "How to play: the rules, the people topics and these controls."},
	{"g": "Windows", "keys": "Esc, Shift+Esc", "codes": ["KEY_ESCAPE"], "mouse": [],
		"short": "back; close all", "long": "Esc ends the last thing you started: the pick, the tool, the over-the-shoulder view, the last window, the selection. Then it opens the menu. Shift+Esc closes every window."},
	{"g": "People", "keys": "F", "codes": ["KEY_F"], "mouse": [],
		"short": "follow from above", "long": "Follow the selected person from above. Any camera key ends it."},
	{"g": "People", "keys": "V", "codes": ["KEY_V"], "mouse": [],
		"short": "over the shoulder; awards", "long": "Over the shoulder: the camera goes behind the selected person. V or Esc: back. With nobody selected, V opens the Awards."},
	{"g": "People", "keys": "Tab", "codes": ["KEY_TAB"], "mouse": [],
		"short": "next person (shoulder view)", "long": "Over the shoulder: follow the next person."},
]

## Every KEY_ constant that the table documents.
static func all_codes() -> Array:
	var out: Array = []
	for r in ROWS:
		for c in r["codes"]:
			if not out.has(c):
				out.append(c)
	return out

## Every MOUSE_BUTTON_ constant that the table documents.
static func all_mouse() -> Array:
	var out: Array = []
	for r in ROWS:
		for c in r["mouse"]:
			if not out.has(c):
				out.append(c)
	return out
