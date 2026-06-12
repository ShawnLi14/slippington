class_name DecoyClone
extends CharacterBody2D
## Doppel's decoy: a convincing copy of the caster that keeps running the way
## they were going (turning around at walls and map edges) until it expires
## or an OPPONENT touches it — then it pops in a puff, outing itself as the
## fake. Simulated locally on every peer from cast-time state; screens can
## drift apart slightly, which is fine — the clone is theater, not gameplay.
## It is deliberately NOT in the "players" group: it can't be tagged, can't
## be stunned, and never eats a real tag.

const POP_RADIUS := 30.0
const FADE_SECS := 0.25

var clone_color := Color.WHITE
var clone_name := "Player"
var caster_peer_id := 0
var run_dir := 1.0
var speed := 300.0
var show_it_arrow := false
var lifetime := 2.5
var facing_right := true

var _age := 0.0
var _popped := false


func _ready() -> void:
	collision_layer = 0  # blocks nothing, blockable by nothing
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE)
	shape.shape = rect
	add_child(shape)

	# Same name tag as the real pawn — the label is half the disguise.
	var label := Label.new()
	label.text = clone_name
	label.position = Vector2(-60, -GameConfig.PLAYER_SIZE / 2.0 - 48)
	label.size = Vector2(120, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.12, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)


func _physics_process(delta: float) -> void:
	if _popped:
		return
	_age += delta
	if _age >= lifetime:
		_pop(false)
		return

	if not is_on_floor():
		velocity.y += GameConfig.GRAVITY * delta
	velocity.x = run_dir * speed
	move_and_slide()

	var half := GameConfig.PLAYER_SIZE / 2.0
	if global_position.x < half:
		global_position.x = half
		_flip(1.0)
	elif global_position.x > GameConfig.MAP_WIDTH - half:
		global_position.x = GameConfig.MAP_WIDTH - half
		_flip(-1.0)
	elif is_on_wall():
		_flip(-run_dir)
	if global_position.y > GameConfig.MAP_HEIGHT + 100.0:
		_pop(false)
		return

	# An opponent walking through the decoy pops it — touch calls the bluff.
	for other in get_tree().get_nodes_in_group("players"):
		if other.peer_id == caster_peer_id:
			continue
		if global_position.distance_to(other.global_position) < POP_RADIUS:
			_pop(true)
			return


func _flip(dir: float) -> void:
	run_dir = dir
	facing_right = dir > 0.0
	queue_redraw()


func _pop(burst: bool) -> void:
	_popped = true
	set_physics_process(false)
	if burst:
		var ring := Player.PulseRing.new()
		ring.global_position = global_position
		ring.max_radius = 50.0
		ring.ring_color = clone_color
		get_parent().add_child(ring)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECS)
	tween.tween_callback(queue_free)


func _draw() -> void:
	# Mirrors Player._draw() so the two are indistinguishable at a glance.
	var half := GameConfig.PLAYER_SIZE / 2.0
	draw_rect(Rect2(-half, -half, GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE), clone_color)
	var eye_dir := 6.0 if facing_right else -6.0
	var eye_color := Color(0.06, 0.06, 0.1)
	draw_circle(Vector2(eye_dir - 4.0, -8.0), 4.0, eye_color)
	draw_circle(Vector2(eye_dir + 8.0, -8.0), 4.0, eye_color)
	if show_it_arrow:
		var top := -half - 8.0
		draw_colored_polygon(
			PackedVector2Array([Vector2(-10, top - 14), Vector2(10, top - 14), Vector2(0, top)]),
			Color(1.0, 0.25, 0.25)
		)
