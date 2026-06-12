class_name SpringPad
extends Area2D
## A launch pad: touch it and get flung upward. Each peer applies the
## launch to its OWN player only (authority model), so there's nothing to
## sync — pads are deterministic from the map seed and the launch shows up
## through normal position replication.

const SIZE := Vector2(56.0, 16.0)
const LAUNCH_VELOCITY := -780.0  # ~2.4x jump height
const RETRIGGER_COOLDOWN := 0.3

var _cooldown := 0.0
var _squash := 0.0


static func create(pos: Vector2) -> SpringPad:
	var pad := SpringPad.new()
	pad.position = pos
	return pad


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
	_cooldown = maxf(0.0, _cooldown - delta)
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta * 4.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	# Duck-typed on purpose: referencing the Player class here would chain
	# this script (and the autoloads Player needs) into headless map tests.
	if not body.has_method("apply_spring"):
		return
	# Squash animation plays for everyone; the launch itself only applies
	# to the body its owner controls.
	if _cooldown <= 0.0:
		_cooldown = RETRIGGER_COOLDOWN
		_squash = 1.0
		queue_redraw()
	if body.is_multiplayer_authority() and body.velocity.y >= -100.0:
		body.apply_spring(LAUNCH_VELOCITY)


func _draw() -> void:
	var squash_offset := _squash * 5.0
	# Base
	draw_rect(Rect2(-SIZE.x / 2.0, 2.0, SIZE.x, 6.0), Color("#5a3d2b"))
	# Coil hint
	draw_line(Vector2(-SIZE.x * 0.25, 2.0), Vector2(-SIZE.x * 0.15, -4.0 + squash_offset), Color("#c9a26b"), 3.0)
	draw_line(Vector2(SIZE.x * 0.25, 2.0), Vector2(SIZE.x * 0.15, -4.0 + squash_offset), Color("#c9a26b"), 3.0)
	# Pad
	var pad_rect := Rect2(-SIZE.x / 2.0, -8.0 + squash_offset, SIZE.x, 7.0)
	draw_rect(pad_rect, Color("#ff8c5a"))
	draw_line(pad_rect.position + Vector2(0, 1), pad_rect.position + Vector2(SIZE.x, 1), Color("#ffd2b0"), 2.0)
