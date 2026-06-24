class_name UpdraftZone
extends Area2D
## A vertical column of upward push: while inside, the owning peer's body is
## buoyed up (gravity countered + capped rise) so you float and steer. Each
## peer applies it only to its OWN player (authority model) — deterministic
## from the seed, nothing to sync.

const MAX_RISE := 230.0  # px/s cap on updraft-driven ascent

var rect := Rect2()
var accel := 1400.0  # upward px/s^2 applied while inside (> gravity = net lift)
var _bodies: Array = []


static func create(zone_rect: Rect2, zone_accel: float) -> UpdraftZone:
	var z := UpdraftZone.new()
	z.rect = zone_rect
	z.accel = zone_accel
	return z


func _ready() -> void:
	position = rect.position + rect.size / 2.0
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = rect.size
	shape.shape = r
	add_child(shape)
	collision_layer = 0
	collision_mask = 4  # players
	body_entered.connect(func(b): if not _bodies.has(b): _bodies.append(b))
	body_exited.connect(func(b): _bodies.erase(b))


func _physics_process(delta: float) -> void:
	for b in _bodies:
		if is_instance_valid(b) and b.has_method("apply_updraft") and b.is_multiplayer_authority():
			b.apply_updraft(accel, delta)


func _draw() -> void:
	# Faint up-arrows so the column reads as lift.
	var half := rect.size / 2.0
	var y := half.y - 10.0
	while y > -half.y:
		draw_line(Vector2(0, y), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		draw_line(Vector2(-4, y - 7), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		draw_line(Vector2(4, y - 7), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		y -= 34.0
