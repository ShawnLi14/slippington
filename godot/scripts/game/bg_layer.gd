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

func _ensure_island_detail(e: Dictionary) -> void:
	if e.has("under_pts"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = e.get("seed", 1)
	var w: float = e["w"]
	# Jagged rocky underside: irregular polygon from the rim down to a tip.
	var depth := w * rng.randf_range(0.7, 0.95)
	var tip_x := w * rng.randf_range(0.42, 0.58)
	var pts := PackedVector2Array()
	pts.append(Vector2(0, 0))
	var steps := 7
	for i in range(1, steps):
		var t := float(i) / float(steps)
		# Stair-step jaggedness: alternate pulling points in/out so the rock
		# edge reads as cut stone instead of a smooth cone.
		var jag := w * 0.09 * (1.0 if i % 2 == 0 else -0.4) * rng.randf_range(0.6, 1.2)
		# Keep each chain on its own side of the tip so the outline stays a
		# simple polygon (crossing chains fail triangulation).
		var px := clampf(lerpf(0.0, tip_x, pow(t, 0.8)) + jag, -w * 0.06, tip_x - w * 0.03)
		var py := depth * pow(t, 1.5) * rng.randf_range(0.9, 1.0)
		pts.append(Vector2(px, py))
	pts.append(Vector2(tip_x, depth))
	for i in range(steps - 1, 0, -1):
		var t := float(i) / float(steps)
		var jag := w * 0.09 * (1.0 if i % 2 == 0 else -0.4) * rng.randf_range(0.6, 1.2)
		var px := clampf(lerpf(w, tip_x, pow(t, 0.8)) - jag, tip_x + w * 0.03, w * 1.06)
		var py := depth * pow(t, 1.5) * rng.randf_range(0.9, 1.0)
		pts.append(Vector2(px, py))
	pts.append(Vector2(w, 0))
	e["under_pts"] = pts
	e["depth"] = depth
	e["tip_x"] = tip_x
	# Grass drips: lobes hanging over the rim.
	var drips: Array = []
	var drip_count := rng.randi_range(4, 6)
	for i in drip_count:
		drips.append({
			"x": w * (0.08 + 0.84 * float(i) / float(drip_count - 1)) + rng.randf_range(-w * 0.03, w * 0.03),
			"r": w * rng.randf_range(0.045, 0.08),
		})
	e["drips"] = drips
	# A small tree or two on top.
	var trees: Array = []
	for i in rng.randi_range(1, 2):
		trees.append({
			"x": w * rng.randf_range(0.2, 0.8),
			"h": w * rng.randf_range(0.16, 0.24),
			"r": w * rng.randf_range(0.08, 0.13),
		})
	e["trees"] = trees
	# Detached rock chunks floating beneath the tip.
	var chunks: Array = []
	for i in rng.randi_range(1, 3):
		chunks.append({
			"o": Vector2(tip_x + rng.randf_range(-w * 0.2, w * 0.2),
				depth + w * (0.12 + 0.14 * float(i))),
			"r": w * rng.randf_range(0.03, 0.07) * (1.0 - 0.2 * float(i)),
		})
	e["chunks"] = chunks


func _draw_island(e: Dictionary) -> void:
	_ensure_island_detail(e)
	var origin := Vector2(e["x"], e["y"])
	var w: float = e["w"]
	var rock: Color = e["color"]
	var grass: Color = e["top_color"]
	var rock_dark := rock.darkened(0.25)
	var grass_dark := grass.darkened(0.2)

	# Rocky underside (jagged polygon), with a darker core toward the tip:
	# the same silhouette scaled about the tip point, so the strata follow
	# the rock's own shape.
	var pts: PackedVector2Array = e["under_pts"]
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(origin + p)
	draw_colored_polygon(moved, rock)
	var tip := Vector2(e["tip_x"], e["depth"])
	var core := PackedVector2Array()
	for p in pts:
		core.append(origin + tip + (p - tip) * 0.62)
	draw_colored_polygon(core, rock_dark)

	# Floating rock chunks under the tip.
	for chunk in e["chunks"]:
		draw_circle(origin + chunk["o"], chunk["r"], rock_dark)

	# Grass cap: dark rim ellipse, drips over the edge, lighter top surface.
	draw_colored_polygon(_ellipse(origin + Vector2(w * 0.5, 2.0), w * 0.54, w * 0.13), grass_dark)
	for drip in e["drips"]:
		draw_circle(origin + Vector2(drip["x"], 4.0), drip["r"], grass_dark)
	draw_colored_polygon(_ellipse(origin + Vector2(w * 0.5, -4.0), w * 0.52, w * 0.11), grass)

	# Trees: trunk + two-tone foliage blobs.
	for tree in e["trees"]:
		var base := origin + Vector2(tree["x"], -6.0)
		draw_rect(Rect2(base + Vector2(-tree["r"] * 0.12, -tree["h"]), Vector2(tree["r"] * 0.24, tree["h"])), rock_dark)
		draw_circle(base + Vector2(0, -tree["h"]), tree["r"], grass_dark)
		draw_circle(base + Vector2(-tree["r"] * 0.4, -tree["h"] - tree["r"] * 0.35), tree["r"] * 0.7, grass)
		draw_circle(base + Vector2(tree["r"] * 0.45, -tree["h"] - tree["r"] * 0.25), tree["r"] * 0.6, grass)


func _ellipse(center: Vector2, rx: float, ry: float, segments := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
