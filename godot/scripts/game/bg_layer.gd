class_name BgLayer
extends Node2D
## A data-driven painter for one depth layer of the background. Holds a list of
## simple shape "elements" (mountain / island / cloud) and draws them. If
## scroll_speed is non-zero it drifts them left and wraps, giving slow motion
## without a scrolling camera (the play area is exactly one screen, so real
## camera parallax never triggers).

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


func _draw_island(e: Dictionary) -> void:
	var x: float = e["x"]
	var y: float = e["y"]
	var w: float = e["w"]
	# Rock underside: a downward wedge.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w * 0.5, y + w * 0.65),
	]), e["color"])
	# Grass cap: a flat ellipse sitting on top.
	draw_colored_polygon(_ellipse(Vector2(x + w * 0.5, y), w * 0.55, w * 0.18), e["top_color"])


func _draw_cloud(e: Dictionary) -> void:
	var p := Vector2(e["x"], e["y"])
	var s: float = e["scale"]
	var c: Color = e["color"]
	draw_circle(p + Vector2(-30, 8) * s, 22 * s, c)
	draw_circle(p + Vector2(34, 6) * s, 26 * s, c)
	draw_circle(p + Vector2(8, -14) * s, 24 * s, c)
	draw_circle(p, 30 * s, c)
	# Flatten the bottom so it reads as a cloud, not a bubble cluster.
	draw_rect(Rect2(p + Vector2(-52, 0) * s, Vector2(104, 20) * s), c)


func _ellipse(center: Vector2, rx: float, ry: float, segments := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
