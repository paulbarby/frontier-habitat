extends RefCounted
## Plain-English helpers for alert and log texts: a count with the right noun form, and
## the right verb for it. "1 colonist is starving." / "3 colonists are starving."
##   const Text = preload("res://sim/text.gd")
##   Text.n(3, "colonist")              -> "3 colonists"
##   Text.n(1, "person", "people")      -> "1 person"
##   Text.be(n)  -> "is" / "are"        Text.have(n) -> "has" / "have"
##   Text.s(n, "lose")                  -> "loses" (n == 1) / "lose"

static func n(count: int, one: String, many: String = "") -> String:
	return "%d %s" % [count, one if count == 1 else (many if many != "" else one + "s")]

static func be(count: int) -> String:
	return "is" if count == 1 else "are"

static func have(count: int) -> String:
	return "has" if count == 1 else "have"

## The verb for a count: s(1, "lose") = "loses", s(2, "lose") = "lose".
static func s(count: int, verb: String) -> String:
	if count != 1:
		return verb
	if verb.ends_with("s") or verb.ends_with("sh") or verb.ends_with("ch"):
		return verb + "es"
	return verb + "s"
