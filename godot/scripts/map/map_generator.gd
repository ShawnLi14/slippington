class_name MapGenerator
## Seeded map generation 2.0: landmark-based zones instead of uniform
## platform soup. The map is split into columns; each gets a distinct
## structure (walled tower, overhung pocket, ice rink, spring yard) in the
## lower band, then reachability-checked connector platforms fill the air
## above. Same seed = same map on every client.
##
## Map data shape:
##   { "seed": String, "width": int, "height": int,
##     "platforms": [{ "rect": Rect2, "type": "solid"|"ice"|"wall",
##                     "thru": bool }],   # thru = one-way variant of the
##                                        # material: pass up through it,
##                                        # land on top (drawn transparent)
##     "objects":   [{ "type": "spring", "pos": Vector2 }],
##     "spawn_points": [Vector2] }

const MIN_PLATFORM_WIDTH := 180
const MAX_PLATFORM_WIDTH := 280
const PLATFORM_HEIGHT := 16.0
const GROUND_HEIGHT := 20.0
const WALL_WIDTH := 16.0
const PASSTHROUGH_CHANCE := 0.25
const ICE_CHANCE := 0.15
## Connector platforms: chance to be a slope instead of a flat, and chance
## for a flat to grow a bent ramp off one end (an L-shape).
const RAMP_CHANCE := 0.16
const BEND_CHANCE := 0.18
## Chance a flat solid connector becomes a conveyor belt.
const CONVEYOR_CHANCE := 0.28
## Chance a thru connector becomes a clocked phase platform instead.
const PHASE_CHANCE := 0.65
## Chance a placed spring is re-aimed as an angled launcher instead.
const LAUNCHER_CHANCE := 0.45
## Chance a still-spring pad becomes an updraft column instead.
const UPDRAFT_CHANCE := 0.30
## Landmarks occupy the band between the ground and this height; connector
## platforms fill everything above it.
const LANDMARK_TOP := 640.0

## Five landmark kinds, four columns: each map shuffles the pool and takes
## the first four, so every map is missing a different one.
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft"]

## Debug/test hook: when true, generate() returns the raw map without the
## planner's validation/repair pass.
static var skip_plan := false

## Debug/test hook: pin this landmark kind into column 0 (and exclude it from
## the random tail). "" = normal shuffle. Used by unit tests and screenshots.
static var force_landmark := ""

## Widest half-extent of each landmark's platforms, used to keep the whole
## structure GameConfig.PLATFORM_GAP clear of the map border and of the
## neighboring column's landmark. The worst four of these plus five gaps
## must total under the map width.
const LANDMARK_HALF := {
	"scaffold": 170.0,     # 220/2 + 50 zigzag offset + 10 jitter
	"pocket": 170.0,
	"ice_rink": 190.0,     # second slab: w2/2 (150) + 40 placement jitter
	"spring_yard": 100.0,
	"mast": 140.0,         # crow's nest 280 wide
	"mill": 150.0,         # 200 belt /2 + 35 offset + 8 jitter
	"shaft": 120.0,        # side ledges reach cx±118
}


static func max_jump_height() -> float:
	var v := absf(GameConfig.JUMP_VELOCITY)
	return (v * v) / (2.0 * GameConfig.GRAVITY)


static func generate(seed_string: String) -> Dictionary:
	var rng := SeededRng.new(seed_string)
	var width := GameConfig.MAP_WIDTH
	var height := GameConfig.MAP_HEIGHT
	var ground_y := float(height) - GROUND_HEIGHT

	var platforms: Array[Dictionary] = []
	var objects: Array[Dictionary] = []
	var spawn_points: Array[Vector2] = []

	var ground := {"rect": Rect2(0, ground_y, width, GROUND_HEIGHT), "type": "solid"}
	platforms.append(ground)

	# --- landmarks: one per column, shuffled deterministically -------------
	var order := LANDMARKS.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.next_int(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp

	if force_landmark != "" and LANDMARKS.has(force_landmark):
		order.erase(force_landmark)
		order.push_front(force_landmark)

	var columns := 4  # pool has 5 kinds; the first 4 of the shuffle play
	var col_w := float(width) / float(columns)
	var gap := GameConfig.PLATFORM_GAP
	var landmark_boxes: Array[Rect2] = []
	var landmark_extents: Array[Vector2] = []  # x ranges, for the low patrol
	# Greedy left-to-right: each landmark sits near its column center, pushed
	# clear of the border and of its left neighbor by a full gap, while
	# reserving room on the right for the columns still to come (so the
	# bounds can never invert — the worst four landmark widths + 5 gaps
	# stay under the 1920 map width).
	var prev_right := 0.0
	for i in columns:
		var half: float = LANDMARK_HALF[order[i]]
		var reserve := 0.0
		for j in range(i + 1, columns):
			reserve += 2.0 * LANDMARK_HALF[order[j]] + gap
		var lo := maxf(gap + half, prev_right + gap + half)
		var hi := float(width) - gap - half - reserve
		var cx := clampf(col_w * (float(i) + 0.5) + rng.next_float(-40.0, 40.0), lo, hi)
		prev_right = cx + half
		landmark_extents.append(Vector2(cx - half, cx + half))
		var built := _build_landmark(order[i], cx, ground_y, rng)
		for p in built["platforms"]:
			platforms.append(p)
			landmark_boxes.append(p["rect"].grow_individual(gap, 30.0, gap, 30.0))
		for o in built["objects"]:
			objects.append(o)

	# --- connector platforms above the landmark band -----------------------
	var vertical_spacing := int(floor(max_jump_height() * 0.8))
	# Reachability seeds: ground + the top platform of each landmark.
	var previous_layer: Array = [ground]
	for p in platforms:
		if p["type"] != "wall" and p["rect"].position.y <= LANDMARK_TOP + 120.0:
			previous_layer.append(p)

	var y := LANDMARK_TOP
	while y >= 80.0:
		var layer_platforms: Array = []
		var count := rng.next_int(2, 4)
		for i in count:
			var p_width := float(rng.next_int(MIN_PLATFORM_WIDTH, MAX_PLATFORM_WIDTH))
			var base: Dictionary = previous_layer[rng.next_int(0, previous_layer.size() - 1)]
			var base_rect: Rect2 = base["rect"]
			var jump_time := 2.0 * absf(GameConfig.JUMP_VELOCITY) / GameConfig.GRAVITY
			var max_horizontal := GameConfig.PLAYER_SPEED * jump_time
			var min_x := maxf(gap, base_rect.position.x - max_horizontal)
			var max_x := minf(float(width) - p_width - gap,
				base_rect.position.x + base_rect.size.x + max_horizontal - p_width)
			if max_x < min_x:
				continue
			var x := float(rng.next_int(int(floor(min_x)), int(floor(max_x))))
			var rect := Rect2(x, y, p_width, PLATFORM_HEIGHT)

			var blocked := false
			for lp in layer_platforms:
				var lp_rect: Rect2 = lp["rect"]
				if x < lp_rect.position.x + lp_rect.size.x + gap and x + p_width + gap > lp_rect.position.x:
					blocked = true
					break
			if not blocked:
				for box in landmark_boxes:
					if box.intersects(rect):
						blocked = true
						break
			if blocked:
				continue

			# Material and thru-ness roll independently: any material can
			# come in its one-way "transparent" variant (yes, thru ice).
			var p_type := "ice" if rng.next() < ICE_CHANCE else "solid"
			var thru := rng.next() < PASSTHROUGH_CHANCE
			var platform: Dictionary
			if rng.next() < RAMP_CHANCE:
				# An angled slab instead of a flat: same 16px-thick platform,
				# tilted slightly (rect height = rise + thickness). Never thru.
				var r_rise := rng.next_float(24.0, 56.0)
				var r_dir := 1 if rng.next() < 0.5 else -1
				platform = {"rect": Rect2(x, y, p_width, r_rise + PLATFORM_HEIGHT), "type": p_type, "ramp": r_dir}
			else:
				platform = {"rect": rect, "type": p_type, "thru": thru}
				if thru and rng.next() < PHASE_CHANCE:
					platform = {"rect": rect, "type": p_type,
						"phase": {"period": rng.next_float(1.6, 2.6), "duty": rng.next_float(0.45, 0.6), "offset": rng.next_float(0.0, 2.0)}}
			platforms.append(platform)
			layer_platforms.append(platform)

			# Salt a conveyor onto eligible flats (solid, non-thru, non-ramp, non-phase).
			if not platform.has("ramp") and not platform.get("thru", false) \
					and not platform.has("phase") \
					and platform["type"] == "solid" and rng.next() < CONVEYOR_CHANCE:
				platform["conveyor"] = {
					"dir": 1 if rng.next() < 0.5 else -1,
					"speed": rng.next_float(90.0, 150.0),
				}

			# Bent end: a flat can grow a ramp off one side (an L-shape), if
			# it stays inside the border gap and clear of everything else.
			if not platform.has("ramp") and not thru and rng.next() < BEND_CHANCE:
				var b_run := rng.next_float(90.0, 120.0)
				var b_rise := rng.next_float(30.0, 50.0)
				var b_left := rng.next() < 0.5
				# Slab rect includes the 16px thickness; the low corner's walk
				# surface sits flush with the flat's top.
				var b_rect := Rect2(x - b_run, y - b_rise, b_run, b_rise + PLATFORM_HEIGHT) if b_left \
						else Rect2(x + p_width, y - b_rise, b_run, b_rise + PLATFORM_HEIGHT)
				var bend_ok := b_rect.position.x >= gap and b_rect.end.x <= float(width) - gap
				if bend_ok:
					for lp in layer_platforms:
						if lp == platform:
							continue
						var lp_rect: Rect2 = lp["rect"]
						if b_rect.position.x < lp_rect.end.x + gap and b_rect.end.x + gap > lp_rect.position.x:
							bend_ok = false
							break
				if bend_ok:
					for box in landmark_boxes:
						if box.intersects(b_rect):
							bend_ok = false
							break
				if bend_ok:
					var bend := {"rect": b_rect, "type": p_type, "ramp": -1 if b_left else 1}
					platforms.append(bend)
					layer_platforms.append(bend)

		if layer_platforms.is_empty() and not previous_layer.is_empty():
			var base2: Dictionary = previous_layer[0]
			var base2_rect: Rect2 = base2["rect"]
			var w2 := float(MIN_PLATFORM_WIDTH)
			var x2 := maxf(gap, minf(float(width) - w2 - gap,
				base2_rect.position.x + base2_rect.size.x / 2.0 - w2 / 2.0))
			var fallback := {"rect": Rect2(x2, y, w2, PLATFORM_HEIGHT), "type": "solid"}
			platforms.append(fallback)
			layer_platforms.append(fallback)

		previous_layer = layer_platforms
		y -= float(vertical_spacing)

	# A couple of extra springs on wide high platforms keep the upper map in
	# play even outside the spring yard.
	var spring_candidates: Array = []
	for p in platforms:
		if p["type"] == "solid" and not p.get("thru", false) and not p.has("ramp") and p["rect"].size.x >= 200.0 and p["rect"].position.y < ground_y - 100.0:
			spring_candidates.append(p)
	if not spring_candidates.is_empty():
		for i in rng.next_int(1, 2):
			var p: Dictionary = spring_candidates[rng.next_int(0, spring_candidates.size() - 1)]
			var rect: Rect2 = p["rect"]
			objects.append({"type": "spring", "pos": Vector2(
				rect.position.x + rect.size.x * rng.next_float(0.25, 0.75),
				rect.position.y - 7.0)})

	# One LOW patrol over open ground between landmarks: a mover anyone can
	# board with a plain jump. (The connector-layer candidates below all
	# live in the upper half — the mid-map band is crowded by landmark
	# tops, so without this every mover ends up in the sky.)
	var low_cursor := gap
	var ground_intervals: Array[Vector2] = []
	for ext in landmark_extents:
		if ext.x - gap - low_cursor >= 280.0:
			ground_intervals.append(Vector2(low_cursor, ext.x - gap))
		low_cursor = ext.y + gap
	if float(width) - gap - low_cursor >= 280.0:
		ground_intervals.append(Vector2(low_cursor, float(width) - gap))
	var low_mover_placed := false
	if not ground_intervals.is_empty():
		var iv: Vector2 = ground_intervals[rng.next_int(0, ground_intervals.size() - 1)]
		var w_low := 180.0
		var low_amp := minf(160.0, (iv.y - iv.x - w_low) / 2.0)
		var low_cx := (iv.x + iv.y) / 2.0
		platforms.append({
			"rect": Rect2(low_cx - w_low / 2.0, rng.next_float(940.0, 985.0), w_low, PLATFORM_HEIGHT),
			"type": "solid",
			"move": {"axis": "x", "amplitude": low_amp, "period": rng.next_float(6.0, 9.0), "phase": rng.next_float(0.0, 1.0)},
		})
		low_mover_placed = true

	# A pinch gate: two counter-phase movers that meet and part — a closing gap
	# to thread on the beat. Scan the connector layer (y ≈ 700) for a clear
	# horizontal span — connectors are sparse enough that a 400 px gap nearly
	# always exists.  The pair is non-blocking (Task 2) so it can't sever
	# ground routes; the sweep exemption (above) lets pinch partners co-exist
	# without the planner stripping them.
	var pinch_y := rng.next_float(680.0, 760.0)
	var pw := 120.0
	var pinch_band_used: Array[Vector2] = []
	for p in platforms:
		var pr: Rect2 = p["rect"]
		if pr.position.y < pinch_y + 80.0 and pr.end.y > pinch_y - 80.0:
			pinch_band_used.append(Vector2(pr.position.x - 20.0, pr.end.x + 20.0))
	pinch_band_used.sort_custom(func(a, b): return a.x < b.x)
	var pinch_intervals: Array[Vector2] = []
	var pstart := gap
	for seg in pinch_band_used:
		if seg.x - pstart >= 400.0:
			pinch_intervals.append(Vector2(pstart, seg.x))
		pstart = maxf(pstart, seg.y)
	if float(width) - gap - pstart >= 400.0:
		pinch_intervals.append(Vector2(pstart, float(width) - gap))
	if not pinch_intervals.is_empty() and rng.next() < 0.85:
		var pv: Vector2 = pinch_intervals[rng.next_int(0, pinch_intervals.size() - 1)]
		var mid := (pv.x + pv.y) / 2.0
		var amp := minf(150.0, (pv.y - pv.x) / 2.0 - pw - 20.0)
		var per := rng.next_float(2.6, 3.4)
		platforms.append({"rect": Rect2(mid - pw - 30.0, pinch_y, pw, PLATFORM_HEIGHT), "type": "solid",
			"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.0, "pinch": int(mid)}})
		platforms.append({"rect": Rect2(mid + 30.0, pinch_y, pw, PLATFORM_HEIGHT), "type": "solid",
			"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.5, "pinch": int(mid)}})

	# Moving platforms: 2-3 guaranteed per map, preferring the lowest viable
	# layers (the lowest-first draw below) but allowed to fall back upward —
	# high patrols still add traversal value. The floor just keeps
	# them off the literal top edge. Amplitude is clamped to the border gap
	# up front instead of relying on the planner to strip violators.
	# (Historical note: a y>=420 hard ceiling lived here briefly — it was
	# chasing what turned out to be the sync_to_physics origin-render bug.)
	var mover_candidates: Array = []
	for p in platforms:
		var rect: Rect2 = p["rect"]
		# thru platforms make fine movers (one-way patrols are a platformer
		# classic, and their sweep doesn't block anyone's arcs); ramps and
		# ice stay static.
		if p["type"] != "solid" or p.has("move") or p.has("ramp") \
				or rect.size.x < 140.0 or rect.size.x > 280.0 \
				or rect.position.y < 240.0 or rect.position.y > LANDMARK_TOP:
			continue
		# Connectors only — landmark pieces (e.g. the mast's crow's nest)
		# must not wander off their structure.
		var in_landmark := false
		for box in landmark_boxes:
			if box.intersects(rect):
				in_landmark = true
				break
		if not in_landmark:
			mover_candidates.append(p)
	# Strictly lowest-first: a patrol high in the sky is hard to use; one
	# near the mid-map routes real chases. Higher candidates only come up
	# when lower ones are discarded.
	mover_candidates.sort_custom(func(a, b): return a["rect"].position.y > b["rect"].position.y)
	# Keep drawing until the target is met — a candidate too hemmed in to
	# patrol (clamped amplitude under 60) or one whose sweep would break a
	# route is discarded, not counted.
	var mover_target := rng.next_int(3, 4) - (1 if low_mover_placed else 0)
	var movers_assigned := 0
	while movers_assigned < mover_target and not mover_candidates.is_empty():
		var p: Dictionary = mover_candidates.pop_front()
		var rect: Rect2 = p["rect"]
		var max_amp := minf(rect.position.x - GameConfig.PLATFORM_GAP,
			float(width) - GameConfig.PLATFORM_GAP - rect.end.x)
		# Also clear of same-layer neighbors across the whole patrol, so the
		# planner doesn't have to strip the mover afterwards.
		for q in platforms:
			if q == p:
				continue
			var qr: Rect2 = q["rect"]
			if absf(qr.position.y - rect.position.y) > 60.0:
				continue
			if qr.end.x <= rect.position.x:
				max_amp = minf(max_amp, rect.position.x - qr.end.x - 12.0)
			elif qr.position.x >= rect.end.x:
				max_amp = minf(max_amp, qr.position.x - rect.end.x - 12.0)
		if max_amp < 50.0:
			continue
		# Vertical clearance: nearest platform above/below within this column.
		var v_amp := minf(rect.position.y - 120.0, LANDMARK_TOP - rect.end.y)
		for q in platforms:
			if q == p:
				continue
			var qr2: Rect2 = q["rect"]
			if qr2.end.x <= rect.position.x or qr2.position.x >= rect.end.x:
				continue  # not in this column
			if qr2.end.y <= rect.position.y:
				v_amp = minf(v_amp, rect.position.y - qr2.end.y - 12.0)
			elif qr2.position.y >= rect.end.y:
				v_amp = minf(v_amp, qr2.position.y - rect.end.y - 12.0)
		var go_vertical := v_amp >= 60.0 and rng.next() < 0.8
		# A patrol (x or y) widens this platform's blocker footprint to its whole
		# sweep, which can sever jump arcs that route past it. Only keep the mover
		# if the map stays exactly as reachable as before.
		var probe := {"width": width, "height": height, "platforms": platforms, "objects": objects}
		var base_unreachable: int = MapPlanner._unreachable_surfaces(probe).size()
		if go_vertical:
			p["move"] = {
				"axis": "y",
				"amplitude": minf(rng.next_float(70.0, 130.0), v_amp),
				"period": rng.next_float(5.0, 8.0),
				"phase": rng.next_float(0.0, 1.0),
			}
		else:
			p["move"] = {
				"axis": "x",
				"amplitude": minf(rng.next_float(110.0, 180.0), max_amp),
				"period": rng.next_float(6.0, 9.0),
				"phase": rng.next_float(0.0, 1.0),
			}
		if MapPlanner._unreachable_surfaces(probe).size() > base_unreachable:
			p.erase("move")
			continue
		movers_assigned += 1

	# A portal pair linking the far-left floor to a high perch on the right
	# half (or vice versa) — the cross-map escape hatch.
	var flip := rng.next() < 0.5
	var high_candidates: Array = []
	for p in platforms:
		var rect: Rect2 = p["rect"]
		var on_far_half := rect.position.x > width * 0.55 if not flip else rect.position.x + rect.size.x < width * 0.45
		if p["type"] == "solid" and not p.get("thru", false) and not p.has("move") and not p.has("ramp") and rect.size.x >= 120.0 \
				and rect.position.y < 500.0 and on_far_half:
			high_candidates.append(p)
	if not high_candidates.is_empty():
		var perch: Rect2 = high_candidates[rng.next_int(0, high_candidates.size() - 1)]["rect"]
		var floor_x := 70.0 if not flip else float(width) - 70.0
		objects.append({"type": "portal", "pos": Vector2(floor_x, ground_y - 36.0),
			"dest": Vector2(perch.position.x + perch.size.x / 2.0, perch.position.y - 40.0)})
		objects.append({"type": "portal", "pos": Vector2(perch.position.x + perch.size.x / 2.0, perch.position.y - 36.0),
			"dest": Vector2(floor_x, ground_y - 40.0)})

	# --- spawn points (lowest wide platforms, ground guaranteed) ------------
	var sorted := platforms.duplicate()
	sorted.sort_custom(func(a, b):
		var ra: Rect2 = a["rect"]
		var rb: Rect2 = b["rect"]
		if ra.position.y != rb.position.y:
			return ra.position.y > rb.position.y
		if ra.position.x != rb.position.x:
			return ra.position.x < rb.position.x
		return ra.size.x < rb.size.x
	)
	for p in sorted:
		if spawn_points.size() >= 4:
			break
		if p["type"] == "wall":
			continue
		var rect: Rect2 = p["rect"]
		if rect.size.x >= float(MIN_PLATFORM_WIDTH):
			spawn_points.append(Vector2(
				rect.position.x + rect.size.x / 2.0,
				rect.position.y - GameConfig.PLAYER_SIZE))
	while spawn_points.size() < 2:
		spawn_points.append(Vector2(
			float(rng.next_int(100, width - 100)),
			ground_y - GameConfig.PLAYER_SIZE))

	var map := {
		"seed": seed_string,
		"width": width,
		"height": height,
		"platforms": platforms,
		"objects": objects,
		"spawn_points": spawn_points,
	}
	# Re-aim a fraction of springs as angled launchers (up-and-sideways). The
	# planner's _scrub_objects DROPS any launcher whose arc has no valid target
	# (the source spring is then gone, but plan()'s repair pass re-routes, so the
	# map always stays sound — a conversion can never make a map unreachable).
	# A pad that did NOT become a launcher may become an updraft column instead
	# (mutually exclusive, deterministic: launcher roll consumed first).
	for o in map["objects"]:
		if o["type"] != "spring":
			continue
		if rng.next() < LAUNCHER_CHANCE:
			var dir := 1.0 if rng.next() < 0.5 else -1.0
			o["type"] = "launcher"
			o["vel"] = Vector2(dir * rng.next_float(180.0, 280.0), -rng.next_float(640.0, 740.0))
		elif rng.next() < UPDRAFT_CHANCE:
			# A column rising from just above the pad's footing up ~spring height.
			var updraft_w := 96.0
			var updraft_h := minf(320.0, MapPlanner.spring_height() * 0.7)
			var pad_pos: Vector2 = o["pos"]
			o["type"] = "updraft"
			o["rect"] = Rect2(pad_pos.x - updraft_w / 2.0, pad_pos.y - updraft_h, updraft_w, updraft_h)
			o["accel"] = 1400.0
			o.erase("pos")
	# Post-pass: traversal-graph validation and deterministic repair —
	# everything must actually be reachable with real jump physics.
	if skip_plan:
		return map  # debug/tests: inspect the raw map before repairs
	return MapPlanner.plan(map, rng)


# --- landmark builders -----------------------------------------------------------

static func _build_landmark(kind: String, cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	match kind:
		"scaffold":
			return _scaffold(cx, rng)
		"pocket":
			return _pocket(cx, ground_y)
		"ice_rink":
			return _ice_rink(cx, rng)
		"spring_yard":
			return _spring_yard(cx, ground_y, rng)
		"mast":
			return _mast(cx, ground_y, rng)
		"mill":
			return _mill(cx, rng)
		"shaft":
			return _shaft(cx, rng)
	return {"platforms": [], "objects": []}


## A zigzag scaffold: stacked platforms with alternating horizontal offsets.
## Every floor below the crown is passthrough — you can drop OR jump through
## it, so nothing inside can corner you (the old walled tower turned each
## shelf into a dead-end cubby). Chases here are vertical mixups: fake the
## drop, take the jump. Only the solid crown demands an edge approach.
static func _scaffold(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var w := 220.0
	var levels := [960.0, 860.0, 760.0, 660.0]
	var side := 1.0 if rng.next() < 0.5 else -1.0
	for i in levels.size():
		var off := side * (50.0 if i % 2 == 0 else -50.0) + rng.next_float(-10.0, 10.0)
		var thru := i != levels.size() - 1  # all floors but the crown
		plats.append({"rect": Rect2(cx + off - w / 2.0, levels[i], w, PLATFORM_HEIGHT), "type": "solid", "thru": thru})
	return {"platforms": plats, "objects": []}


## An overhung room with low side entrances and a spring inside that fires
## you up through a passthrough section of the roof. Risky hiding spot with
## an escape hatch.
static func _pocket(cx: float, ground_y: float) -> Dictionary:
	var plats: Array[Dictionary] = []
	var roof_y := 880.0
	plats.append({"rect": Rect2(cx - 170.0, roof_y, 110.0, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx - 60.0, roof_y, 120.0, PLATFORM_HEIGHT), "type": "solid", "thru": true})
	plats.append({"rect": Rect2(cx + 60.0, roof_y, 110.0, PLATFORM_HEIGHT), "type": "solid"})
	var wall_top := roof_y + PLATFORM_HEIGHT
	var wall_h := ground_y - 64.0 - wall_top  # 64px entrance gaps at the floor
	plats.append({"rect": Rect2(cx - 170.0, wall_top, WALL_WIDTH, wall_h), "type": "wall"})
	plats.append({"rect": Rect2(cx + 170.0 - WALL_WIDTH, wall_top, WALL_WIDTH, wall_h), "type": "wall"})
	var objects: Array[Dictionary] = [
		{"type": "spring", "pos": Vector2(cx, ground_y - 7.0)},
	]
	return {"platforms": plats, "objects": objects}


## Wide slippery platforms: cornering here is a commitment.
static func _ice_rink(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	# Widths/jitter capped so the rink fits its LANDMARK_HALF (190) budget.
	var w1 := rng.next_float(300.0, 360.0)
	var w2 := rng.next_float(240.0, 300.0)
	plats.append({"rect": Rect2(cx - w1 / 2.0, 940.0, w1, PLATFORM_HEIGHT), "type": "ice"})
	plats.append({"rect": Rect2(cx - w2 / 2.0 + rng.next_float(-40.0, 40.0), 820.0, w2, PLATFORM_HEIGHT), "type": "ice"})
	return {"platforms": plats, "objects": []}


## A mast: one tall spine wall with rungs crossing it — two parallel
## ladders sharing a divider. The sides connect under the spine's base and
## over the crow's nest at the top; mid-climb the spine blocks horizontal
## moves, so the juke is the feint: start up one side, drop through a thru
## rung, slip under the base, climb the other.
static func _mast(cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var top_y := 560.0
	# Spine stops 64px short of the ground (like pocket doorways) so the
	# floor stays runnable and the two sides connect at the base.
	plats.append({"rect": Rect2(cx - WALL_WIDTH / 2.0, top_y, WALL_WIDTH, ground_y - 64.0 - top_y), "type": "wall"})
	var w := 260.0
	for y in [960.0, 860.0, 760.0, 660.0]:
		var thru := rng.next() < 0.4
		plats.append({"rect": Rect2(cx - w / 2.0, y, w, PLATFORM_HEIGHT), "type": "solid", "thru": thru})
	# Crow's nest across the spine top joins the two sides.
	plats.append({"rect": Rect2(cx - 140.0, top_y - PLATFORM_HEIGHT, 280.0, PLATFORM_HEIGHT), "type": "solid"})
	return {"platforms": plats, "objects": []}


## Open ground with launch pads: instant vertical exits from any chase.
static func _spring_yard(cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = [
		{"rect": Rect2(cx - 100.0, 950.0, 200.0, PLATFORM_HEIGHT), "type": "solid"},
	]
	var objects: Array[Dictionary] = [
		{"type": "spring", "pos": Vector2(cx - 160.0 + rng.next_float(-30.0, 30.0), ground_y - 7.0)},
		{"type": "spring", "pos": Vector2(cx + rng.next_float(-40.0, 40.0), 943.0)},
	]
	return {"platforms": plats, "objects": objects}


## Stacked conveyor belts running alternate directions: the juke is the
## counter-belt — lure the chaser onto a belt dragging them the wrong way
## while you ride yours. Open stack with horizontal offsets (no walls), so
## nothing corners you; every level is a jump apart.
static func _mill(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var w := 200.0
	var levels := [960.0, 860.0, 760.0, 660.0]
	var side := 1.0 if rng.next() < 0.5 else -1.0
	for i in levels.size():
		var off := side * (35.0 if i % 2 == 0 else -35.0) + rng.next_float(-8.0, 8.0)
		plats.append({
			"rect": Rect2(cx + off - w / 2.0, levels[i], w, PLATFORM_HEIGHT),
			"type": "solid",
			"conveyor": {"dir": 1 if i % 2 == 0 else -1, "speed": rng.next_float(110.0, 150.0)},
		})
	return {"platforms": plats, "objects": []}


## A narrow vertical channel: static side ledges staggered L/R (each a jump
## apart, so the climb never depends on the lift) plus a y-mover elevator
## bobbing the center as the express route. The juke is committing to the
## lift — a mistimed chaser eats a beat.
static func _shaft(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var lw := 70.0
	# Staggered side ledges: left, right, left, right — 85-90 px steps.
	plats.append({"rect": Rect2(cx - 118.0, 945.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx + 48.0, 855.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx - 118.0, 760.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx + 48.0, 668.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	# Center elevator: y-axis mover, amplitude clamped so the sweep stays in the
	# channel; 12 px clear of the ledges (ledges start at cx±48, ew/2 = 36).
	var ew := 72.0
	plats.append({
		"rect": Rect2(cx - ew / 2.0, 815.0, ew, PLATFORM_HEIGHT),
		"type": "solid",
		"move": {"axis": "y", "amplitude": 110.0, "period": rng.next_float(2.8, 3.6), "phase": rng.next_float(0.0, 1.0)},
	})
	return {"platforms": plats, "objects": []}


## Resolves a map from either a preset id ("arena", "towers") or a random seed.
static func from_seed_or_preset(seed_or_preset: String) -> Dictionary:
	if MapPresets.PRESETS.has(seed_or_preset):
		return MapPresets.get_preset(seed_or_preset)
	return generate(seed_or_preset)


## Debug helper used to verify cross-platform determinism (M1 check).
static func describe(map_data: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("seed=%s platforms=%d objects=%d" % [
		map_data["seed"], map_data["platforms"].size(), map_data.get("objects", []).size()])
	for p in map_data["platforms"]:
		var r: Rect2 = p["rect"]
		var marks := ""
		if p.get("thru", false):
			marks += "~thru"
		if p.has("ramp"):
			marks += "~ramp%+d" % p["ramp"]
		var line := "%s%s %.0f,%.0f %dx%d" % [p["type"], marks, r.position.x, r.position.y, int(r.size.x), int(r.size.y)]
		if p.has("move"):
			line += " move(%s a=%.0f T=%.1f ph=%.2f)" % [p["move"]["axis"], p["move"]["amplitude"], p["move"]["period"], p["move"]["phase"]]
		lines.append(line)
	for o in map_data.get("objects", []):
		var line := "%s %.0f,%.0f" % [o["type"], o["pos"].x, o["pos"].y]
		if o.has("dest"):
			line += " -> %.0f,%.0f" % [o["dest"].x, o["dest"].y]
		lines.append(line)
	for s in map_data["spawn_points"]:
		lines.append("spawn %.0f,%.0f" % [s.x, s.y])
	return "\n".join(lines)
