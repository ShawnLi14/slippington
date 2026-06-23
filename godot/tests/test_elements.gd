extends SceneTree
## Phase-A element unit tests (headless):
##   godot --headless --path . --script res://tests/test_elements.gd
## These exercise the autoload-free generation/planner layer only — node
## classes like PlatformBody/Player can't be instantiated under --script.

func _init() -> void:
	var failures := 0
	failures += _check("generation stays sound with conveyors", _test_gen_sound())
	failures += _check("some seed produces a conveyor", _test_gen_has_conveyor())
	failures += _check("some seed produces a vertical mover", _test_gen_has_ymover())
	failures += _check("phase platform is not a blocker", _test_phase_nonblocking())
	failures += _check("phase platform is a landable surface", _test_phase_landable())
	failures += _check("some seed produces a phase platform", _test_gen_has_phase())
	if failures > 0:
		print("FAILED: %d test(s)" % failures)
		quit(1)
		return
	print("DONE: elements ok")
	quit(0)

func _check(name: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + name)
	return 0 if ok else 1

func _test_gen_sound() -> bool:
	for s in 30:
		var m := MapGenerator.generate("a1-%d" % s)
		if not MapPlanner.validate(m).is_empty():
			return false
	return true

func _test_gen_has_conveyor() -> bool:
	# Across many seeds at least one belt should appear (CONVEYOR_CHANCE > 0).
	for s in 60:
		var m := MapGenerator.generate("a1-%d" % s)
		for p in m["platforms"]:
			if not p.get("conveyor", {}).is_empty():
				return true
	return false

func _test_gen_has_ymover() -> bool:
	for s in 60:
		var m := MapGenerator.generate("a1-%d" % s)
		for p in m["platforms"]:
			if p.get("move", {}).get("axis", "x") == "y":
				return true
	return false

func _test_phase_nonblocking() -> bool:
	# A phase platform must NOT appear among the planner's blocker rects.
	var ph := {"rect": Rect2(400, 500, 180, 16), "type": "solid", "phase": {"period": 2.0, "duty": 0.5, "offset": 0.0}}
	var m := {"width": 1920, "height": 1080, "platforms": [
		{"rect": Rect2(0, 1060, 1920, 20), "type": "solid"}, ph], "objects": []}
	for b in MapPlanner._blockers(m):
		if b.position.distance_to(Rect2(400, 500, 180, 16).grow(10.0).position) < 1.0:
			return false  # phase platform leaked into blockers
	return true

func _test_phase_landable() -> bool:
	# A phase platform is a non-wall surface, so it must be in _surfaces.
	var ph := {"rect": Rect2(400, 500, 180, 16), "type": "solid", "phase": {"period": 2.0, "duty": 0.5, "offset": 0.0}}
	var m := {"width": 1920, "height": 1080, "platforms": [ph], "objects": []}
	return MapPlanner._surfaces(m).has(ph)

func _test_gen_has_phase() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2-%d" % s)
		for p in m["platforms"]:
			if p.has("phase"):
				return true
	return false
