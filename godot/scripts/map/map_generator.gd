class_name MapGenerator
## Seeded map generation 2.0: landmark-based zones instead of uniform
## platform soup. The map is split into columns; each gets a distinct
## structure (walled tower, overhung pocket, ice rink, spring yard) in the
## lower band, then reachability-checked connector platforms fill the air
## above. Same seed = same map on every client.
##
## Map data shape:
##   { "seed": String, "width": int, "height": int,
##     "platforms": [{ "rect": Rect2, "type": "solid"|"passthrough"|"ice"|"wall" }],
##     "objects":   [{ "type": "spring", "pos": Vector2 }],
##     "spawn_points": [Vector2] }

const MIN_PLATFORM_WIDTH := 120
const MAX_PLATFORM_WIDTH := 280
const PLATFORM_HEIGHT := 16.0
const GROUND_HEIGHT := 20.0
const WALL_WIDTH := 16.0
const PASSTHROUGH_CHANCE := 0.25
const ICE_CHANCE := 0.15
## Landmarks occupy the band between the ground and this height; connector
## platforms fill everything above it.
const LANDMARK_TOP := 640.0

const LANDMARKS := ["tower", "pocket", "ice_rink", "spring_yard"]


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

	var columns := order.size()
	var col_w := float(width) / float(columns)
	var landmark_boxes: Array[Rect2] = []
	for i in columns:
		var cx := col_w * (float(i) + 0.5) + rng.next_float(-40.0, 40.0)
		var built := _build_landmark(order[i], cx, ground_y, rng)
		for p in built["platforms"]:
			platforms.append(p)
			landmark_boxes.append(p["rect"].grow(30.0))
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
			var min_x := maxf(20.0, base_rect.position.x - max_horizontal)
			var max_x := minf(float(width) - p_width - 20.0,
				base_rect.position.x + base_rect.size.x + max_horizontal - p_width)
			if max_x < min_x:
				continue
			var x := float(rng.next_int(int(floor(min_x)), int(floor(max_x))))
			var rect := Rect2(x, y, p_width, PLATFORM_HEIGHT)

			var blocked := false
			for lp in layer_platforms:
				var lp_rect: Rect2 = lp["rect"]
				if x < lp_rect.position.x + lp_rect.size.x + 50.0 and x + p_width + 50.0 > lp_rect.position.x:
					blocked = true
					break
			if not blocked:
				for box in landmark_boxes:
					if box.intersects(rect):
						blocked = true
						break
			if blocked:
				continue

			var roll := rng.next()
			var p_type := "solid"
			if roll < ICE_CHANCE:
				p_type = "ice"
			elif roll < ICE_CHANCE + PASSTHROUGH_CHANCE:
				p_type = "passthrough"
			var platform := {"rect": rect, "type": p_type}
			platforms.append(platform)
			layer_platforms.append(platform)

		if layer_platforms.is_empty() and not previous_layer.is_empty():
			var base2: Dictionary = previous_layer[0]
			var base2_rect: Rect2 = base2["rect"]
			var w2 := float(MIN_PLATFORM_WIDTH)
			var x2 := maxf(20.0, minf(float(width) - w2 - 20.0,
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
		if p["type"] == "solid" and p["rect"].size.x >= 200.0 and p["rect"].position.y < ground_y - 100.0:
			spring_candidates.append(p)
	if not spring_candidates.is_empty():
		for i in rng.next_int(1, 2):
			var p: Dictionary = spring_candidates[rng.next_int(0, spring_candidates.size() - 1)]
			var rect: Rect2 = p["rect"]
			objects.append({"type": "spring", "pos": Vector2(
				rect.position.x + rect.size.x * rng.next_float(0.25, 0.75),
				rect.position.y - 7.0)})

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

	return {
		"seed": seed_string,
		"width": width,
		"height": height,
		"platforms": platforms,
		"objects": objects,
		"spawn_points": spawn_points,
	}


# --- landmark builders -----------------------------------------------------------

static func _build_landmark(kind: String, cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	match kind:
		"tower":
			return _tower(cx, rng)
		"pocket":
			return _pocket(cx, ground_y)
		"ice_rink":
			return _ice_rink(cx, rng)
		"spring_yard":
			return _spring_yard(cx, ground_y, rng)
	return {"platforms": [], "objects": []}


## A climbable tower with walls alternating sides between levels: straight
## horizontal runs are blocked, so chases have to weave.
static func _tower(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var w := 230.0
	var levels := [960.0, 860.0, 760.0, 660.0]
	for y in levels:
		plats.append({"rect": Rect2(cx - w / 2.0, y, w, PLATFORM_HEIGHT), "type": "solid"})
	for i in range(levels.size() - 1):
		var left := i % 2 == 0 if rng.next() < 0.5 else i % 2 == 1
		var wall_x := (cx - w / 2.0 - WALL_WIDTH) if left else (cx + w / 2.0)
		plats.append({
			"rect": Rect2(wall_x, levels[i + 1] + PLATFORM_HEIGHT, WALL_WIDTH,
				levels[i] - levels[i + 1] - PLATFORM_HEIGHT),
			"type": "wall",
		})
	return {"platforms": plats, "objects": []}


## An overhung room with low side entrances and a spring inside that fires
## you up through a passthrough section of the roof. Risky hiding spot with
## an escape hatch.
static func _pocket(cx: float, ground_y: float) -> Dictionary:
	var plats: Array[Dictionary] = []
	var roof_y := 880.0
	plats.append({"rect": Rect2(cx - 170.0, roof_y, 110.0, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx - 60.0, roof_y, 120.0, PLATFORM_HEIGHT), "type": "passthrough"})
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
	var w1 := rng.next_float(320.0, 400.0)
	var w2 := rng.next_float(240.0, 320.0)
	plats.append({"rect": Rect2(cx - w1 / 2.0, 940.0, w1, PLATFORM_HEIGHT), "type": "ice"})
	plats.append({"rect": Rect2(cx - w2 / 2.0 + rng.next_float(-60.0, 60.0), 820.0, w2, PLATFORM_HEIGHT), "type": "ice"})
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
		lines.append("%s %.0f,%.0f %dx%d" % [p["type"], r.position.x, r.position.y, int(r.size.x), int(r.size.y)])
	for o in map_data.get("objects", []):
		lines.append("%s %.0f,%.0f" % [o["type"], o["pos"].x, o["pos"].y])
	for s in map_data["spawn_points"]:
		lines.append("spawn %.0f,%.0f" % [s.x, s.y])
	return "\n".join(lines)
