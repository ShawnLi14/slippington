extends SceneTree
## Map generation gate (headless):
##   godot --headless --path . --script res://tests/test_mapgen.gd
## 1. Determinism: describe() printed for fixed seeds — diff across runs
##    and platforms must be identical.
## 2. Soundness: MapPlanner.validate() must report ZERO issues across many
##    seeds and both presets (unreachable surfaces, floating/pointless
##    springs, blocked portals, movers sweeping through geometry).
## Exits 1 on any failure.

const DESCRIBE_SEEDS := ["alpha", "1749600000_abc1d2e3f", "slippington", "42"]
const SOUNDNESS_SEEDS := 50


func _init() -> void:
	var failures := 0

	for seed_str in DESCRIBE_SEEDS:
		var map := MapGenerator.generate(seed_str)
		print("=== seed: %s ===" % seed_str)
		print(MapGenerator.describe(map))

	for i in SOUNDNESS_SEEDS:
		var seed_str := "soundness_%d" % i
		var map := MapGenerator.generate(seed_str)
		var issues := MapPlanner.validate(map)
		for issue in issues:
			print("FAIL seed %s: %s" % [seed_str, issue])
			failures += 1

	for preset in ["arena", "towers"]:
		var map := MapPresets.get_preset(preset)
		var issues := MapPlanner.validate(map)
		for issue in issues:
			print("FAIL preset %s: %s" % [preset, issue])
			failures += 1

	if failures > 0:
		print("FAILED: %d issues" % failures)
		quit(1)
	else:
		print("DONE: %d seeds + presets sound" % SOUNDNESS_SEEDS)
		quit(0)
