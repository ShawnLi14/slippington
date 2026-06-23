class_name PlatformBody
extends AnimatableBody2D
## A map platform built from generator data. Every material ("solid", "ice")
## comes in two variants: the normal one (collision layer 1) and a "thru"
## one drawn transparent (layer 2, one-way collision) that players can jump
## up through — and drop through with Down+Jump, which briefly masks layer 2
## off the player.
##
## AnimatableBody2D (not StaticBody2D) so platforms with "move" data carry
## their riders; movement phase derives from GameState.world_clock, which
## every peer resets on the same start_game RPC — no extra sync needed.

var rect := Rect2()
var type := "solid"
var thru := false
var ramp := 0  # 0 = flat; 1 rises to the right, -1 to the left (triangle)
var move_data: Dictionary = {}  # {axis, amplitude, period, phase} or empty
var conveyor: Dictionary = {}  # {dir: ±1, speed: float} or empty
var phase: Dictionary = {}  # {period, duty, offset} or empty — clocked solid↔thru

var _base_pos := Vector2.ZERO


static func create(data: Dictionary) -> PlatformBody:
	var p := PlatformBody.new()
	p.rect = data["rect"]
	p.type = data["type"]
	p.thru = data.get("thru", false)
	p.ramp = data.get("ramp", 0)
	p.move_data = data.get("move", {})
	p.conveyor = data.get("conveyor", {})
	p.phase = data.get("phase", {})
	return p


## Local-space shape for an angled platform: a normal-thickness slab tilted
## so its top edge runs from the low corner (16px above the rect bottom) to
## the high corner. The rect is the bounding box, thickness included.
func _ramp_points() -> PackedVector2Array:
	var half := rect.size / 2.0
	var t := 16.0
	if ramp > 0:
		return PackedVector2Array([
			Vector2(-half.x, half.y - t), Vector2(half.x, -half.y),
			Vector2(half.x, -half.y + t), Vector2(-half.x, half.y),
		])
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, half.y - t),
		Vector2(half.x, half.y), Vector2(-half.x, -half.y + t),
	])


func _ready() -> void:
	# While sync_to_physics is enabled (the AnimatableBody2D default),
	# transform writes outside _physics_process are silently DISCARDED.
	# So: disable it, place the body (the write sticks), THEN re-enable it
	# for movers so their per-physics-frame motion carries riders. Doing it
	# in any other order leaves the body at the origin — top-left corner.
	sync_to_physics = false
	position = rect.position + rect.size / 2.0
	_base_pos = position
	sync_to_physics = not move_data.is_empty()
	set_physics_process(not move_data.is_empty() or not phase.is_empty())
	var shape := CollisionShape2D.new()
	if ramp != 0:
		var tri := ConvexPolygonShape2D.new()
		tri.points = _ramp_points()
		shape.shape = tri
	else:
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = rect.size
		shape.shape = rect_shape
	if thru or not phase.is_empty():
		collision_layer = 2
		shape.one_way_collision = true
		shape.one_way_collision_margin = 8.0
	else:
		collision_layer = 1
	add_child(shape)


func _physics_process(_delta: float) -> void:
	if not move_data.is_empty():
		var t: float = GameState.world_clock / move_data["period"] + move_data["phase"]
		var offset: float = move_data["amplitude"] * sin(TAU * t)
		if move_data["axis"] == "y":
			position = _base_pos + Vector2(0, offset)
		else:
			position = _base_pos + Vector2(offset, 0)
	if not phase.is_empty():
		var on: bool = fmod(GameState.world_clock + phase["offset"], phase["period"]) < phase["duty"] * phase["period"]
		var want := 2 if on else 0
		if collision_layer != want:
			collision_layer = want
		if (on and modulate.a != 1.0) or (not on and modulate.a != 0.45):
			modulate.a = 1.0 if on else 0.45
			queue_redraw()


func _draw() -> void:
	var half := rect.size / 2.0
	if type == "wall":
		draw_rect(Rect2(-half, rect.size), Color("#262840"))
		draw_line(Vector2(-half.x + 2, -half.y), Vector2(-half.x + 2, half.y), Color("#575b85"), 3.0)
		draw_line(Vector2(half.x - 2, -half.y), Vector2(half.x - 2, half.y), Color("#575b85"), 3.0)
		return

	# One palette per material; the thru variant is the same material drawn
	# transparent. The bright dashed top edge carries the read — a half-alpha
	# dark fill alone disappears against the night sky themes.
	var fill := Color("#9fd4ee") if type == "ice" else Color("#2f3147")
	var edge := Color("#e8f7ff") if type == "ice" else Color("#575b85")
	var dash := Color("#cdf2ff") if type == "ice" else Color("#9aa2d8")
	var alpha := 0.5 if thru else 1.0
	if ramp != 0:
		var pts := _ramp_points()
		draw_colored_polygon(pts, Color(fill, alpha))
		# Highlight the walkable incline edge (top of the slab).
		var lo := Vector2(-half.x, half.y - 16.0) if ramp > 0 else Vector2(half.x, half.y - 16.0)
		var hi := Vector2(half.x, -half.y) if ramp > 0 else Vector2(-half.x, -half.y)
		draw_line(lo, hi, edge, 4.0 if type == "ice" else 3.0)
		if type == "ice":
			for i in range(1, 4):
				var g := lo.lerp(hi, float(i) / 4.0)
				draw_line(g + Vector2(-4, 6), g + Vector2(4, 6), Color(1, 1, 1, 0.7), 2.0)
		return
	draw_rect(Rect2(-half, rect.size), Color(fill, alpha))
	if thru:
		var x := -half.x
		while x < half.x:
			draw_line(Vector2(x, -half.y + 2), Vector2(minf(x + 12, half.x), -half.y + 2), dash, 3.0)
			x += 20.0
	else:
		draw_line(Vector2(-half.x, -half.y + 2), Vector2(half.x, -half.y + 2), edge, 4.0 if type == "ice" else 3.0)
	if not conveyor.is_empty():
		var cdir: int = conveyor["dir"]
		var cy := -half.y + 9.0
		var cx := -half.x + 14.0
		while cx < half.x - 14.0:
			draw_line(Vector2(cx, cy - 4), Vector2(cx + 6 * cdir, cy), Color(1, 1, 1, 0.6), 2.0)
			draw_line(Vector2(cx + 6 * cdir, cy), Vector2(cx, cy + 4), Color(1, 1, 1, 0.6), 2.0)
			cx += 22.0
	if not phase.is_empty():
		var px := -half.x + 6.0
		while px < half.x - 6.0:
			draw_line(Vector2(px, -half.y + 2), Vector2(minf(px + 8, half.x - 6.0), -half.y + 2), Color(1, 1, 1, 0.7), 2.0)
			px += 16.0
	if type == "ice":
		# Glints so it reads as slippery at a glance.
		var gx := -half.x + 14.0
		while gx < half.x - 10.0:
			draw_line(Vector2(gx, -half.y + 8), Vector2(gx + 8, -half.y + 8), Color(1, 1, 1, 0.7 * alpha), 2.0)
			gx += 46.0
