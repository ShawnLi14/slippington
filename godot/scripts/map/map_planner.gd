class_name MapPlanner
## Post-generation map planning: builds a real traversal graph from jump
## physics (arcs with horizontal drift, walls and platform undersides as
## blockers, fall/spring/portal edges), flood-fills from the ground, and
## deterministically repairs or removes anything unreachable. Also enforces
## object rules: springs need a landing target and head clearance, portal
## arrivals need player clearance, movers must not sweep through geometry.
##
## Pure functions over map-data dictionaries — no scene or autoload
## dependencies, so headless tests can run it directly.

# Conservative physics: the slowest class (0.9x speed) with the lowest
# jump (1.0x) must be able to traverse everything.
const SPEED := 270.0
const JUMP_V := 450.0
const SPRING_V := 780.0
const GRAVITY := 800.0
const EDGE_MARGIN := 20.0      # required slack on horizontal reach
const HEIGHT_MARGIN := 6.0     # required slack on vertical reach
const BLOCK_INFLATE := 10.0    # blocker rects grow by this for the player's body
const REPAIR_PASSES := 3


static func jump_height() -> float:
	return JUMP_V * JUMP_V / (2.0 * GRAVITY) - HEIGHT_MARGIN


static func spring_height() -> float:
	return SPRING_V * SPRING_V / (2.0 * GRAVITY) - HEIGHT_MARGIN


## Repairs the map in place (adds/removes platforms and objects) until the
## traversal graph is fully connected from the ground. Deterministic: all
## randomness comes from the caller's seeded rng.
static func plan(map: Dictionary, rng: SeededRng) -> Dictionary:
	_strip_colliding_movers(map)
	for pass_i in REPAIR_PASSES:
		var unreachable := _unreachable_surfaces(map)
		if unreachable.is_empty():
			break
		for surf in unreachable:
			_repair_surface(map, surf, rng)
	# Anything still orphaned gets deleted along with objects riding it.
	for surf in _unreachable_surfaces(map):
		_delete_surface(map, surf)
	_scrub_objects(map)
	# Removing objects can remove access routes — one more repair round.
	for surf in _unreachable_surfaces(map):
		_repair_surface(map, surf, rng)
	for surf in _unreachable_surfaces(map):
		_delete_surface(map, surf)
	_fix_spawns(map, rng)
	return map


## Returns human-readable issues; empty array = the map is sound.
static func validate(map: Dictionary) -> Array:
	var issues: Array = []
	for surf in _unreachable_surfaces(map):
		var r: Rect2 = surf["rect"]
		issues.append("unreachable %s at %.0f,%.0f" % [surf["type"], r.position.x, r.position.y])
	for obj in map.get("objects", []):
		if obj["type"] == "spring":
			if _spring_support(map, obj) == null:
				issues.append("floating spring at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
			elif not _spring_has_headroom(map, obj):
				issues.append("spring under ceiling at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
			elif not _spring_has_target(map, obj):
				issues.append("spring with no landing target at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
		elif obj["type"] == "portal":
			if _portal_support(map, obj["pos"]) == null:
				issues.append("portal entrance unsupported at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
			elif _portal_support(map, obj["dest"]) == null:
				issues.append("portal exit unsupported at %.0f,%.0f" % [obj["dest"].x, obj["dest"].y])
			elif not _point_has_clearance(map, obj["dest"]):
				issues.append("portal exit blocked at %.0f,%.0f" % [obj["dest"].x, obj["dest"].y])
	for p in map["platforms"]:
		if p.has("move") and _mover_sweep_collides(map, p):
			var r: Rect2 = p["rect"]
			issues.append("mover sweeps through geometry at %.0f,%.0f" % [r.position.x, r.position.y])
	return issues


# --- traversal graph -------------------------------------------------------------

static func _surfaces(map: Dictionary) -> Array:
	var out: Array = []
	for p in map["platforms"]:
		if p["type"] != "wall":
			out.append(p)
	return out


static func _blockers(map: Dictionary) -> Array[Rect2]:
	# Walls and solid platforms block movement arcs; passthrough does not.
	var out: Array[Rect2] = []
	for p in map["platforms"]:
		if p["type"] == "wall" or p["type"] == "solid" or p["type"] == "ice":
			out.append(_sweep_rect(p).grow(BLOCK_INFLATE))
	return out


## A mover's rect expanded across its full travel range.
static func _sweep_rect(p: Dictionary) -> Rect2:
	var r: Rect2 = p["rect"]
	if not p.has("move"):
		return r
	var a: float = p["move"]["amplitude"]
	if p["move"]["axis"] == "y":
		return Rect2(r.position - Vector2(0, a), r.size + Vector2(0, 2 * a))
	return Rect2(r.position - Vector2(a, 0), r.size + Vector2(2 * a, 0))


static func _segment_blocked(seg_a: Vector2, seg_b: Vector2, blockers: Array[Rect2], skip: Array) -> bool:
	for b in blockers:
		# Skip the inflated rects belonging to the takeoff/landing surfaces.
		var skipped := false
		for s in skip:
			if _sweep_rect(s).grow(BLOCK_INFLATE).is_equal_approx(b):
				skipped = true
				break
		if skipped:
			continue
		if _segment_hits_rect(seg_a, seg_b, b):
			return true
	return false


static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	# Sample along the segment — robust enough at platform scale.
	for i in range(1, 8):
		if r.has_point(a.lerp(b, float(i) / 8.0)):
			return true
	return false


## Can a player travel from surface `a` to surface `b`? Jump or fall, with
## a 3-point arc (takeoff, apex, landing) checked against blockers.
static func _edge_ok(a: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	if a == b:
		return false
	var ra := _sweep_rect(a)
	var rb := _sweep_rect(b)
	var ay := ra.position.y
	var by := rb.position.y
	var rise := ay - by  # > 0 means b is above a
	if rise > jump_height():
		return false
	# Nearest takeoff/landing x.
	var tx := clampf(rb.get_center().x, ra.position.x, ra.position.x + ra.size.x)
	var lx := clampf(tx, rb.position.x, rb.position.x + rb.size.x)
	var gap := absf(lx - tx)
	# Air time: rise to apex, then fall to b's height.
	var t_up := JUMP_V / GRAVITY
	var apex := jump_height() + HEIGHT_MARGIN
	var fall_h := apex - rise
	if fall_h < 0.0:
		return false
	var t := t_up + sqrt(2.0 * fall_h / GRAVITY)
	if gap + EDGE_MARGIN > SPEED * t:
		return false
	var takeoff := Vector2(tx, ay - 4.0)
	var apex_pt := Vector2((tx + lx) / 2.0, ay - apex - GameConfig.PLAYER_SIZE / 2.0)
	var land := Vector2(lx, by - 6.0)
	var skip := [a, b]
	return not _segment_blocked(takeoff, apex_pt, blockers, skip) \
		and not _segment_blocked(apex_pt, land, blockers, skip)


static func _spring_edge_ok(pad_pos: Vector2, support: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	var rb := _sweep_rect(b)
	var rise := pad_pos.y - rb.position.y
	if rise > spring_height() or b == support:
		return false
	var t_up := SPRING_V / GRAVITY
	var fall_h := spring_height() + HEIGHT_MARGIN - rise
	var t := t_up + sqrt(2.0 * maxf(fall_h, 0.0) / GRAVITY)
	# The player steers during flight, so several landing points are
	# plausible — accept the edge if any unobstructed one is in range.
	var candidates := [
		clampf(pad_pos.x, rb.position.x, rb.position.x + rb.size.x),
		rb.position.x + 25.0,
		rb.position.x + rb.size.x - 25.0,
	]
	var skip := [support, b]
	for lx in candidates:
		if absf(lx - pad_pos.x) + EDGE_MARGIN > SPEED * t:
			continue
		# Drift happens during ascent too: apex sits between pad and landing.
		var apex_pt := Vector2(lerpf(pad_pos.x, lx, 0.5), pad_pos.y - spring_height() - GameConfig.PLAYER_SIZE / 2.0)
		var land := Vector2(lx, rb.position.y - 6.0)
		if not _segment_blocked(pad_pos + Vector2(0, -8), apex_pt, blockers, skip) \
				and not _segment_blocked(apex_pt, land, blockers, skip):
			return true
	return false


## Surface directly under a point (springs sit ~7px above their platform;
## portals hover ~36px above theirs).
static func _support_under(map: Dictionary, pos: Vector2, max_drop := 70.0):
	var best = null
	var best_dy := max_drop
	for s in _surfaces(map):
		var r := _sweep_rect(s)
		if pos.x >= r.position.x - 4.0 and pos.x <= r.position.x + r.size.x + 4.0:
			var dy := r.position.y - pos.y
			if dy >= -4.0 and dy <= best_dy:
				best_dy = dy
				best = s
	return best


static func _spring_support(map: Dictionary, obj: Dictionary):
	return _support_under(map, obj["pos"], 20.0)


static func _portal_support(map: Dictionary, pos: Vector2):
	return _support_under(map, pos, 70.0)


## BFS from the ground over jump/fall/spring/portal edges; returns the set
## of reachable surfaces (as an Array of platform dicts).
static func _reachable_set(map: Dictionary) -> Array:
	var surfaces := _surfaces(map)
	if surfaces.is_empty():
		return []
	var blockers := _blockers(map)
	var ground = null
	for s in surfaces:
		if ground == null or s["rect"].position.y > ground["rect"].position.y:
			ground = s
	var reachable := [ground]
	var frontier := [ground]
	while not frontier.is_empty():
		var cur = frontier.pop_back()
		for s in surfaces:
			if s in reachable:
				continue
			if _edge_ok(cur, s, blockers):
				reachable.append(s)
				frontier.append(s)
		for obj in map.get("objects", []):
			if obj["type"] == "spring":
				var support = _spring_support(map, obj)
				if support != cur:
					continue
				for s in surfaces:
					if s in reachable:
						continue
					if _spring_edge_ok(obj["pos"], support, s, blockers):
						reachable.append(s)
						frontier.append(s)
			elif obj["type"] == "portal":
				var enter = _portal_support(map, obj["pos"])
				var exit_surf = _portal_support(map, obj["dest"])
				if enter == cur and exit_surf != null and not exit_surf in reachable:
					reachable.append(exit_surf)
					frontier.append(exit_surf)
	return reachable


static func _unreachable_surfaces(map: Dictionary) -> Array:
	var reachable := _reachable_set(map)
	var out: Array = []
	for s in _surfaces(map):
		if not s in reachable:
			out.append(s)
	# Lowest first: fixing low surfaces can unlock everything above them.
	out.sort_custom(func(a, b): return a["rect"].position.y > b["rect"].position.y)
	return out


# --- repairs ----------------------------------------------------------------------

static func _repair_surface(map: Dictionary, surf: Dictionary, rng: SeededRng) -> void:
	var reachable := _reachable_set(map)
	if surf in reachable or reachable.is_empty():
		return
	# Nearest reachable surface as the repair anchor.
	var target_rect: Rect2 = surf["rect"]
	var anchor = null
	var best := INF
	for r in reachable:
		var d: float = r["rect"].get_center().distance_to(target_rect.get_center())
		if d < best:
			best = d
			anchor = r
	if anchor == null:
		return
	var anchor_rect: Rect2 = anchor["rect"]
	var blockers := _blockers(map)

	# Repair A: a stepping platform halfway between anchor and target.
	var mid := (anchor_rect.get_center() + target_rect.get_center()) / 2.0
	for attempt in 4:
		var w := 150.0
		var x := clampf(mid.x - w / 2.0 + rng.next_float(-70.0, 70.0), 20.0, GameConfig.MAP_WIDTH - w - 20.0)
		var y := clampf(mid.y + rng.next_float(-40.0, 40.0), 90.0, GameConfig.MAP_HEIGHT - 120.0)
		var rect := Rect2(x, y, w, 16.0)
		var collides := false
		for p in map["platforms"]:
			if _sweep_rect(p).grow(40.0).intersects(rect):
				collides = true
				break
		if collides:
			continue
		var step := {"rect": rect, "type": "solid"}
		map["platforms"].append(step)
		if _edge_ok(anchor, step, _blockers(map)) and _edge_ok(step, surf, _blockers(map)):
			return  # success
		map["platforms"].erase(step)

	# Repair B: a spring on the anchor aimed at the target.
	var rise := anchor_rect.position.y - target_rect.position.y
	if rise > 0.0 and rise < spring_height():
		var pad_x := clampf(target_rect.get_center().x, anchor_rect.position.x + 20.0, anchor_rect.position.x + anchor_rect.size.x - 20.0)
		var pad := {"type": "spring", "pos": Vector2(pad_x, anchor_rect.position.y - 7.0)}
		map["objects"].append(pad)
		if _spring_edge_ok(pad["pos"], anchor, surf, blockers) and _spring_has_headroom(map, pad):
			return
		map["objects"].erase(pad)
	# Couldn't repair — the delete pass will clean it up.


static func _delete_surface(map: Dictionary, surf: Dictionary) -> void:
	# Remove objects standing on it first.
	var doomed: Array = []
	for obj in map.get("objects", []):
		if obj["type"] == "spring" and _spring_support(map, obj) == surf:
			doomed.append(obj)
		elif obj["type"] == "portal" and (_portal_support(map, obj["pos"]) == surf or _portal_support(map, obj["dest"]) == surf):
			doomed.append(obj)
	for obj in doomed:
		map["objects"].erase(obj)
	map["platforms"].erase(surf)


# --- object rules -------------------------------------------------------------------

static func _spring_has_headroom(map: Dictionary, obj: Dictionary) -> bool:
	var top := Vector2(obj["pos"].x, obj["pos"].y - 150.0)
	for p in map["platforms"]:
		if p["type"] == "passthrough":
			continue
		if _segment_hits_rect(obj["pos"] + Vector2(0, -10), top, _sweep_rect(p)):
			return false
	return true


static func _spring_has_target(map: Dictionary, obj: Dictionary) -> bool:
	var support = _spring_support(map, obj)
	if support == null:
		return false
	var blockers := _blockers(map)
	for s in _surfaces(map):
		if s == support:
			continue
		if s["rect"].position.y < obj["pos"].y - 30.0 and _spring_edge_ok(obj["pos"], support, s, blockers):
			return true
	return false


static func _point_has_clearance(map: Dictionary, pos: Vector2) -> bool:
	var box := Rect2(pos - Vector2(24, 24), Vector2(48, 48))
	for p in map["platforms"]:
		if _sweep_rect(p).intersects(box):
			return false
	return true


static func _mover_sweep_collides(map: Dictionary, mover: Dictionary) -> bool:
	var sweep := _sweep_rect(mover).grow(8.0)
	for p in map["platforms"]:
		if p == mover:
			continue
		if sweep.intersects(p["rect"]):
			return true
	return false


static func _strip_colliding_movers(map: Dictionary) -> void:
	for p in map["platforms"]:
		if p.has("move") and _mover_sweep_collides(map, p):
			p.erase("move")


static func _scrub_objects(map: Dictionary) -> void:
	var keep: Array[Dictionary] = []
	var dropped_portal := false
	for obj in map.get("objects", []):
		var ok := true
		if obj["type"] == "spring":
			ok = _spring_support(map, obj) != null \
				and _spring_has_headroom(map, obj) \
				and _spring_has_target(map, obj)
		elif obj["type"] == "portal":
			ok = _portal_support(map, obj["pos"]) != null \
				and _portal_support(map, obj["dest"]) != null \
				and _point_has_clearance(map, obj["dest"])
			if not ok:
				dropped_portal = true
		if ok:
			keep.append(obj)
	if dropped_portal:
		# Portals come in pairs — if either direction is invalid, drop both.
		keep = keep.filter(func(o): return o["type"] != "portal")
	map["objects"] = keep


# --- spawns -------------------------------------------------------------------------

static func _fix_spawns(map: Dictionary, rng: SeededRng) -> void:
	var reachable := _reachable_set(map)
	if reachable.is_empty():
		return
	# Candidates: centered above wide reachable surfaces, lowest first.
	var candidates: Array[Vector2] = []
	var sorted := reachable.duplicate()
	sorted.sort_custom(func(a, b):
		if a["rect"].position.y != b["rect"].position.y:
			return a["rect"].position.y > b["rect"].position.y
		return a["rect"].position.x < b["rect"].position.x
	)
	for s in sorted:
		var r: Rect2 = s["rect"]
		if r.size.x < 120.0 or s.has("move"):
			continue
		# Wide surfaces (like the ground) yield several spread-out spots.
		var count := maxi(1, int(r.size.x / 480.0))
		for i in count:
			var x := r.position.x + r.size.x * (float(i) + 0.5) / float(count)
			candidates.append(Vector2(x, r.position.y - GameConfig.PLAYER_SIZE))
	var picked: Array[Vector2] = []
	for c in candidates:
		var far := true
		for p in picked:
			if p.distance_to(c) < 450.0:
				far = false
				break
		if far:
			picked.append(c)
		if picked.size() >= 4:
			break
	# Ground fallbacks keep at least two spawns.
	while picked.size() < 2:
		picked.append(Vector2(
			float(rng.next_int(150, GameConfig.MAP_WIDTH - 150)),
			GameConfig.MAP_HEIGHT - 20.0 - GameConfig.PLAYER_SIZE))
	map["spawn_points"] = picked
