class_name PlatformBody
extends StaticBody2D
## A map platform built from generator data. Solid platforms live on
## collision layer 1; passthrough platforms on layer 2 with one-way
## collision so players can jump up through them (and drop through
## with Down+Jump, which briefly masks layer 2 off the player).

var rect := Rect2()
var type := "solid"


static func create(data: Dictionary) -> PlatformBody:
	var p := PlatformBody.new()
	p.rect = data["rect"]
	p.type = data["type"]
	return p


func _ready() -> void:
	position = rect.position + rect.size / 2.0
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	if type == "passthrough":
		collision_layer = 2
		shape.one_way_collision = true
		shape.one_way_collision_margin = 8.0
	else:
		collision_layer = 1
	add_child(shape)


func _draw() -> void:
	var half := rect.size / 2.0
	match type:
		"passthrough":
			draw_rect(Rect2(-half, rect.size), Color("#3a6b68"))
			# Dashed top edge marks platforms you can pass through.
			var x := -half.x
			while x < half.x:
				draw_line(Vector2(x, -half.y + 2), Vector2(minf(x + 12, half.x), -half.y + 2), Color("#7fe7df"), 3.0)
				x += 20.0
		"ice":
			draw_rect(Rect2(-half, rect.size), Color("#9fd4ee"))
			draw_line(Vector2(-half.x, -half.y + 2), Vector2(half.x, -half.y + 2), Color("#e8f7ff"), 4.0)
			# Glints so it reads as slippery at a glance.
			var gx := -half.x + 14.0
			while gx < half.x - 10.0:
				draw_line(Vector2(gx, -half.y + 8), Vector2(gx + 8, -half.y + 8), Color(1, 1, 1, 0.7), 2.0)
				gx += 46.0
		"wall":
			draw_rect(Rect2(-half, rect.size), Color("#262840"))
			draw_line(Vector2(-half.x + 2, -half.y), Vector2(-half.x + 2, half.y), Color("#575b85"), 3.0)
			draw_line(Vector2(half.x - 2, -half.y), Vector2(half.x - 2, half.y), Color("#575b85"), 3.0)
		_:
			draw_rect(Rect2(-half, rect.size), Color("#2f3147"))
			draw_line(Vector2(-half.x, -half.y + 2), Vector2(half.x, -half.y + 2), Color("#575b85"), 3.0)
