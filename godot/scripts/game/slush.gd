class_name Slush
extends Node2D
## The endgame flood: over the final SLUSH_FINAL_SEC of the match, slush
## rises from the bottom of the map, heavily slowing anyone inside it.
## The level derives from the host-synced match clock, so every client
## computes (nearly) the same height with zero extra netcode; each peer
## applies the slowdown to its own player.

var level_y: float = GameConfig.MAP_HEIGHT + 80.0

var _wave := 0.0


func _ready() -> void:
	add_to_group("slush")
	z_index = 10  # over players: being submerged should look like it


func _process(delta: float) -> void:
	_wave += delta
	var resting := GameConfig.MAP_HEIGHT + 80.0
	var target := resting
	if GameState.match_running:
		var p: float = clampf(
			(GameConfig.SLUSH_FINAL_SEC - GameState.match_remaining) / GameConfig.SLUSH_FINAL_SEC,
			0.0, 1.0)
		target = resting - p * (GameConfig.SLUSH_RISE + 80.0)
	# The synced clock steps at 1Hz — ratchet smoothly toward the target.
	level_y = move_toward(level_y, target, 90.0 * delta)
	queue_redraw()


func _draw() -> void:
	# Don't draw when the surface is at/below the map bottom — the wavy top
	# edge would cross the bottom edge and the polygon fails triangulation.
	if level_y >= GameConfig.MAP_HEIGHT - 12.0:
		return
	var w := float(GameConfig.MAP_WIDTH)
	var bottom := float(GameConfig.MAP_HEIGHT)
	# Wavy surface
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := w * float(i) / float(steps)
		pts.append(Vector2(x, minf(level_y + sin(_wave * 2.2 + x * 0.011) * 7.0, bottom - 2.0)))
	pts.append(Vector2(w, bottom))
	pts.append(Vector2(0, bottom))
	draw_colored_polygon(pts, Color(0.78, 0.92, 0.97, 0.82))
	# Foam line along the surface
	for i in steps:
		var x0 := w * float(i) / float(steps)
		var x1 := w * float(i + 1) / float(steps)
		draw_line(
			Vector2(x0, level_y + sin(_wave * 2.2 + x0 * 0.011) * 7.0 - 2.0),
			Vector2(x1, level_y + sin(_wave * 2.2 + x1 * 0.011) * 7.0 - 2.0),
			Color(1, 1, 1, 0.9), 4.0)
