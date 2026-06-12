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
		failures += _check_border_gap(seed_str, map)

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


## Generated maps only (hand-made presets own their margins): every platform,
## including a mover's full travel range, stays PLATFORM_GAP off the borders.
## The full-width ground is the deliberate exception.
func _check_border_gap(seed_str: String, map: Dictionary) -> int:
	var bad := 0
	for p in map["platforms"]:
		var r: Rect2 = p["rect"]
		if r.size.x >= float(map["width"]):
			continue  # ground
		var sweep := r
		if p.has("move") and p["move"]["axis"] == "x":
			var a: float = p["move"]["amplitude"]
			sweep = Rect2(r.position - Vector2(a, 0), r.size + Vector2(2 * a, 0))
		if sweep.position.x < GameConfig.PLATFORM_GAP - 0.5 \
				or sweep.end.x > float(map["width"]) - GameConfig.PLATFORM_GAP + 0.5:
			print("FAIL seed %s: platform breaks border gap at %.0f,%.0f (w=%.0f)"
					% [seed_str, r.position.x, r.position.y, r.size.x])
			bad += 1
	return bad
