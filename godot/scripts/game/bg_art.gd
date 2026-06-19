class_name BgArt
## Procedural background art: flat, friendly silhouettes drawn into a CanvasItem.
## Draw opaque; the caller fades the whole layer via self_modulate for the
## "atmospheric silhouette" look. Shapes are unit (0..1) coords * size.

# Floating-island silhouette: smooth rock + grassy plateau (validated shape).
static var _ROCK := PackedVector2Array([
	Vector2(0.125,0.388), Vector2(0.09,0.55), Vector2(0.16,0.72), Vector2(0.30,0.86),
	Vector2(0.4625,0.9375), Vector2(0.62,0.86), Vector2(0.78,0.72), Vector2(0.85,0.55),
	Vector2(0.875,0.388)])
static var _GRASS := PackedVector2Array([
	Vector2(0.10,0.388), Vector2(0.10,0.30), Vector2(0.20,0.30), Vector2(0.40,0.275),
	Vector2(0.575,0.294), Vector2(0.76,0.31), Vector2(0.9125,0.3125), Vector2(0.975,0.35),
	Vector2(0.9375,0.40), Vector2(0.50,0.4375)])
# Tree
static var _TRUNK := PackedVector2Array([
	Vector2(0.53,0.325), Vector2(0.55,0.19), Vector2(0.60,0.19), Vector2(0.62,0.325)])
# Canopy clumps: Vector3(cx, cy, radius), all unit.
static var _CANOPY := [
	Vector3(0.469,0.1625,0.0875), Vector3(0.675,0.15,0.094),
	Vector3(0.575,0.081,0.109), Vector3(0.575,0.20,0.0875)]


static func _scaled(unit: PackedVector2Array, origin: Vector2, size: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in unit:
		out.append(origin + Vector2(p.x * size.x, p.y * size.y))
	return out


## Draw a floating island with a tree. `size` is the bounding box.
static func draw_island(ci: CanvasItem, origin: Vector2, size: Vector2,
		rock: Color, grass: Color, trunk: Color, leaf: Color) -> void:
	ci.draw_colored_polygon(_scaled(_ROCK, origin, size), rock)
	ci.draw_colored_polygon(_scaled(_GRASS, origin, size), grass)
	ci.draw_colored_polygon(_scaled(_TRUNK, origin, size), trunk)
	for c in _CANOPY:  # opaque, same color -> merges into one blob over the trunk
		ci.draw_circle(origin + Vector2(c.x * size.x, c.y * size.y), c.z * size.x, leaf)


## Geometry accessor for tests / reuse.
static func island_silhouette(size: Vector2) -> PackedVector2Array:
	return _scaled(_ROCK, Vector2.ZERO, size)


## A jagged snow-capped mountain ridge across [x0,x1] with `peaks` points.
## Returns nothing; draws ridge + caps + a rim-light line on the lit (left) side.
static func draw_mountain(ci: CanvasItem, x0: float, x1: float, base_y: float,
		min_h: float, max_h: float, rock: Color, cap: Color, rim: Color,
		rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(x0, base_y))
	var n := 5
	var caps := []
	for i in n + 1:
		var x := lerpf(x0, x1, float(i) / float(n))
		var y := base_y if i == 0 or i == n else base_y - rng.randf_range(min_h, max_h)
		pts.append(Vector2(x, y))
		if i != 0 and i != n:
			caps.append(Vector2(x, y))
	pts.append(Vector2(x1, base_y))
	ci.draw_colored_polygon(pts, rock)
	for peak in caps:  # small snow cap triangle
		var w := 14.0
		ci.draw_colored_polygon(PackedVector2Array([
			peak, peak + Vector2(-w, w * 1.4), peak + Vector2(w, w * 1.4)]), cap)
	# rim light: trace the lit side of each peak
	for i in range(1, pts.size() - 1):
		ci.draw_line(pts[i - 1], pts[i], rim, 2.0, true)


## A soft cloud: a cluster of radial-gradient blobs (soft edges via the texture).
static func draw_cloud(ci: CanvasItem, center: Vector2, scale := 1.0,
		color := Color(1, 1, 1, 0.9), tex: Texture2D = null) -> void:
	if tex == null: return
	var blobs := [Vector2(-40, 6), Vector2(0, -10), Vector2(34, 8), Vector2(-12, 12)]
	var sizes := [70.0, 95.0, 66.0, 54.0]
	for i in blobs.size():
		var d: float = sizes[i] * scale
		ci.draw_texture_rect(tex, Rect2(center + blobs[i] * scale - Vector2(d, d) / 2, Vector2(d, d)), false, color)
