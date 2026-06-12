class_name MapGenerator
## Seeded map generation, ported from the old lib/game/maps/MapGenerator.ts.
## Generates layered platforms bottom-to-top, each reachable from the layer
## below given the jump physics. Same seed = same map on every client.
##
## Map data shape:
##   { "seed": String, "width": int, "height": int,
##     "platforms": [{ "rect": Rect2, "type": "solid"|"passthrough" }],
##     "spawn_points": [Vector2] }

const MIN_PLATFORM_WIDTH := 120
const MAX_PLATFORM_WIDTH := 280
const PLATFORM_HEIGHT := 16.0
const GROUND_HEIGHT := 20.0
const PASSTHROUGH_CHANCE := 0.3


static func max_jump_height() -> float:
	var v := absf(GameConfig.JUMP_VELOCITY)
	return (v * v) / (2.0 * GameConfig.GRAVITY)


static func generate(seed_string: String) -> Dictionary:
	var rng := SeededRng.new(seed_string)
	var width := GameConfig.MAP_WIDTH
	var height := GameConfig.MAP_HEIGHT
	var vertical_spacing := int(floor(max_jump_height() * 0.8))

	var platforms: Array[Dictionary] = []
	var spawn_points: Array[Vector2] = []

	var ground := {
		"rect": Rect2(0, height - GROUND_HEIGHT, width, GROUND_HEIGHT),
		"type": "solid",
	}
	platforms.append(ground)

	var platforms_by_layer: Array = [[ground]]
	var num_layers := int(floor(float(height - 150) / float(vertical_spacing)))

	for layer in range(1, num_layers + 1):
		var layer_platforms: Array = []
		var y := height - GROUND_HEIGHT - float(layer * vertical_spacing)
		if y < 80.0:
			continue

		var count := rng.next_int(2, 4)
		var previous_layer: Array = platforms_by_layer[layer - 1] if layer - 1 < platforms_by_layer.size() else platforms_by_layer[0]

		for i in count:
			var p_width := float(rng.next_int(MIN_PLATFORM_WIDTH, MAX_PLATFORM_WIDTH))
			var base: Dictionary = previous_layer[rng.next_int(0, previous_layer.size() - 1)]
			var base_rect: Rect2 = base["rect"]

			# Horizontal reach while airborne for a full jump arc.
			var jump_time := 2.0 * absf(GameConfig.JUMP_VELOCITY) / GameConfig.GRAVITY
			var max_horizontal := GameConfig.PLAYER_SPEED * jump_time

			var min_x := maxf(20.0, base_rect.position.x - max_horizontal)
			var max_x := minf(
				float(width) - p_width - 20.0,
				base_rect.position.x + base_rect.size.x + max_horizontal - p_width
			)
			if max_x < min_x:
				continue

			var x := float(rng.next_int(int(floor(min_x)), int(floor(max_x))))

			var overlaps := false
			for lp in layer_platforms:
				var lp_rect: Rect2 = lp["rect"]
				if x < lp_rect.position.x + lp_rect.size.x + 50.0 and x + p_width + 50.0 > lp_rect.position.x:
					overlaps = true
					break
			if overlaps:
				continue

			var p_type := "passthrough" if rng.next() < PASSTHROUGH_CHANCE else "solid"
			var platform := {
				"rect": Rect2(x, y, p_width, PLATFORM_HEIGHT),
				"type": p_type,
			}
			platforms.append(platform)
			layer_platforms.append(platform)

		# Guarantee connectivity: at least one platform per layer.
		if layer_platforms.is_empty() and not previous_layer.is_empty():
			var base2: Dictionary = previous_layer[0]
			var base2_rect: Rect2 = base2["rect"]
			var w2 := float(MIN_PLATFORM_WIDTH)
			var x2 := maxf(20.0, minf(
				float(width) - w2 - 20.0,
				base2_rect.position.x + base2_rect.size.x / 2.0 - w2 / 2.0
			))
			var fallback := {
				"rect": Rect2(x2, y, w2, PLATFORM_HEIGHT),
				"type": "solid",
			}
			platforms.append(fallback)
			layer_platforms.append(fallback)

		platforms_by_layer.append(layer_platforms)

	# Spawn points: centered above the 4 lowest wide-enough platforms.
	# Sort with full tiebreakers so ordering never depends on sort stability.
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
		var rect: Rect2 = p["rect"]
		if rect.size.x >= float(MIN_PLATFORM_WIDTH):
			spawn_points.append(Vector2(
				rect.position.x + rect.size.x / 2.0,
				rect.position.y - GameConfig.PLAYER_SIZE
			))

	while spawn_points.size() < 2:
		spawn_points.append(Vector2(
			float(rng.next_int(100, width - 100)),
			float(height) - GROUND_HEIGHT - GameConfig.PLAYER_SIZE
		))

	return {
		"seed": seed_string,
		"width": width,
		"height": height,
		"platforms": platforms,
		"spawn_points": spawn_points,
	}


## Resolves a map from either a preset id ("arena", "towers") or a random seed.
static func from_seed_or_preset(seed_or_preset: String) -> Dictionary:
	if MapPresets.PRESETS.has(seed_or_preset):
		return MapPresets.get_preset(seed_or_preset)
	return generate(seed_or_preset)


## Debug helper used to verify cross-platform determinism (M1 check).
static func describe(map_data: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("seed=%s platforms=%d" % [map_data["seed"], map_data["platforms"].size()])
	for p in map_data["platforms"]:
		var r: Rect2 = p["rect"]
		lines.append("%s %.0f,%.0f %dx%d" % [p["type"], r.position.x, r.position.y, int(r.size.x), int(r.size.y)])
	for s in map_data["spawn_points"]:
		lines.append("spawn %.0f,%.0f" % [s.x, s.y])
	return "\n".join(lines)
