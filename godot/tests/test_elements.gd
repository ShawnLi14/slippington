extends SceneTree
## Phase-A element unit tests (headless):
##   godot --headless --path . --script res://tests/test_elements.gd
## These exercise the autoload-free generation/planner layer only — node
## classes like PlatformBody/Player can't be instantiated under --script.

func _init() -> void:
	var failures := 0
	failures += _check("generation stays sound with conveyors", _test_gen_sound())
	failures += _check("some seed produces a conveyor", _test_gen_has_conveyor())
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
