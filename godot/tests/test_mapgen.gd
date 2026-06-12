extends SceneTree
## Headless determinism check for the seeded map generator (M1 verification).
## Run on each platform and diff the output — it must be identical:
##   godot --headless --path . --script res://tests/test_mapgen.gd

const SEEDS := ["alpha", "1749600000_abc1d2e3f", "slippington", "42"]


func _init() -> void:
	for seed_str in SEEDS:
		var map := MapGenerator.generate(seed_str)
		print("=== seed: %s ===" % seed_str)
		print(MapGenerator.describe(map))
	for preset in ["arena", "towers"]:
		var map := MapPresets.get_preset(preset)
		print("=== preset: %s ===" % preset)
		print("platforms=%d spawns=%d" % [map["platforms"].size(), map["spawn_points"].size()])
		_check_reachability(map, preset)
	print("DONE")
	quit(0)


## Sanity check: every preset platform should be reachable from some other
## platform below it (vertical gap within max jump height).
func _check_reachability(map: Dictionary, label: String) -> void:
	var max_jump := MapGenerator.max_jump_height()
	for p in map["platforms"]:
		var rect: Rect2 = p["rect"]
		if rect.position.y >= 1060.0:
			continue  # ground
		var reachable := false
		for other in map["platforms"]:
			if other == p:
				continue
			var o: Rect2 = other["rect"]
			var dy := o.position.y - rect.position.y
			if dy > 0.0 and dy <= max_jump + 1.0:
				reachable = true
				break
		if not reachable:
			print("WARNING %s: platform at %.0f,%.0f may be unreachable (gap > %.0f)" % [label, rect.position.x, rect.position.y, max_jump])
