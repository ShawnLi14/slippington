class_name Portal
extends Area2D
## One end of a portal pair: step in, come out at the linked exit across
## the map. Each peer teleports only its OWN player (authority model), and
## players carry a short portal cooldown so the exit doesn't bounce you
## straight back. Deterministic from the map seed — nothing to sync.

const SIZE := Vector2(36.0, 64.0)

var dest := Vector2.ZERO
var tint := Color("#b46cff")

var _spin := 0.0


static func create(pos: Vector2, destination: Vector2) -> Portal:
	var p := Portal.new()
	p.position = pos
	p.dest = destination
	return p


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	add_child(shape)
	collision_layer = 0
	collision_mask = 4  # players
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_spin += delta * 2.0
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	# Duck-typed (see SpringPad) — and the player itself enforces the
	# per-player cooldown so the exit portal doesn't ping-pong you.
	if body.has_method("try_portal") and body.is_multiplayer_authority():
		body.try_portal(dest)


func _draw() -> void:
	# Swirling oval: outer ring, inner glow, slow-orbiting sparks.
	draw_arc(Vector2.ZERO, SIZE.y / 2.0, 0, TAU, 32, tint, 5.0)
	var squashed := Transform2D().scaled(Vector2(0.55, 1.0))
	draw_set_transform_matrix(squashed)
	draw_circle(Vector2.ZERO, SIZE.y / 2.0 - 6.0, Color(tint, 0.35))
	draw_set_transform_matrix(Transform2D())
	for i in 3:
		var a := _spin + TAU * float(i) / 3.0
		var p := Vector2(cos(a) * SIZE.x * 0.45, sin(a) * SIZE.y * 0.42)
		draw_circle(p, 3.0, Color(1, 1, 1, 0.8))
