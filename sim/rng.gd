extends RefCounted
## Deterministic random streams (mulberry32). Each stream is one int in state["rng"].
## Integer-only arithmetic: the same seed gives the same numbers on every platform.
## Hazard, weather, arrivals and names use separate streams (spec 11: keep hazard RNG apart).

const MASK := 0xFFFFFFFF

static func imul(a: int, b: int) -> int:
	# 32-bit wrapping multiply without 64-bit overflow.
	var al: int = a & 0xFFFF
	var ah: int = (a >> 16) & 0xFFFF
	var bl: int = b & 0xFFFF
	var bh: int = (b >> 16) & 0xFFFF
	return ((((ah * bl + al * bh) & 0xFFFF) << 16) + al * bl) & MASK

static func stream_seed(seed_value: int, salt: int) -> int:
	var h: int = (seed_value & MASK) ^ imul(salt + 1, 0x9E3779B1)
	h = imul(h ^ (h >> 16), 0x85EBCA6B)
	h = imul(h ^ (h >> 13), 0xC2B2AE35)
	return (h ^ (h >> 16)) & MASK

static func next_u32(rng: Dictionary, stream: String) -> int:
	var a: int = (int(rng[stream]) + 0x6D2B79F5) & MASK
	rng[stream] = a
	var t: int = imul(a ^ (a >> 15), a | 1)
	t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & MASK)) & MASK
	return (t ^ (t >> 14)) & MASK

static func next_float(rng: Dictionary, stream: String) -> float:
	return float(next_u32(rng, stream)) / 4294967296.0

static func range_float(rng: Dictionary, stream: String, lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float(rng, stream)

static func range_int(rng: Dictionary, stream: String, lo: int, hi_inclusive: int) -> int:
	return lo + int(next_u32(rng, stream) % (hi_inclusive - lo + 1))

## Stateless lattice hash for terrain noise. Returns 0..1.
static func hash2(x: int, y: int, seed_value: int) -> float:
	var h: int = (seed_value & MASK) ^ imul(x & MASK, 0x27D4EB2F)
	h = imul(h ^ (h >> 15), 0x85EBCA6B)
	h = (h ^ imul(y & MASK, 0x165667B1)) & MASK
	h = imul(h ^ (h >> 13), 0xC2B2AE35)
	return float((h ^ (h >> 16)) & MASK) / 4294967296.0
