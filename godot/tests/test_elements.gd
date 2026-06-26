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
	failures += _check("pinch partners are sweep-exempt", _test_pinch_sweep_exempt())
	failures += _check("pinch mover is not a blocker", _test_pinch_nonblocking())
	failures += _check("some seed produces a pinch pair", _test_gen_has_pinch())
	failures += _check("launcher reaches an in-arc target", _test_launcher_edge())
	failures += _check("launcher rejects an out-of-arc target", _test_launcher_miss())
	failures += _check("some seed produces a launcher", _test_gen_has_launcher())
	failures += _check("updraft lifts to an in-column target", _test_updraft_edge())
	failures += _check("updraft rejects an out-of-column target", _test_updraft_miss())
	failures += _check("some seed produces an updraft", _test_gen_has_updraft())
	failures += _check("force_landmark pins column 0", _test_force_landmark())
	failures += _check("the Mill builds 4 conveyor belts", _test_mill_builds())
	failures += _check("the Shaft builds a vertical elevator", _test_shaft_builds())
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

func _test_pinch_sweep_exempt() -> bool:
	# Two counter-phase movers whose sweeps overlap in the middle must NOT be
	# flagged as colliding with each other (they're never co-located in time).
	var a := {"rect": Rect2(700, 980, 120, 16), "type": "solid",
		"move": {"axis": "x", "amplitude": 120.0, "period": 3.0, "phase": 0.0, "pinch": 1}}
	var b := {"rect": Rect2(940, 980, 120, 16), "type": "solid",
		"move": {"axis": "x", "amplitude": 120.0, "period": 3.0, "phase": 0.5, "pinch": 1}}
	var m := {"width": 1920, "height": 1080, "platforms": [
		{"rect": Rect2(0, 1060, 1920, 20), "type": "solid"}, a, b], "objects": []}
	return not MapPlanner._mover_sweep_collides(m, a) and not MapPlanner._mover_sweep_collides(m, b)

func _test_pinch_nonblocking() -> bool:
	# A pinch-pair mover must be excluded from blockers (the gap opens every
	# cycle). With only the ground + one pinch mover, blockers should contain
	# ONLY the ground rect.
	var pm := {"rect": Rect2(700, 700, 120, 16), "type": "solid",
		"move": {"axis": "x", "amplitude": 100.0, "period": 3.0, "phase": 0.0, "pinch": 1}}
	var m := {"width": 1920, "height": 1080, "platforms": [
		{"rect": Rect2(0, 1060, 1920, 20), "type": "solid"}, pm], "objects": []}
	return MapPlanner._blockers(m).size() == 1

func _test_gen_has_pinch() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2-%d" % s)
		for p in m["platforms"]:
			if p.get("move", {}).has("pinch"):
				return true
	return false

func _test_launcher_edge() -> bool:
	var support := {"rect": Rect2(200, 900, 200, 16), "type": "solid"}
	var target := {"rect": Rect2(640, 640, 200, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	# pad sits on the support, fires up-and-right
	return MapPlanner._launcher_edge_ok(Vector2(300, 893), Vector2(260, -700), support, target, blockers)

func _test_launcher_miss() -> bool:
	var support := {"rect": Rect2(200, 900, 200, 16), "type": "solid"}
	# Reachable in HEIGHT (rise 193 < apex), but far LEFT — beyond the launch's
	# rightward horizontal reach, so the direction/range guard must reject it.
	var target := {"rect": Rect2(-600, 700, 200, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	return not MapPlanner._launcher_edge_ok(Vector2(300, 893), Vector2(260, -700), support, target, blockers)

func _test_gen_has_launcher() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2b-%d" % s)
		for o in m.get("objects", []):
			if o["type"] == "launcher":
				return true
	return false

func _test_updraft_edge() -> bool:
	var support := {"rect": Rect2(400, 900, 160, 16), "type": "solid"}
	var target := {"rect": Rect2(420, 600, 120, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	# column spans x 400..560, y 560..900 (base just above support)
	return MapPlanner._updraft_edge_ok(Rect2(400, 560, 160, 340), support, target, blockers)

func _test_updraft_miss() -> bool:
	var support := {"rect": Rect2(400, 900, 160, 16), "type": "solid"}
	var target := {"rect": Rect2(900, 600, 120, 16), "type": "solid"}  # far right, outside column
	var blockers: Array[Rect2] = []
	return not MapPlanner._updraft_edge_ok(Rect2(400, 560, 160, 340), support, target, blockers)

func _test_gen_has_updraft() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2b-%d" % s)
		for o in m.get("objects", []):
			if o["type"] == "updraft":
				return true
	return false

func _test_force_landmark() -> bool:
	# Forcing a known landmark must place its signature in column 0 (cx≈240).
	# "pocket" emits wall platforms; without the hook a fixed seed won't put
	# them in col 0.
	MapGenerator.force_landmark = "pocket"
	var m := MapGenerator.generate("a3-force")
	MapGenerator.force_landmark = ""
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if p["type"] == "wall" and r.position.x + r.size.x / 2.0 < 440.0:
			return true
	return false

func _test_mill_builds() -> bool:
	# The Mill is 4 conveyor belts; every platform stays within HALF (150) of cx
	# and carries a conveyor.
	var m := MapGenerator._mill(300.0, SeededRng.new("m"))
	var plats: Array = m["platforms"]
	if plats.size() != 4:
		return false
	for p in plats:
		if p.get("conveyor", {}).is_empty():
			return false
		var r: Rect2 = p["rect"]
		if r.position.x < 300.0 - 150.0 or r.end.x > 300.0 + 150.0:
			return false
	return true

func _test_shaft_builds() -> bool:
	# The Shaft has static side ledges plus at least one vertical (axis "y")
	# elevator; everything within HALF (120) of cx.
	var m := MapGenerator._shaft(500.0, SeededRng.new("s"))
	var has_ymover := false
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if r.position.x < 500.0 - 120.0 or r.end.x > 500.0 + 120.0:
			return false
		if p.get("move", {}).get("axis", "x") == "y":
			has_ymover = true
	return has_ymover
