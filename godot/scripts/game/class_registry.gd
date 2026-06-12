class_name ClassRegistry
## The v1 class roster. Classes are PlayerClass resources built in code so
## there's a single reviewable source of truth (they can be saved out to
## .tres files later if we want editor-tweakable balance).

static var _classes: Dictionary = {}


static func all() -> Array[PlayerClass]:
	_ensure_loaded()
	var result: Array[PlayerClass] = []
	for id in ["slipper", "swapper", "anchor"]:
		result.append(_classes[id])
	return result


static func get_class_by_id(id: String) -> PlayerClass:
	_ensure_loaded()
	if _classes.has(id):
		return _classes[id]
	return _classes["slipper"]


static func _ensure_loaded() -> void:
	if not _classes.is_empty():
		return
	# All classes share one run speed (1.1 = the midpoint of the old
	# slipper 1.3 / anchor 0.9 spread) — identity comes from jump, mass,
	# and ability, so no class wins a flat chase by stat alone.
	_classes["slipper"] = PlayerClass.new(
		"slipper", "Slipper", "Slippery and elusive. Hard to catch.",
		1.1, 1.1, 0.8, BlinkAbility.new()
	)
	_classes["swapper"] = PlayerClass.new(
		"swapper", "Swapper", "Unpredictable. Trades places in a blink.",
		1.1, 1.0, 1.0, SwapAbility.new()
	)
	_classes["anchor"] = PlayerClass.new(
		"anchor", "Anchor", "Heavy and mighty. Stops runners cold.",
		1.1, 1.2, 1.4, StunAbility.new()
	)
