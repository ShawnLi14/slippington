class_name Player
extends CharacterBody2D
## A player pawn. The owning peer (multiplayer authority) runs input and
## physics locally and broadcasts its state at 30 Hz over an unreliable RPC;
## on every other peer this node is a puppet that interpolates toward the
## latest received state. Game rules (tagging, timer) live on the host.

const PUPPET_LERP_RATE := 15.0
const PUPPET_SNAP_DISTANCE := 250.0
const DROP_THROUGH_TIME := 0.3

var peer_id := 1
var player_class: PlayerClass
var color := Color.WHITE
var display_name_text := "Player"

var facing_right := true
var anim_state := "idle"
var stun_left := 0.0
var dash_left := 0.0
var _dash_speed := 0.0
var _drop_through_left := 0.0
var _cooldown_until_ms := 0

# Puppet interpolation state
var _target_position := Vector2.ZERO
var _target_velocity := Vector2.ZERO
var _teleport_count := 0
var _seen_teleport_count := 0

var _sync_accumulator := 0.0
var _name_label: Label
var _was_it := false


func setup(p_peer_id: int, info: Dictionary, spawn_pos: Vector2) -> void:
	peer_id = p_peer_id
	name = str(p_peer_id)
	player_class = ClassRegistry.get_class_by_id(info.get("class_id", "slipper"))
	color = GameConfig.PLAYER_COLORS[info.get("color_index", 0)]
	display_name_text = info.get("name", "Player")
	global_position = spawn_pos
	_target_position = spawn_pos
	set_multiplayer_authority(p_peer_id)
	add_to_group("players")


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE)
	shape.shape = rect
	add_child(shape)
	collision_layer = 4
	collision_mask = 1 | 2

	_name_label = Label.new()
	_name_label.text = display_name_text
	_name_label.position = Vector2(-60, -GameConfig.PLAYER_SIZE / 2.0 - 48)
	_name_label.size = Vector2(120, 20)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	add_child(_name_label)

	GameState.it_changed.connect(func(_n, _o): queue_redraw())


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func is_it() -> bool:
	return GameState.players.get(peer_id, {}).get("is_it", false)


func _physics_process(delta: float) -> void:
	stun_left = maxf(0.0, stun_left - delta)
	dash_left = maxf(0.0, dash_left - delta)
	_drop_through_left = maxf(0.0, _drop_through_left - delta)
	collision_mask = 1 if _drop_through_left > 0.0 else (1 | 2)

	if is_multiplayer_authority():
		_authority_physics(delta)
		_sync_accumulator += delta
		# Stop broadcasting the moment the match ends — peers free their game
		# scene on the phase change and late packets would target dead nodes.
		if _sync_accumulator >= 1.0 / GameConfig.SYNC_HZ and GameState.phase == GameState.Phase.PLAYING:
			_sync_accumulator = 0.0
			sync_state.rpc(global_position, velocity, facing_right, anim_state, _teleport_count)
	else:
		_puppet_interpolate(delta)

	if is_it() != _was_it:
		_was_it = is_it()
		queue_redraw()


func _authority_physics(delta: float) -> void:
	var dashing := dash_left > 0.0
	var stunned := stun_left > 0.0

	if not dashing and not is_on_floor():
		velocity.y += GameConfig.GRAVITY * delta

	var direction := 0.0
	if not stunned:
		direction = Input.get_axis("move_left", "move_right")

	if dashing:
		velocity.x = (_dash_speed if facing_right else -_dash_speed)
		velocity.y = 0.0
	elif stunned:
		velocity.x = 0.0
	else:
		velocity.x = direction * GameConfig.PLAYER_SPEED * player_class.speed_mult
		if direction > 0.0:
			_set_facing(true)
		elif direction < 0.0:
			_set_facing(false)

		if Input.is_action_just_pressed("jump") and is_on_floor():
			if Input.is_action_pressed("move_down"):
				_drop_through_left = DROP_THROUGH_TIME
			else:
				velocity.y = GameConfig.JUMP_VELOCITY * player_class.jump_mult

		if Input.is_action_just_pressed("ability_primary"):
			try_use_ability()

	move_and_slide()

	# Hard world bounds (map edges).
	var half := GameConfig.PLAYER_SIZE / 2.0
	global_position.x = clampf(global_position.x, half, GameConfig.MAP_WIDTH - half)
	if global_position.y > GameConfig.MAP_HEIGHT + 200.0:
		global_position.y = -half  # fell out somehow — wrap to top

	var new_anim := "idle"
	if not is_on_floor():
		new_anim = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 10.0:
		new_anim = "run"
	if new_anim != anim_state:
		anim_state = new_anim
		queue_redraw()


func _puppet_interpolate(delta: float) -> void:
	if global_position.distance_to(_target_position) > PUPPET_SNAP_DISTANCE:
		global_position = _target_position
	else:
		var t := 1.0 - exp(-PUPPET_LERP_RATE * delta)
		global_position = global_position.lerp(_target_position + _target_velocity * delta, t)


@rpc("authority", "call_remote", "unreliable")
func sync_state(pos: Vector2, vel: Vector2, p_facing: bool, p_anim: String, teleports: int) -> void:
	_target_position = pos
	_target_velocity = vel
	if teleports != _seen_teleport_count:
		_seen_teleport_count = teleports
		global_position = pos  # blink/teleport: snap, don't glide
	if p_facing != facing_right or p_anim != anim_state:
		facing_right = p_facing
		anim_state = p_anim
		queue_redraw()


func _set_facing(right: bool) -> void:
	if facing_right != right:
		facing_right = right
		queue_redraw()


# --- abilities ----------------------------------------------------------------

func try_use_ability() -> void:
	var ability := player_class.primary_ability
	if ability == null or Time.get_ticks_msec() < _cooldown_until_ms:
		return
	if ability.execute(self):
		_cooldown_until_ms = Time.get_ticks_msec() + int(ability.cooldown_sec * 1000.0)
		GameState.report_ability_used(ability.id)


func get_cooldown_remaining() -> float:
	return maxf(0.0, float(_cooldown_until_ms - Time.get_ticks_msec()) / 1000.0)


func start_dash(speed: float, duration: float) -> void:
	_dash_speed = speed
	dash_left = duration


func apply_stun(duration: float) -> void:
	stun_left = duration
	dash_left = 0.0
	queue_redraw()


## Remote VFX entry point: another peer used an ability.
func play_remote_ability(ability_id: String) -> void:
	match ability_id:
		"blink":
			flash_ability_vfx(ability_id)
		"stun":
			spawn_pulse_ring(StunAbility.RADIUS)
		"dash":
			flash_ability_vfx(ability_id)


# --- VFX ------------------------------------------------------------------------

func spawn_blink_trail(from_pos: Vector2, to_pos: Vector2) -> void:
	_teleport_count += 1  # tells puppets to snap instead of glide
	for i in 6:
		var ghost := _make_ghost(from_pos.lerp(to_pos, float(i) / 5.0))
		get_parent().add_child(ghost)


func flash_ability_vfx(_ability_id: String) -> void:
	var ghost := _make_ghost(global_position)
	get_parent().add_child(ghost)


func spawn_pulse_ring(radius: float) -> void:
	var ring := PulseRing.new()
	ring.global_position = global_position
	ring.max_radius = radius
	ring.ring_color = color
	get_parent().add_child(ring)


func _make_ghost(at: Vector2) -> Node2D:
	var ghost := GhostFade.new()
	ghost.global_position = at
	ghost.ghost_color = color
	ghost.size = GameConfig.PLAYER_SIZE
	return ghost


# --- drawing --------------------------------------------------------------------

func _draw() -> void:
	var half := GameConfig.PLAYER_SIZE / 2.0
	var body_color := color
	if stun_left > 0.0:
		body_color = color.lerp(Color(0.4, 0.6, 1.0), 0.6)
	draw_rect(Rect2(-half, -half, GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE), body_color)

	# Eyes show facing direction.
	var eye_dir := 6.0 if facing_right else -6.0
	var eye_color := Color(0.06, 0.06, 0.1)
	draw_circle(Vector2(eye_dir - 4.0, -8.0), 4.0, eye_color)
	draw_circle(Vector2(eye_dir + 8.0, -8.0), 4.0, eye_color)

	if is_it():
		# Red arrow above the head: this player is IT.
		var top := -half - 8.0
		draw_colored_polygon(
			PackedVector2Array([Vector2(-10, top - 14), Vector2(10, top - 14), Vector2(0, top)]),
			Color(1.0, 0.25, 0.25)
		)


class GhostFade:
	extends Node2D
	var ghost_color := Color.WHITE
	var size := 40.0

	func _ready() -> void:
		z_index = -1
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.4)
		tween.tween_callback(queue_free)

	func _draw() -> void:
		var half := size / 2.0
		draw_rect(Rect2(-half, -half, size, size), Color(ghost_color, 0.4))


class PulseRing:
	extends Node2D
	var max_radius := 120.0
	var ring_color := Color.WHITE
	var _progress := 0.0

	func _ready() -> void:
		var tween := create_tween()
		tween.tween_method(_set_progress, 0.0, 1.0, 0.45)
		tween.tween_callback(queue_free)

	func _set_progress(v: float) -> void:
		_progress = v
		queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, max_radius * _progress, 0.0, TAU, 48, Color(ring_color, 1.0 - _progress), 4.0)
