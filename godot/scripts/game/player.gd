class_name Player
extends CharacterBody2D
## A player pawn. The owning peer (multiplayer authority) runs input and
## physics locally and broadcasts its state at 30 Hz over an unreliable RPC;
## on every other peer this node is a puppet that interpolates toward the
## latest received state. Game rules (tagging, timer) live on the host.

const DROP_THROUGH_TIME := 0.3
## Remote players render this far in the past, interpolated between real
## snapshots — smooth, with a fixed and known delay instead of a trailing lerp.
const INTERP_DELAY := 0.05
const MAX_EXTRAPOLATION := 0.1
## While "it" and touching someone, re-claim at most this often; the host
## rejects claims during tag immunity, so contact re-tags once it expires.
const CLAIM_INTERVAL_MS := 250
## Tag claims need deeper contact than the sprites' 40px — grazes that look
## like nothing on the victim's screen shouldn't count.
const CLAIM_CONTACT_SIZE := GameConfig.PLAYER_SIZE * 0.85
## Host-side position history window for lag-compensated claim validation.
const HISTORY_WINDOW := 0.6
## Brief freeze applied to both players involved in a tag (hit-stop).
const TAG_HITSTOP := 0.15

var peer_id := 1
var player_class: PlayerClass
var color := Color.WHITE
var display_name_text := "Player"

var facing_right := true
var anim_state := "idle"
var stun_left := 0.0
var hitstop_left := 0.0
var dash_left := 0.0
var _dash_speed := 0.0
var _drop_through_left := 0.0
var _cooldown_until_ms := 0

# Puppet interpolation state: [{t, pos, vel}] in receiver-clock seconds
var _snapshots: Array = []
var _teleport_count := 0
var _seen_teleport_count := 0
var _last_claim_ms := 0

# Host-only: timestamped position history for lag-compensated tag validation.
var _history: Array = []

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
	hitstop_left = maxf(0.0, hitstop_left - delta)
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
	var stunned := stun_left > 0.0 or hitstop_left > 0.0

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

	# Tagger-side hit detection: the "it" player's own client decides when
	# contact happens (true self vs. the puppets it actually sees), then the
	# host validates the claim. What you see is what you tag.
	if is_it():
		_check_tagging()

	if multiplayer.is_server():
		_record_history(global_position)

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


func _puppet_interpolate(_delta: float) -> void:
	if _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var prev: Dictionary
	var next: Dictionary
	for s in _snapshots:
		if s["t"] <= render_t:
			prev = s
		else:
			next = s
			break
	var target: Vector2
	if prev.is_empty():
		target = _snapshots[0]["pos"]
	elif next.is_empty():
		# Newest snapshot is older than the render time (packet gap):
		# extrapolate along last known velocity, but only briefly.
		var dt: float = clampf(render_t - prev["t"], 0.0, MAX_EXTRAPOLATION)
		target = prev["pos"] + prev["vel"] * dt
	else:
		var span: float = next["t"] - prev["t"]
		var f: float = 0.0 if span <= 0.0 else (render_t - prev["t"]) / span
		target = prev["pos"].lerp(next["pos"], f)
	global_position = target


@rpc("authority", "call_remote", "unreliable")
func sync_state(pos: Vector2, vel: Vector2, p_facing: bool, p_anim: String, teleports: int) -> void:
	if multiplayer.is_server():
		_record_history(pos)
	if teleports != _seen_teleport_count:
		_seen_teleport_count = teleports
		_snapshots.clear()  # blink/teleport: snap, don't glide through the gap
		global_position = pos
	_snapshots.append({"t": Time.get_ticks_msec() / 1000.0, "pos": pos, "vel": vel})
	while _snapshots.size() > 30:
		_snapshots.pop_front()
	if p_facing != facing_right or p_anim != anim_state:
		facing_right = p_facing
		anim_state = p_anim
		queue_redraw()


func _set_facing(right: bool) -> void:
	if facing_right != right:
		facing_right = right
		queue_redraw()


func _check_tagging() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_claim_ms < CLAIM_INTERVAL_MS:
		return
	for other in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		# Box overlap, slightly deeper than the sprites — matches what the
		# player sees while ruling out grazes the victim never saw.
		if absf(other.global_position.x - global_position.x) < CLAIM_CONTACT_SIZE \
				and absf(other.global_position.y - global_position.y) < CLAIM_CONTACT_SIZE:
			_last_claim_ms = now
			GameState.claim_tag_local(other.peer_id, global_position)
			return


# --- host-side position history (lag compensation) -----------------------------

func _record_history(pos: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_history.append({"t": t, "pos": pos})
	while not _history.is_empty() and _history[0]["t"] < t - HISTORY_WINDOW:
		_history.pop_front()


## Host-only: this player's position at a past host-clock time, interpolated
## between recorded samples. Clamps to the oldest/newest sample.
func position_at(t: float) -> Vector2:
	if _history.is_empty():
		return global_position
	if t <= _history[0]["t"]:
		return _history[0]["pos"]
	for i in range(_history.size() - 1, -1, -1):
		if _history[i]["t"] <= t:
			if i == _history.size() - 1:
				return _history[i]["pos"]
			var a: Dictionary = _history[i]
			var b: Dictionary = _history[i + 1]
			var span: float = b["t"] - a["t"]
			var f: float = 0.0 if span <= 0.0 else (t - a["t"]) / span
			return a["pos"].lerp(b["pos"], f)
	return _history[0]["pos"]


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
