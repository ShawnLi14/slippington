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
		_check_reachability(map, seed_str)
	for preset in ["arena", "towers"]:
		var map := MapPresets.get_preset(preset)
		print("=== preset: %s ===" % preset)
		print("platforms=%d spawns=%d" % [map["platforms"].size(), map["spawn_points"].size()])
		_check_reachability(map, preset)
	print("DONE")
	quit(0)


## Sanity check: every platform should be reachable from a platform below
## (within jump height) or from a spring below (springs launch ~380px).
func _check_reachability(map: Dictionary, label: String) -> void:
	var max_jump := MapGenerator.max_jump_height()
	var spring_reach := pow(SpringPad.LAUNCH_VELOCITY, 2.0) / (2.0 * GameConfig.GRAVITY)
	for p in map["platforms"]:
		if p["type"] == "wall":
			continue  # walls are obstacles, not floors
		var rect: Rect2 = p["rect"]
		if rect.position.y >= 1060.0:
			continue  # ground
		var reachable := false
		for other in map["platforms"]:
			if other == p or other["type"] == "wall":
				continue
			var o: Rect2 = other["rect"]
			var dy := o.position.y - rect.position.y
			if dy > 0.0 and dy <= max_jump + 1.0:
				reachable = true
				break
		if not reachable:
			for obj in map.get("objects", []):
				if obj["type"] == "spring" and obj["pos"].y - rect.position.y <= spring_reach:
					reachable = true
					break
		if not reachable:
			print("WARNING %s: platform at %.0f,%.0f may be unreachable (gap > %.0f)" % [label, rect.position.x, rect.position.y, max_jump])
