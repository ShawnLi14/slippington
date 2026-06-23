class_name LagCompHistory
extends RefCounted
## Host-side per-player position buffer for lag-compensated tag validation.
## Records timestamped positions and answers "where was this player at past
## time t?" by interpolating between samples. Extracted out of Player so it
## carries no GameState dependency and is unit-testable (tests/test_lagcomp.gd).

const WINDOW := 0.6  # seconds of history retained


var _samples: Array = []  # [{t, pos, teleport}] ascending by t


func record(t: float, pos: Vector2, is_teleport := false) -> void:
	_samples.append({"t": t, "pos": pos, "teleport": is_teleport})
	while not _samples.is_empty() and _samples[0]["t"] < t - WINDOW:
		_samples.pop_front()


## Interpolated position at past time t, clamped to the oldest/newest sample.
func position_at(t: float, fallback: Vector2) -> Vector2:
	if _samples.is_empty():
		return fallback
	if t <= _samples[0]["t"]:
		return _samples[0]["pos"]
	for i in range(_samples.size() - 1, -1, -1):
		if _samples[i]["t"] <= t:
			if i == _samples.size() - 1:
				return _samples[i]["pos"]
			var a: Dictionary = _samples[i]
			var b: Dictionary = _samples[i + 1]
			# Never interpolate across a teleport: the player jumped instantly,
			# so it was never between a and b. Clamp to the pre-teleport sample
			# rather than inventing a phantom midpoint the validator would tag.
			if b.get("teleport", false):
				return a["pos"]
			var span: float = b["t"] - a["t"]
			var f: float = 0.0 if span <= 0.0 else (t - a["t"]) / span
			return a["pos"].lerp(b["pos"], f)
	return _samples[0]["pos"]
