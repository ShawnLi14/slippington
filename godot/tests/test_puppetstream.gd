extends SceneTree
## PuppetStream unit tests (headless):
##   godot --headless --path . --script res://tests/test_puppetstream.gd
##
## PuppetStream is the remote-puppet position interpolation extracted out of
## Player so the interpolate-vs-extrapolate decision is testable without the
## GameState autoload. The extrapolation case is the regression guard for the
## "tagged with no contact" overshoot: past the newest snapshot the rendered
## position is a GUESS that can drift into a chaser, so the tagger must use
## real_pos (the last actually-received position) for contact instead.

func _init() -> void:
	var failures := 0
	failures += _check("interpolates between snapshots", _test_interp())
	failures += _check("clamps before the first snapshot", _test_before())
	failures += _check("flags extrapolation and exposes real_pos", _test_extrap())
	failures += _check("caps extrapolation distance", _test_cap())
	failures += _check("reports empty with no snapshots", _test_empty())
	if failures > 0:
		print("FAILED: %d test(s)" % failures)
		quit(1)
		return
	print("DONE: PuppetStream ok")
	quit(0)


func _check(name: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + name)
	return 0 if ok else 1


func _snaps() -> Array:
	return [
		{"t": 1.00, "pos": Vector2(100, 0), "vel": Vector2(100, 0)},
		{"t": 1.10, "pos": Vector2(110, 0), "vel": Vector2(100, 0)},
	]


func _test_interp() -> bool:
	var r := PuppetStream.sample(_snaps(), 1.05)
	return r["pos"].is_equal_approx(Vector2(105, 0)) and not r["extrapolating"]


func _test_before() -> bool:
	var r := PuppetStream.sample(_snaps(), 0.50)
	return r["pos"] == Vector2(100, 0) and not r["extrapolating"]


func _test_extrap() -> bool:
	# 0.05s past the newest (1.10) snapshot, vel=100px/s -> a +5px guess.
	var r := PuppetStream.sample(_snaps(), 1.15)
	if not r["extrapolating"]:
		return false
	# The tagger must get the LAST REAL position (110), not the 115 guess.
	return r["real_pos"] == Vector2(110, 0) and r["pos"].is_equal_approx(Vector2(115, 0))


func _test_cap() -> bool:
	# 1.0s past newest would be +100px, but extrapolation caps at 0.1s -> +10px.
	var r := PuppetStream.sample(_snaps(), 2.10)
	return r["pos"].is_equal_approx(Vector2(120, 0))


func _test_empty() -> bool:
	var r := PuppetStream.sample([], 1.0)
	return r.get("empty", false)
