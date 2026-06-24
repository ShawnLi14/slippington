class_name LauncherPad
extends Area2D
## A directional launch pad: touch it and get flung up AND sideways along its
## aim vector. Like SpringPad, each peer applies the launch to its OWN player
## only (authority model) — deterministic from the seed, nothing to sync.

const SIZE := Vector2(48.0, 18.0)
const RETRIGGER_COOLDOWN := 0.3

var vel := Vector2(0, -700)  # launch velocity (up-and-sideways)
var _cooldown := 0.0
var _squash := 0.0


static func create(pos: Vector2, launch_vel: Vector2) -> LauncherPad:
	var pad := LauncherPad.new()
	pad.position = pos
	pad.vel = launch_vel
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
	# Duck-typed (see SpringPad) so headless map tests don't chain in Player.
	if not body.has_method("apply_launch"):
		return
	if _cooldown <= 0.0:
		_cooldown = RETRIGGER_COOLDOWN
		_squash = 1.0
		queue_redraw()
	if body.is_multiplayer_authority() and body.velocity.y >= -100.0:
		body.apply_launch(vel)


func _draw() -> void:
	# A cannon-ish wedge pointing along the aim, in the spring palette.
	var dir := vel.normalized()
	var squash_offset := _squash * 5.0
	draw_rect(Rect2(-SIZE.x / 2.0, 2.0, SIZE.x, 6.0), Color("#5a3d2b"))  # base
	var muzzle := dir * (14.0 - squash_offset)
	draw_line(Vector2.ZERO, muzzle, Color("#ff8c5a"), 6.0)
	draw_circle(muzzle, 5.0, Color("#ffd2b0"))
