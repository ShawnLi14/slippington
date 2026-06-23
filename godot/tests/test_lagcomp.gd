extends SceneTree
## LagCompHistory unit tests (headless):
##   godot --headless --path . --script res://tests/test_lagcomp.gd
##
## LagCompHistory is the host-side per-player position buffer used to validate
## lag-compensated tag claims, extracted out of Player so it carries no
## GameState autoload dependency and can be exercised in isolation here.
## The teleport case is the regression guard for the "tagged with no contact"
## bug: position_at() must NEVER interpolate across a teleport and hand the
## validator a phantom position the player never occupied.

func _init() -> void:
	var failures := 0
	failures += _check("interpolates between samples", _test_interp())
	failures += _check("clamps before the first sample", _test_clamp_before())
	failures += _check("trims samples past the window", _test_trim())
	failures += _check("no phantom across a teleport", _test_no_phantom())
	if failures > 0:
		print("FAILED: %d test(s)" % failures)
		quit(1)
		return
	print("DONE: LagCompHistory ok")
	quit(0)


func _check(name: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + name)
	return 0 if ok else 1


func _test_interp() -> bool:
	var h := LagCompHistory.new()
	h.record(1.00, Vector2(100, 0))
	h.record(1.10, Vector2(200, 0))
	return h.position_at(1.05, Vector2.ZERO).is_equal_approx(Vector2(150, 0))


func _test_clamp_before() -> bool:
	var h := LagCompHistory.new()
	h.record(1.00, Vector2(100, 0))
	h.record(1.10, Vector2(200, 0))
	# A time before the oldest sample clamps to the oldest position.
	return h.position_at(0.50, Vector2(-1, -1)) == Vector2(100, 0)


func _test_trim() -> bool:
	var h := LagCompHistory.new()
	h.record(1.00, Vector2(0, 0))
	# Recording 1s later (> 0.6s window) must drop the stale 1.00 sample.
	h.record(2.00, Vector2(500, 0))
	# With only the 2.00 sample left, any lookup returns it.
	return h.position_at(1.00, Vector2.ZERO) == Vector2(500, 0)


func _test_no_phantom() -> bool:
	var h := LagCompHistory.new()
	h.record(1.00, Vector2(100, 0))
	h.record(1.02, Vector2(700, 0), true)  # teleport: 100 -> 700
	var p := h.position_at(1.01, Vector2.ZERO)  # mid-teleport in time
	# It was NEVER at the 400 midpoint. Must clamp to a real endpoint.
	return p == Vector2(100, 0) or p == Vector2(700, 0)
