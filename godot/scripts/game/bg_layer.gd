class_name BgLayer
extends Node2D
## A data-driven painter for one depth layer of the background. Holds a list of
## shape "elements" (mountain / island / cloud) and draws them. If scroll_speed
## is non-zero it drifts them left and wraps, giving slow motion without a
## scrolling camera (the play area is exactly one screen).
##
## Clouds and islands are composed multi-tone flat-design shapes; each element
## carries a "seed" so its silhouette detail is generated once (lazily) and
## stays stable while it drifts.

var elements: Array = []
var scroll_speed := 0.0          # px/sec; 0 = static
var wrap_left := -350.0          # x at which an element wraps back to the right
var wrap_span := 0.0             # distance to jump when wrapping


func _process(delta: float) -> void:
	if scroll_speed == 0.0:
		return
	for e in elements:
		e["x"] -= scroll_speed * delta
		if e["x"] < wrap_left:
			e["x"] += wrap_span
	queue_redraw()


func _draw() -> void:
	for e in elements:
		match e["type"]:
			"mountain":
				_draw_mountain(e)
			"island":
				_draw_island(e)
			"cloud":
				_draw_cloud(e)


func _draw_mountain(e: Dictionary) -> void:
	var x: float = e["x"]
	var base_y: float = e["base_y"]
	var w: float = e["w"]
	var h: float = e["h"]
	var peak := Vector2(x + w * 0.5, base_y - h)
	var left := Vector2(x, base_y)
	var right := Vector2(x + w, base_y)
	draw_colored_polygon(PackedVector2Array([left, peak, right]), e["color"])
	if e.has("cap_color"):
		var f := 0.24  # snow cap covers the top quarter
		draw_colored_polygon(PackedVector2Array([
			peak, peak.lerp(left, f), peak.lerp(right, f),
		]), e["cap_color"])
	if e.has("rim_color"):
		draw_line(left, peak, e["rim_color"], 2.0, true)


# --- clouds ---------------------------------------------------------------------

## Puff layout template: offsets/radii in unit space, composed per cloud with
## seeded variation so no two clouds are identical.
func _ensure_cloud_detail(e: Dictionary) -> void:
	if e.has("puffs"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = e.get("seed", 1)
	var puffs: Array = []
	var count := rng.randi_range(5, 7)
	var span := 110.0
	for i in count:
		var t := float(i) / float(count - 1)
		# Bigger puffs in the middle, smaller at the ends; tops vary.
		var cx := lerpf(-span * 0.5, span * 0.5, t) + rng.randf_range(-8.0, 8.0)
		var r := lerpf(18.0, 34.0, 1.0 - absf(t - 0.5) * 2.0) * rng.randf_range(0.85, 1.15)
		var cy := -r * rng.randf_range(0.35, 0.75)
		puffs.append({"o": Vector2(cx, cy), "r": r})
	e["puffs"] = puffs


func _draw_cloud(e: Dictionary) -> void:
	_ensure_cloud_detail(e)
	var p := Vector2(e["x"], e["y"])
	var s: float = e["scale"]
	var c: Color = e["color"]
	# Underside shade: same silhouette nudged down, in a cooler darker tone.
	var shade := Color(c.r * 0.82, c.g * 0.86, c.b * 0.95, c.a)
	for puff in e["puffs"]:
		draw_circle(p + (puff["o"] + Vector2(0, 7)) * s, puff["r"] * s, shade)
	draw_rect(Rect2(p + Vector2(-58, -4) * s, Vector2(116, 14) * s), shade)
	# Main body.
	for puff in e["puffs"]:
		draw_circle(p + puff["o"] * s, puff["r"] * s, c)
	# Flat base in the main tone, slightly above the shade so a shadow lip shows.
	draw_rect(Rect2(p + Vector2(-55, -10) * s, Vector2(110, 12) * s), c)


# --- floating islands -------------------------------------------------------------

func _draw_island(e: Dictionary) -> void:
	var origin := Vector2(e["x"], e["y"])
	var sz := Vector2(e["w"], e["w"])
	BgArt.draw_island(self, origin, sz,
		e["color"],                                   # rock
		e["top_color"],                               # grass
		e.get("trunk_color", Color(0.43, 0.34, 0.26)),
		e.get("leaf_color", (e["top_color"] as Color).darkened(0.2)))
