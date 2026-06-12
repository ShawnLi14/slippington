class_name SeededRng
extends RefCounted
## Deterministic LCG seeded from a string, ported from the old MapGenerator's
## SeededRandom. Pure integer math (with explicit 32-bit wrapping in the hash)
## so the same seed yields the same sequence on every platform.

var _seed: int
var _initial_seed: String


func _init(seed_string: String) -> void:
	_initial_seed = seed_string
	_seed = _hash_string(seed_string)


static func _to_i32(v: int) -> int:
	v = v & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v


static func _hash_string(s: String) -> int:
	var h := 0
	for i in s.length():
		var c := s.unicode_at(i)
		h = _to_i32(_to_i32(h << 5) - h + c)
	return absi(h)


## Returns a float in [0, 1).
func next() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_seed) / float(0x7FFFFFFF)


## Returns an int in [min_v, max_v] inclusive.
func next_int(min_v: int, max_v: int) -> int:
	return int(floor(next() * float(max_v - min_v + 1))) + min_v


func next_float(min_v: float, max_v: float) -> float:
	return next() * (max_v - min_v) + min_v


func get_seed_string() -> String:
	return _initial_seed
