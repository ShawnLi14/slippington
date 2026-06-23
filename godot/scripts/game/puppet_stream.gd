class_name PuppetStream
extends RefCounted
## Pure interpolation over a remote player's position snapshots, extracted out
## of Player so the interpolate-vs-extrapolate decision is unit-testable
## (tests/test_puppetstream.gd) without the GameState autoload.
##
## snapshots = [{t, pos, vel}] ascending by t (sender timeline). Given a render
## time, returns where to draw the puppet AND whether that position is an
## extrapolated GUESS past the newest snapshot — which the tagger must not
## treat as real contact (it can drift into a chaser during a packet gap).

const MAX_EXTRAPOLATION := 0.1  # cap on how far past the newest snapshot we guess


## Returns {pos, extrapolating, real_pos}. While extrapolating, real_pos is the
## last actually-received position (use it for tag contact, not the guess).
## Returns {empty=true, ...} when there are no snapshots.
static func sample(snapshots: Array, render_t: float) -> Dictionary:
	if snapshots.is_empty():
		return {"empty": true, "pos": Vector2.ZERO, "extrapolating": false, "real_pos": Vector2.ZERO}
	var prev: Dictionary
	var next: Dictionary
	for s in snapshots:
		if s["t"] <= render_t:
			prev = s
		else:
			next = s
			break
	if prev.is_empty():
		var first: Vector2 = snapshots[0]["pos"]
		return {"pos": first, "extrapolating": false, "real_pos": first}
	elif next.is_empty():
		# Newest snapshot is older than the render time (packet gap): extrapolate
		# along last known velocity, but only briefly. The guess is NOT real.
		var dt: float = clampf(render_t - prev["t"], 0.0, MAX_EXTRAPOLATION)
		return {"pos": prev["pos"] + prev["vel"] * dt, "extrapolating": true, "real_pos": prev["pos"]}
	else:
		var span: float = next["t"] - prev["t"]
		var f: float = 0.0 if span <= 0.0 else (render_t - prev["t"]) / span
		var p: Vector2 = prev["pos"].lerp(next["pos"], f)
		return {"pos": p, "extrapolating": false, "real_pos": p}
