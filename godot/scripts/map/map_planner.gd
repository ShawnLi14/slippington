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

# Conservative physics: every class now runs at 1.1x (330), but planning
# with the old 0.9x speed keeps a safety margin AND keeps existing seeds
# generating identical maps — raise only with a deliberate map reroll.
const SPEED := 270.0
const JUMP_V := 450.0
const SPRING_V := 780.0
const GRAVITY := 800.0
const EDGE_MARGIN := 20.0      # required slack on horizontal reach
const HEIGHT_MARGIN := 6.0     # required slack on vertical reach
const BLOCK_INFLATE := 10.0    # blocker rects grow by this for the player's body
const REPAIR_PASSES := 3
## A cut vertex only counts as a bottleneck when it gates this many
## surfaces. Ladder structures (mast, scaffold) are cut-vertex chains by
## design, and a one-or-two-perch dead end is fine — you can always drop
## off. The rule exists to stop a chaser camping the only way into a
## whole REGION.
const MIN_BOTTLENECK_ORPHANS := 3


static func jump_height() -> float:
	return JUMP_V * JUMP_V / (2.0 * GRAVITY) - HEIGHT_MARGIN


static func spring_height() -> float:
	return SPRING_V * SPRING_V / (2.0 * GRAVITY) - HEIGHT_MARGIN


## Repairs the map in place (adds/removes platforms and objects) until the
## traversal graph is fully connected from the ground AND 2-connected (no
## single surface is the only route anywhere). Deterministic: all
## randomness comes from the caller's seeded rng.
##
## The stages interact (a bottleneck repair can put a step over a spring;
## an object scrub can remove a route), so the whole pipeline iterates to
## a fixed point.
static func plan(map: Dictionary, rng: SeededRng) -> Dictionary:
	_strip_colliding_movers(map)
	for outer in 3:
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
		# Route diversity: no single surface may be the only way anywhere.
		_repair_bottlenecks(map, rng)
		# Re-strip any movers whose sweeps now conflict with new repair connectors.
		_strip_colliding_movers(map)
		if validate(map).is_empty():
			break
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
		elif obj["type"] == "launcher":
			if _support_under(map, obj["pos"], 20.0) == null:
				issues.append("launcher unsupported at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
			elif not _launcher_has_target(map, obj):
				issues.append("launcher with no target at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
	for p in map["platforms"]:
		if p.has("move") and _mover_sweep_collides(map, p):
			var r: Rect2 = p["rect"]
			issues.append("mover sweeps through geometry at %.0f,%.0f" % [r.position.x, r.position.y])
	for b in _find_bottlenecks(map):
		var r: Rect2 = b["cut"]["rect"]
		issues.append("bottleneck at %.0f,%.0f isolates %d surface(s)" % [r.position.x, r.position.y, b["orphans"].size()])
	return issues


# --- traversal graph -------------------------------------------------------------

static func _surfaces(map: Dictionary) -> Array:
	var out: Array = []
	for p in map["platforms"]:
		if p["type"] != "wall":
			out.append(p)
	return out


static func _blockers(map: Dictionary) -> Array[Rect2]:
	# Anything you can't pass through blocks movement arcs. "thru" variants,
	# phase platforms (open part of every cycle), and pinch-pair movers (the
	# gap opens every cycle) are timing elements you can always wait out, so
	# they must never sever a route — exclude them from blockers.
	var out: Array[Rect2] = []
	for p in map["platforms"]:
		if p.get("thru", false) or p.has("phase") or p.get("move", {}).has("pinch"):
			continue
		out.append(_sweep_rect(p).grow(BLOCK_INFLATE))
	return out


## Angled platforms are 16px-thick slabs; their bounding rect includes the
## thickness, so the walk surface's low end sits this far above rect bottom.
const RAMP_THICKNESS := 16.0


## Walkable height of a surface at horizontal position x (clamped into the
## surface's span). Flat platforms are their rect top; ramps ("ramp": 1
## rises to the right, -1 to the left) interpolate along the incline.
static func _top_y_at(s: Dictionary, x: float) -> float:
	var r := _sweep_rect(s)
	if not s.has("ramp"):
		return r.position.y
	var f := clampf((x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
	if s["ramp"] < 0:
		f = 1.0 - f
	var low_y := r.end.y - RAMP_THICKNESS
	return low_y - (low_y - r.position.y) * f


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
	# Takeoff/landing geometry uses the BASE rect: a mover sits at its sweep
	# extremes only for an instant, so an arc that needs the platform at the
	# far end of its patrol is not honest reachability. (Blockers still use
	# the full sweep — the patrol genuinely occupies that band.)
	var ra: Rect2 = a["rect"]
	var rb: Rect2 = b["rect"]
	var skip := [a, b]
	# Several candidate landings (nearest point, then each end of the
	# target): a central pillar — like the mast spine — can block the
	# straight arc while a side approach works fine. Heights read off the
	# actual walk surface, so ramps take off from / land on their incline.
	var lxs := [
		clampf(clampf(rb.get_center().x, ra.position.x, ra.end.x), rb.position.x, rb.end.x),
		rb.position.x + 25.0,
		rb.end.x - 25.0,
	]
	for lx in lxs:
		var tx := clampf(lx, ra.position.x, ra.end.x)
		var ay := _top_y_at(a, tx)
		var by := _top_y_at(b, lx)
		var rise := ay - by  # > 0 means b is above a
		if rise > jump_height():
			continue
		var gap := absf(lx - tx)
		# Air time: rise to apex, then fall to b's height.
		var t_up := JUMP_V / GRAVITY
		var apex := jump_height() + HEIGHT_MARGIN
		var fall_h := apex - rise
		if fall_h < 0.0:
			continue
		var t := t_up + sqrt(2.0 * fall_h / GRAVITY)
		if gap + EDGE_MARGIN > SPEED * t:
			continue
		var takeoff := Vector2(tx, ay - 4.0)
		var apex_pt := Vector2((tx + lx) / 2.0, ay - apex - GameConfig.PLAYER_SIZE / 2.0)
		var land := Vector2(lx, by - 6.0)
		if not _segment_blocked(takeoff, apex_pt, blockers, skip) \
				and not _segment_blocked(apex_pt, land, blockers, skip):
			return true
	return false


static func _spring_edge_ok(pad_pos: Vector2, support: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	var rb: Rect2 = b["rect"]  # base rect — same honesty rule as _edge_ok
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


## Can a player launched from `pad_pos` with initial velocity `vel` (up and
## sideways) reach surface `b`? Models the projectile arc plus air-steering,
## conservatively (plans at SPEED). vel.y is negative (up).
static func _launcher_edge_ok(pad_pos: Vector2, vel: Vector2, support: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	if b == support:
		return false
	var rb: Rect2 = b["rect"]
	var apex_h: float = vel.y * vel.y / (2.0 * GRAVITY)  # height gained above the pad
	var rise: float = pad_pos.y - rb.position.y           # > 0 means b is above the pad
	if rise > apex_h - HEIGHT_MARGIN:
		return false
	var t_up: float = -vel.y / GRAVITY
	var fall_h: float = apex_h + HEIGHT_MARGIN - rise
	var t: float = t_up + sqrt(2.0 * maxf(fall_h, 0.0) / GRAVITY)
	# Where the launch carries you horizontally, plus air-steering both ways.
	var center_x: float = pad_pos.x + vel.x * t
	var reach: float = SPEED * t + EDGE_MARGIN
	var candidates := [
		clampf(center_x, rb.position.x, rb.end.x),
		rb.position.x + 25.0,
		rb.end.x - 25.0,
	]
	var skip := [support, b]
	for lx in candidates:
		if absf(lx - center_x) > reach:
			continue
		var apex_pt := Vector2(lerpf(pad_pos.x, lx, 0.5), pad_pos.y - apex_h - GameConfig.PLAYER_SIZE / 2.0)
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
			var dy := _top_y_at(s, pos.x) - pos.y
			if dy >= -4.0 and dy <= best_dy:
				best_dy = dy
				best = s
	return best


static func _spring_support(map: Dictionary, obj: Dictionary):
	return _support_under(map, obj["pos"], 20.0)


static func _portal_support(map: Dictionary, pos: Vector2):
	return _support_under(map, pos, 70.0)


## Builds the full traversal graph ONCE: surfaces as indexed nodes, with
## directed adjacency from jump/fall arcs, spring launches and portals.
## All reachability questions (including cut-vertex analysis) then run as
## cheap BFS over the cached adjacency.
static func _build_graph(map: Dictionary) -> Dictionary:
	var surfaces := _surfaces(map)
	var blockers := _blockers(map)
	var n := surfaces.size()
	var adj: Array = []
	for i in n:
		adj.append([])
	for i in n:
		for j in n:
			if i != j and _edge_ok(surfaces[i], surfaces[j], blockers):
				adj[i].append(j)
	for obj in map.get("objects", []):
		if obj["type"] == "spring":
			var support = _spring_support(map, obj)
			if support == null:
				continue
			var si := surfaces.find(support)
			for j in n:
				if j != si and _spring_edge_ok(obj["pos"], support, surfaces[j], blockers):
					if not j in adj[si]:
						adj[si].append(j)
		elif obj["type"] == "portal":
			var enter = _portal_support(map, obj["pos"])
			var exit_surf = _portal_support(map, obj["dest"])
			if enter != null and exit_surf != null:
				var ei := surfaces.find(enter)
				var xi := surfaces.find(exit_surf)
				if ei != xi and not xi in adj[ei]:
					adj[ei].append(xi)
		elif obj["type"] == "launcher":
			var lsupport = _support_under(map, obj["pos"], 20.0)
			if lsupport == null:
				continue
			var li := surfaces.find(lsupport)
			for j in n:
				if j != li and _launcher_edge_ok(obj["pos"], obj["vel"], lsupport, surfaces[j], blockers):
					if not j in adj[li]:
						adj[li].append(j)
	var ground := 0
	for i in n:
		if surfaces[i]["rect"].position.y > surfaces[ground]["rect"].position.y:
			ground = i
	return {"surfaces": surfaces, "adj": adj, "ground": ground}


## BFS over a prebuilt graph; skip_idx simulates removing one surface.
static func _bfs(graph: Dictionary, skip_idx := -1) -> Array:
	var n: int = graph["surfaces"].size()
	var reached: Array = []
	reached.resize(n)
	reached.fill(false)
	var ground: int = graph["ground"]
	if n == 0 or ground == skip_idx:
		return reached
	reached[ground] = true
	var frontier: Array = [ground]
	while not frontier.is_empty():
		var cur: int = frontier.pop_back()
		for nxt in graph["adj"][cur]:
			if nxt != skip_idx and not reached[nxt]:
				reached[nxt] = true
				frontier.append(nxt)
	return reached


static func _reachable_set(map: Dictionary) -> Array:
	var graph := _build_graph(map)
	var reached := _bfs(graph)
	var out: Array = []
	for i in graph["surfaces"].size():
		if reached[i]:
			out.append(graph["surfaces"][i])
	return out


## Bottlenecks: surfaces whose removal disconnects other (normally
## reachable) surfaces from the ground — the "guard the only ladder" spots.
## Returns [{cut: surface, orphans: [surface...]}], worst first.
static func _find_bottlenecks(map: Dictionary) -> Array:
	var graph := _build_graph(map)
	var base := _bfs(graph)
	var out: Array = []
	for v in graph["surfaces"].size():
		if v == graph["ground"] or not base[v]:
			continue
		var without := _bfs(graph, v)
		var orphans: Array = []
		for i in graph["surfaces"].size():
			if i != v and base[i] and not without[i]:
				orphans.append(graph["surfaces"][i])
		if orphans.size() >= MIN_BOTTLENECK_ORPHANS:
			out.append({"cut": graph["surfaces"][v], "orphans": orphans})
	out.sort_custom(func(a, b): return a["orphans"].size() > b["orphans"].size())
	return out


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
	# Try the three nearest reachable anchors, not just one — a failed
	# repair means deletion, and deletions cascade (each one can orphan
	# more surfaces), so repair success is worth the extra attempts.
	var pool := reachable.duplicate()
	var c: Vector2 = surf["rect"].get_center()
	pool.sort_custom(func(a, b):
		return a["rect"].get_center().distance_to(c) < b["rect"].get_center().distance_to(c))
	for i in mini(3, pool.size()):
		if _try_connect(map, pool[i], surf, rng):
			return


static func _nearest(pool: Array, surf: Dictionary):
	var best = null
	var best_d := INF
	var c: Vector2 = surf["rect"].get_center()
	for r in pool:
		var d: float = r["rect"].get_center().distance_to(c)
		if d < best_d:
			best_d = d
			best = r
	return best


## Try to create a route anchor -> target: first a stepping platform
## halfway, then a spring on the anchor aimed at the target.
static func _try_connect(map: Dictionary, anchor: Dictionary, target: Dictionary, rng: SeededRng) -> bool:
	var anchor_rect: Rect2 = anchor["rect"]
	var target_rect: Rect2 = target["rect"]
	var blockers := _blockers(map)

	var mid := (anchor_rect.get_center() + target_rect.get_center()) / 2.0
	for attempt in 8:
		var w := 150.0
		var x := clampf(mid.x - w / 2.0 + rng.next_float(-120.0, 120.0),
			GameConfig.PLATFORM_GAP, GameConfig.MAP_WIDTH - w - GameConfig.PLATFORM_GAP)
		var y := clampf(mid.y + rng.next_float(-70.0, 70.0), 90.0, GameConfig.MAP_HEIGHT - 120.0)
		var rect := Rect2(x, y, w, 16.0)
		var collides := false
		for p in map["platforms"]:
			# Same horizontal gap rule as generation; vertical clearance stays
			# at 40 so repairs can still slot between layers.
			if _sweep_rect(p).grow_individual(GameConfig.PLATFORM_GAP, 40.0, GameConfig.PLATFORM_GAP, 40.0).intersects(rect):
				collides = true
				break
		if collides:
			continue
		# Repair steps are thru: landable, but they never block anyone
		# else's arcs — so one repair can't sabotage the next.
		var step := {"rect": rect, "type": "solid", "thru": true}
		map["platforms"].append(step)
		if _edge_ok(anchor, step, _blockers(map)) and _edge_ok(step, target, _blockers(map)):
			return true
		map["platforms"].erase(step)

	var rise := anchor_rect.position.y - target_rect.position.y
	# Spring pads need a flat footing — never aim one off a ramp.
	if rise > 0.0 and rise < spring_height() and not anchor.has("ramp"):
		var pad_x := clampf(target_rect.get_center().x, anchor_rect.position.x + 20.0, anchor_rect.position.x + anchor_rect.size.x - 20.0)
		var pad := {"type": "spring", "pos": Vector2(pad_x, anchor_rect.position.y - 7.0)}
		map["objects"].append(pad)
		if _spring_edge_ok(pad["pos"], anchor, target, blockers) and _spring_has_headroom(map, pad):
			return true
		map["objects"].erase(pad)
	return false


## Eliminate single-surface bottlenecks: for every cut vertex, give its
## orphans a second, independent route (or delete tiny orphan sets as the
## last resort) until the graph is 2-connected with respect to the ground.
static func _repair_bottlenecks(map: Dictionary, rng: SeededRng) -> void:
	# Nested cuts (ladders) unwind one per pass, so allow plenty; every pass
	# either adds a route or deletes the orphans, so progress is guaranteed,
	# but stall-detect anyway in case a repair has no effect.
	var prev_count := -1
	var stalls := 0
	for pass_i in 24:
		var bottlenecks := _find_bottlenecks(map)
		if bottlenecks.is_empty():
			return
		if bottlenecks.size() == prev_count:
			stalls += 1
			if stalls >= 3:
				# Force progress: delete the worst offender's orphans.
				for orphan in bottlenecks[0]["orphans"]:
					_delete_surface(map, orphan)
				stalls = 0
				continue
		else:
			stalls = 0
		prev_count = bottlenecks.size()
		var b: Dictionary = bottlenecks[0]
		var graph := _build_graph(map)
		var cut_idx: int = graph["surfaces"].find(b["cut"])
		var without := _bfs(graph, cut_idx)
		var anchors: Array = []
		for i in graph["surfaces"].size():
			if without[i]:
				anchors.append(graph["surfaces"][i])
		# Connect the lowest orphan from a surface that survives the cut.
		var orphans: Array = b["orphans"]
		orphans.sort_custom(func(x, y): return x["rect"].position.y > y["rect"].position.y)
		var connected := false
		for orphan in orphans:
			var anchor = _nearest(anchors, orphan)
			if anchor != null and _try_connect(map, anchor, orphan, rng):
				connected = true
				break
		if not connected:
			# Last resort: drop the orphaned surfaces entirely.
			for orphan in orphans:
				_delete_surface(map, orphan)


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
		if p.get("thru", false):
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


static func _launcher_has_target(map: Dictionary, obj: Dictionary) -> bool:
	var support = _support_under(map, obj["pos"], 20.0)
	if support == null:
		return false
	var blockers := _blockers(map)
	for s in _surfaces(map):
		if s == support:
			continue
		if _launcher_edge_ok(obj["pos"], obj["vel"], support, s, blockers):
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
	# The travel range must respect the border gap like any static platform.
	if sweep.position.x < GameConfig.PLATFORM_GAP \
			or sweep.end.x > GameConfig.MAP_WIDTH - GameConfig.PLATFORM_GAP:
		return true
	for p in map["platforms"]:
		if p == mover:
			continue
		# A pinch partner's sweep overlaps by design; counter-phase guarantees
		# they're never co-located, so don't treat the partner as a collision.
		if mover.get("move", {}).has("pinch") and p.get("move", {}).get("pinch", -999) == mover["move"]["pinch"]:
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
		elif obj["type"] == "launcher":
			ok = _support_under(map, obj["pos"], 20.0) != null and _launcher_has_target(map, obj)
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
		if r.size.x < 120.0 or s.has("move") or s.has("ramp"):
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
