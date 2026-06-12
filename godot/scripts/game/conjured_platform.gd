class_name ConjuredPlatform
extends StaticBody2D
## Mason's conjured ledge: a temporary one-way platform anyone can stand on
## or drop through (layer 2, like the map's thru platforms — the existing
## Down+Jump mask trick works on it for free). Spawned locally on EVERY peer,
## because each client owns its own player's physics; tiny placement drift
## between screens is bounded by puppet-interpolation error and harmless.
## Blinks for the last second as a crumble warning, then frees itself.

const WIDTH := 120.0
const THICKNESS := 18.0
const WARN_SECS := 1.0

var owner_color := Color.WHITE
var lifetime := 4.0

var _age := 0.0


static func create(center: Vector2, p_lifetime: float, p_color: Color) -> ConjuredPlatform:
	var p := ConjuredPlatform.new()
	p.position = center
	p.lifetime = p_lifetime
	p.owner_color = p_color
	return p


func _ready() -> void:
	collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WIDTH, THICKNESS)
	shape.shape = rect
	shape.one_way_collision = true
	shape.one_way_collision_margin = 8.0
	add_child(shape)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var half := Vector2(WIDTH, THICKNESS) / 2.0
	var alpha := 0.85
	var left := lifetime - _age
	if left < WARN_SECS:
		# Crumble warning: pulse harder as time runs out.
		alpha = 0.3 + 0.55 * (0.5 + 0.5 * sin(left * 24.0))
	# Caster-colored so everyone knows whose ledge this is; dashed bright top
	# edge matches the map's thru platforms ("you can pass up through this").
	draw_rect(Rect2(-half, Vector2(WIDTH, THICKNESS)), Color(owner_color.darkened(0.6), alpha * 0.85))
	var dash := owner_color.lightened(0.35)
	var x := -half.x
	while x < half.x:
		draw_line(Vector2(x, -half.y + 2), Vector2(minf(x + 12, half.x), -half.y + 2), Color(dash, alpha), 3.0)
		x += 20.0
