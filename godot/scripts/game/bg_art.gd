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


