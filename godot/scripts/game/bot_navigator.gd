class_name BotNavigator
extends RefCounted
## Turns "get me to that spot" into frame-by-frame movement, using the
## MapPlanner navigation graph (surfaces + validated jump/fall/spring/portal
## edges). It localizes the pawn to a surface, BFS-paths to the goal surface,
## and drives the current edge: run to the takeoff, jump, steer to the
## landing. Replans every grounded frame (cheap over ~30 nodes), so a moving
## goal or a missed jump just re-routes on the next touchdown.
##
## Output is a neutral command {move_dir, jump, drop} so both consumers — the
## practice BotBrain (move_dir + poll_jump) and the Input-driven test bot —
## can apply it the same way.

var graph: Dictionary

var _cur := 0          # surface the pawn was last grounded on
var _path: Array = []  # surface indices, _cur .. goal
var _air_latched := false  # one jump/drop press per hop
var _was_grounded := false
var _stuck := 0.0
var _last_x := 0.0
# Per-hop retry variation: a jump that fails would otherwise repeat verbatim
# forever. Counting attempts at the same target lets us alternate the
# approach side and widen the run-up so the bot explores its way on.
var _hop_to := -1
var _hop_tries := 0


func _init(nav_graph: Dictionary) -> void:
	graph = nav_graph
	_cur = nav_graph.get("ground", 0)


## Clear per-pawn path state (used when a pawn is teleported, e.g. between
## soundness-test targets, so stale path/latch state doesn't carry over).
func reset() -> void:
	_path = []
	_air_latched = false
	_was_grounded = false
	_stuck = 0.0
	_cur = graph.get("ground", 0)


## Per-frame command toward goal_pos. me is the Player (any CharacterBody2D
## exposing is_on_floor()/global_position).
func navigate(me: Node, goal_pos: Vector2, delta: float) -> Dictionary:
	var cmd := {"move_dir": 0.0, "jump": false, "drop": false}
	if graph.is_empty() or graph["surfaces"].is_empty():
		return cmd
	var grounded: bool = me.is_on_floor()
	var px: float = me.global_position.x
	# Reset the per-hop jump latch only on a fresh landing, not every grounded
	# frame — otherwise the bot re-fires while walking up to a takeoff.
	if grounded and not _was_grounded:
		_air_latched = false
	_was_grounded = grounded
	if grounded:
		_cur = localize(me.global_position)
		_path = _plan(_cur, localize(goal_pos))

	if _path.size() <= 1:
		# On the goal surface (or stranded): home in on the exact x.
		cmd["move_dir"] = _toward(px, goal_pos.x, 8.0)
		_recover(me, delta, cmd)
		return cmd

	# Track attempts at the current hop so retries can vary (see _hop_tries).
	if _path[1] != _hop_to:
		_hop_to = _path[1]
		_hop_tries = 0

	var edge = _edge_to(_cur, _path[1])
	if edge == null:
		cmd["move_dir"] = _toward(px, _center_x(_path[1]), 8.0)
		_recover(me, delta, cmd)
		return cmd

	match edge["kind"]:
		"jump":
			_drive_jump(me, _path[1], edge, grounded, px, cmd)
		"spring":
			_drive_spring(me, _path[1], edge, grounded, px, cmd)
		"drop":
			cmd["move_dir"] = _toward(px, edge["land"].x, 6.0)
			if grounded and not _air_latched:
				if _is_thru(_cur):
					cmd["drop"] = true  # fall through the one-way platform
					cmd["jump"] = true
					_air_latched = true
				elif absf(px - edge["takeoff"].x) < 18.0:
					cmd["jump"] = true  # solid floor: hop toward the landing
					_air_latched = true
		"portal":
			cmd["move_dir"] = _toward(px, edge["takeoff"].x, 6.0)
	_recover(me, delta, cmd)
	return cmd


## Execute a jump onto surface `to_i`. A one-way (thru) platform is entered
## straight up from below; a solid one is approached from OUTSIDE a near edge.
func _drive_jump(me: Node, to_i: int, edge: Dictionary, grounded: bool, px: float, cmd: Dictionary) -> void:
	var br: Rect2 = graph["surfaces"][to_i]["rect"]
	if _is_thru(to_i):
		var aim := clampf(px, br.position.x + 6.0, br.end.x - 6.0)
		if grounded:
			cmd["move_dir"] = _toward(px, aim, 6.0)
			if not _air_latched and absf(px - aim) < 28.0:
				cmd["jump"] = true
				_air_latched = true
		else:
			cmd["move_dir"] = _air_steer_onto(me, br, true, true)
		return
	# Solid: jump from just outside the validated edge, then air-steer on.
	# Only after several failed attempts do we try the OTHER side (the planner's
	# side is usually right; flipping early just sends the bot over the target).
	var approach_left: bool = _approach_left(edge["takeoff"].x, br, px)
	if _hop_tries >= 3:
		approach_left = not approach_left
	var a_top := MapPlanner.surface_top_y(graph["surfaces"][_cur], px)
	var rise: float = maxf(0.0, a_top - br.position.y)
	var lead := clampf(rise * 0.6, 50.0, 120.0)
	var takeoff_x := (br.position.x - lead) if approach_left else (br.end.x + lead)
	if grounded:
		cmd["move_dir"] = _toward(px, takeoff_x, 6.0)
		if not _air_latched and absf(px - takeoff_x) < 20.0:
			cmd["jump"] = true
			_air_latched = true
			_hop_tries += 1
			cmd["move_dir"] = _air_steer_onto(me, br, approach_left, false)
	else:
		cmd["move_dir"] = _air_steer_onto(me, br, approach_left, false)


## Ride a spring onto surface `to_i`: walk onto the pad, then steer in flight.
func _drive_spring(me: Node, to_i: int, edge: Dictionary, grounded: bool, px: float, cmd: Dictionary) -> void:
	var br: Rect2 = graph["surfaces"][to_i]["rect"]
	if grounded:
		cmd["move_dir"] = _toward(px, edge["takeoff"].x, 4.0)
	else:
		var approach_left: bool = edge["takeoff"].x <= br.get_center().x
		cmd["move_dir"] = _air_steer_onto(me, br, approach_left, _is_thru(to_i))


func _approach_left(takeoff_x: float, br: Rect2, px: float) -> bool:
	if takeoff_x <= br.position.x:
		return true
	if takeoff_x >= br.end.x:
		return false
	return absf(px - br.position.x) <= absf(px - br.end.x)


## In-flight steering onto a target platform, gated on vertical velocity.
## While RISING, hold just outside the near edge — committing over the span on
## the way up either bonks the solid underside or (off a tall spring) overshoots
## a narrow platform during the long climb. Only on the way DOWN does the body
## move over the span and settle straight onto the top. A thru platform has no
## underside, so just stay within its span and rise through it.
func _air_steer_onto(me: Node, br: Rect2, approach_left: bool, thru: bool) -> float:
	var px: float = me.global_position.x
	var half := GameConfig.PLAYER_SIZE * 0.5
	if thru:
		return _toward(px, clampf(px, br.position.x + 8.0, br.end.x - 8.0), 6.0)
	if me.velocity.y < 0.0:
		# Rising: hold a staging x just outside the near edge.
		var stage := (br.position.x - half * 1.4) if approach_left else (br.end.x + half * 1.4)
		return _toward(px, stage, 4.0)
	# Falling: get over the span, then settle straight down onto it.
	if px > br.position.x + 6.0 and px < br.end.x - 6.0:
		return _toward(px, clampf(px, br.position.x + 12.0, br.end.x - 12.0), 10.0)
	return _toward(px, (br.position.x + 14.0) if approach_left else (br.end.x - 14.0), 0.0)


func ground_index() -> int:
	return graph["ground"]


func debug_state() -> String:
	return "cur=%d path=%s" % [_cur, str(_path)]


## Surface indices reachable from the ground over the edge graph.
func reachable_indices() -> Array:
	var out: Array = []
	var seen := {graph["ground"]: true}
	var q: Array = [graph["ground"]]
	while not q.is_empty():
		var c: int = q.pop_front()
		out.append(c)
		for e in graph["edges"][c]:
			if not seen.has(e["to"]):
				seen[e["to"]] = true
				q.append(e["to"])
	return out


## A standing point on a surface (its center top, at the pawn's center
## height) — a goal to navigate to, and what localize() returns there.
func surface_goal(i: int) -> Vector2:
	var s: Dictionary = graph["surfaces"][i]
	var cx: float = (s["rect"] as Rect2).get_center().x
	return Vector2(cx, MapPlanner.surface_top_y(s, cx) - GameConfig.PLAYER_SIZE / 2.0)


## Surface index whose top is nearest the pawn's feet (the one it's standing
## on, or the nearest below when airborne). Falls back to the ground surface.
func localize(pos: Vector2) -> int:
	var surfaces: Array = graph["surfaces"]
	var feet := pos.y + GameConfig.PLAYER_SIZE / 2.0
	var best: int = graph["ground"]
	var best_dy := INF
	for i in surfaces.size():
		var r := MapPlanner.surface_sweep_rect(surfaces[i])
		if pos.x < r.position.x - 10.0 or pos.x > r.end.x + 10.0:
			continue
		var top := MapPlanner.surface_top_y(surfaces[i], clampf(pos.x, r.position.x, r.end.x))
		var dy := top - feet  # >= 0: surface at or below the feet
		if dy >= -24.0 and absf(dy) < best_dy:
			best_dy = absf(dy)
			best = i
	return best


## BFS over the edge graph: shortest hop count from surface to surface.
## Returns [from] when already there or no route exists (caller best-efforts).
func _plan(from_i: int, to_i: int) -> Array:
	if from_i == to_i:
		return [from_i]
	var prev := {}
	var seen := {from_i: true}
	var q: Array = [from_i]
	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur == to_i:
			break
		for e in graph["edges"][cur]:
			var nx: int = e["to"]
			if not seen.has(nx):
				seen[nx] = true
				prev[nx] = cur
				q.append(nx)
	if not seen.has(to_i):
		return [from_i]
	var path: Array = [to_i]
	while path[0] != from_i:
		path.insert(0, prev[path[0]])
	return path


func _edge_to(i: int, j: int):
	var best = null
	for e in graph["edges"][i]:
		if e["to"] != j:
			continue
		# A direct jump/drop beats a spring/portal to the same surface.
		if best == null or e["kind"] == "jump" or e["kind"] == "drop":
			best = e
	return best


func _toward(from_x: float, to_x: float, deadzone: float) -> float:
	var d := to_x - from_x
	return 0.0 if absf(d) <= deadzone else signf(d)


func _center_x(i: int) -> float:
	return (graph["surfaces"][i]["rect"] as Rect2).get_center().x


func _is_thru(i: int) -> bool:
	return graph["surfaces"][i].get("thru", false)


## If we're pushing into something and not moving, hop; if that fails for a
## while, back off so the next plan can find another way.
func _recover(me: Node, delta: float, cmd: Dictionary) -> void:
	if not me.is_on_floor():
		_stuck = 0.0
		return
	if cmd["move_dir"] != 0.0 and absf(me.global_position.x - _last_x) < 1.5:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_x = me.global_position.x
	if _stuck > 0.5 and not _air_latched:
		cmd["jump"] = true
		_air_latched = true
	if _stuck > 1.4:
		cmd["move_dir"] = -cmd["move_dir"]
		_stuck = 0.0
