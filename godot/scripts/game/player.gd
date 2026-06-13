class_name Player
extends CharacterBody2D
## A player pawn. The owning peer (multiplayer authority) runs input and
## physics locally and broadcasts its state at 30 Hz over an unreliable RPC;
## on every other peer this node is a puppet that interpolates toward the
## latest received state. Game rules (tagging, timer) live on the host.

const DROP_THROUGH_TIME := 0.3
## Remote players render slightly in the past on the SENDER's timeline,
## interpolated between snapshots. Packets carry the sender's physics tick,
## so spacing is perfectly even regardless of network jitter; the render
## delay adapts to measured jitter within these bounds.
const PHYS_DT := 1.0 / 60.0
const DELAY_MIN := 0.05
const DELAY_MAX := 0.15
const OFFSET_WINDOW_SEC := 3.0
const MAX_EXTRAPOLATION := 0.1
## While "it" and touching someone, re-claim at most this often; the host
## rejects claims during tag immunity, so contact re-tags once it expires.
const CLAIM_INTERVAL_MS := 250
## Tag claims need deeper contact than the sprites' 40px — grazes that look
## like nothing on the victim's screen shouldn't count.
const CLAIM_CONTACT_SIZE := GameConfig.PLAYER_SIZE * 0.85
## Host-side position history window for lag-compensated claim validation.
const HISTORY_WINDOW := 0.6
## Echo (Rewind) looks 2s into the past; keep a little extra so the lookup
## never falls off the end of the buffer.
const ECHO_WINDOW := 2.2
## Brief freeze applied to both players involved in a tag (hit-stop).
const TAG_HITSTOP := 0.15

var peer_id := 1
var player_class: PlayerClass
var color := Color.WHITE
var display_name_text := "Player"
## When set, this node is driven by AI instead of the keyboard (practice
## mode bot). It still runs the normal authority physics path.
var bot_brain: BotBrain = null

var facing_right := true
var anim_state := "idle"
## Visual lean to match the slope underfoot. The authority computes the
## target from the floor normal; both it and puppets ease _tilt toward
## _tilt_target every frame so the body banks smoothly on ramps. Only the
## drawing rotates — the collision box and name label stay upright.
var _tilt := 0.0
var _tilt_target := 0.0
var stun_left := 0.0
var hitstop_left := 0.0
var dash_left := 0.0
var _dash_speed := 0.0
var _drop_through_left := 0.0
var _portal_cooldown_left := 0.0
var _cooldown_until_ms := 0
# Doppel cloak: while active the whole pawn (label and IT arrow included)
# renders at _cloak_alpha — 0.5 on the caster's own screen, 0.0 on others'.
var _cloak_left := 0.0
var _cloak_alpha := 1.0

# Puppet stream state. Snapshots are [{t, pos, vel}] on the SENDER timeline
# (t = sender physics tick × PHYS_DT); _stream_offset maps sender time to
# local clock (sliding-window minimum of arrival − sender_t, the classic
# clock-sync trick — the minimum isolates clock difference + best-case
# transit, and the window range above it measures jitter).
var _snapshots: Array = []
var _last_seq := -1
var _offset_window: Array = []  # [{at: local sec, off: sec}]
var _stream_offset := 0.0
var _interp_delay := DELAY_MIN
var _teleport_count := 0
var _seen_teleport_count := 0
var _last_claim_ms := 0

# Host-only: timestamped position history for lag-compensated tag validation.
var _history: Array = []

# Echo class only: recent (t, pos, vel) trail for the Rewind ability. The
# authority records its exact state; puppets record the sync stream so
# remote screens can place the telegraph marker.
var _echo_history: Array = []

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
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_name_label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.12, 0.85))
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label)

	# Method connection (NOT a lambda): Godot auto-disconnects method
	# callables when this node is freed. A lambda here would keep firing
	# into freed memory after the match ends — a random crash in release
	# builds.
	GameState.it_changed.connect(_on_it_changed_redraw)


func _on_it_changed_redraw(_new_it: int, _old_it: int) -> void:
	queue_redraw()


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func is_it() -> bool:
	return GameState.players.get(peer_id, {}).get("is_it", false)


func _physics_process(delta: float) -> void:
	stun_left = maxf(0.0, stun_left - delta)
	hitstop_left = maxf(0.0, hitstop_left - delta)
	dash_left = maxf(0.0, dash_left - delta)
	_portal_cooldown_left = maxf(0.0, _portal_cooldown_left - delta)
	_drop_through_left = maxf(0.0, _drop_through_left - delta)
	collision_mask = 1 if _drop_through_left > 0.0 else (1 | 2)
	if _cloak_left > 0.0:
		_cloak_left = maxf(0.0, _cloak_left - delta)
		modulate.a = _cloak_alpha if _cloak_left > 0.0 else 1.0

	if is_multiplayer_authority():
		_authority_physics(delta)
		_sync_accumulator += delta
		# Stop broadcasting the moment the match ends — peers free their game
		# scene on the phase change and late packets would target dead nodes.
		if _sync_accumulator >= 1.0 / GameConfig.SYNC_HZ and GameState.phase == GameState.Phase.PLAYING:
			_sync_accumulator = 0.0
			sync_state.rpc(Engine.get_physics_frames(), global_position, velocity, facing_right, anim_state, _teleport_count, _tilt_target)

	if is_it() != _was_it:
		_was_it = is_it()
		queue_redraw()


func _process(delta: float) -> void:
	# Puppets interpolate per RENDERED frame (not per physics tick) so they
	# stay smooth on high-refresh displays; the timeline is continuous.
	if not is_multiplayer_authority():
		_puppet_interpolate()
	var prev_tilt := _tilt
	_tilt = lerp_angle(_tilt, _tilt_target, clampf(delta * 12.0, 0.0, 1.0))
	if absf(angle_difference(prev_tilt, _tilt)) > 0.002:
		queue_redraw()


func _authority_physics(delta: float) -> void:
	var dashing := dash_left > 0.0
	var stunned := stun_left > 0.0 or hitstop_left > 0.0

	if not dashing and not is_on_floor():
		velocity.y += GameConfig.GRAVITY * delta

	var direction := 0.0
	if not stunned:
		direction = bot_brain.move_dir if bot_brain != null else Input.get_axis("move_left", "move_right")

	if dashing:
		velocity.x = (_dash_speed if facing_right else -_dash_speed)
		velocity.y = 0.0
	elif stunned:
		velocity.x = 0.0
	else:
		var target_vx := direction * GameConfig.PLAYER_SPEED * player_class.speed_mult
		if _in_slush():
			target_vx *= GameConfig.SLUSH_SLOW
		if _standing_on_ice():
			# Slide: gradual accel/brake — reversing direction is a commitment.
			velocity.x = move_toward(velocity.x, target_vx, GameConfig.ICE_ACCEL * delta)
		else:
			velocity.x = target_vx
		if direction > 0.0:
			_set_facing(true)
		elif direction < 0.0:
			_set_facing(false)

		var jump_pressed := bot_brain.poll_jump() if bot_brain != null else Input.is_action_just_pressed("jump")
		if jump_pressed and is_on_floor():
			# A bot drops through one-way platforms by flagging want_drop; a
			# human holds Down. Either way a "drop" jump becomes a pass-through.
			var want_drop := bot_brain.want_drop if bot_brain != null else Input.is_action_pressed("move_down")
			if want_drop:
				_drop_through_left = DROP_THROUGH_TIME
			else:
				velocity.y = GameConfig.JUMP_VELOCITY * player_class.jump_mult
				SoundManager.play("jump")

		if bot_brain == null and Input.is_action_just_pressed("ability_primary"):
			try_use_ability()

	move_and_slide()

	# Bank to the slope: a floor that isn't flat tilts the body to stand
	# perpendicular to it (flat ground and air both resolve to upright).
	if is_on_floor():
		_tilt_target = get_floor_normal().angle() + PI / 2.0
	else:
		_tilt_target = 0.0

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

	if _uses_echo():
		_record_echo(global_position, velocity)

	var new_anim := "idle"
	if not is_on_floor():
		new_anim = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 10.0:
		new_anim = "run"
	if new_anim != anim_state:
		anim_state = new_anim
		queue_redraw()


func _puppet_interpolate() -> void:
	if _snapshots.is_empty():
		return
	# Estimated newest-available sender time, minus the adaptive delay.
	var render_t := Time.get_ticks_msec() / 1000.0 - _stream_offset - _interp_delay
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


## The delay this client is currently rendering this player at — sent with
## tag claims so the host's lag-compensation rewind matches reality.
func get_interp_delay() -> float:
	return _interp_delay


@rpc("authority", "call_remote", "unreliable")
func sync_state(tick: int, pos: Vector2, vel: Vector2, p_facing: bool, p_anim: String, teleports: int, p_tilt: float) -> void:
	if multiplayer.is_server():
		_record_history(pos)
	# Unreliable channels reorder: a late stale packet must not rewind the
	# timeline (this was a visible source of puppet twitch).
	if tick <= _last_seq:
		return
	_last_seq = tick
	_tilt_target = p_tilt

	var now := Time.get_ticks_msec() / 1000.0
	var sender_t := float(tick) * PHYS_DT
	_offset_window.append({"at": now, "off": now - sender_t})
	while not _offset_window.is_empty() and _offset_window[0]["at"] < now - OFFSET_WINDOW_SEC:
		_offset_window.pop_front()
	var mn := INF
	var mx := -INF
	for s in _offset_window:
		mn = minf(mn, s["off"])
		mx = maxf(mx, s["off"])
	_stream_offset = mn
	# Window spread = arrival jitter; render far enough behind to absorb it.
	var target_delay: float = clampf((mx - mn) * 1.5 + 0.016, DELAY_MIN, DELAY_MAX)
	_interp_delay = lerpf(_interp_delay, target_delay, 0.05)

	if teleports != _seen_teleport_count:
		_seen_teleport_count = teleports
		_snapshots.clear()  # blink/teleport: snap, don't glide through the gap
		global_position = pos
	_snapshots.append({"t": sender_t, "pos": pos, "vel": vel})
	while _snapshots.size() > 40:
		_snapshots.pop_front()
	if _uses_echo():
		_record_echo(pos, vel)
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
			GameState.claim_tag_local(peer_id, other.peer_id, global_position, other.get_interp_delay())
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


func _in_slush() -> bool:
	var slush := get_tree().get_first_node_in_group("slush")
	return slush != null and global_position.y + GameConfig.PLAYER_SIZE / 2.0 > slush.level_y


func _standing_on_ice() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PlatformBody and collider.type == "ice":
			return true
	return false


## Launch from a spring pad (applied by the owning peer only).
func apply_spring(launch_velocity: float) -> void:
	velocity.y = launch_velocity
	dash_left = 0.0
	SoundManager.play("spring")


## Step through a portal (owning peer only); cooldown stops the exit
## portal from bouncing you straight back.
func try_portal(dest: Vector2) -> void:
	if _portal_cooldown_left > 0.0:
		return
	_portal_cooldown_left = 2.0
	SoundManager.play("portal")
	teleport_to(dest)


func start_dash(speed: float, duration: float) -> void:
	_dash_speed = speed
	dash_left = duration


func apply_stun(duration: float) -> void:
	stun_left = duration
	dash_left = 0.0
	queue_redraw()


## Authority-side instant relocation (Swap). Marks the move as a teleport
## so puppets snap instead of gliding across the map.
func teleport_to(pos: Vector2) -> void:
	spawn_blink_trail(global_position, pos)
	global_position = pos


# --- echo (Rewind ability) ------------------------------------------------------

func _uses_echo() -> bool:
	return player_class != null and player_class.primary_ability != null \
			and player_class.primary_ability.id == "rewind"


func _record_echo(pos: Vector2, vel: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_echo_history.append({"t": t, "pos": pos, "vel": vel})
	while not _echo_history.is_empty() and _echo_history[0]["t"] < t - ECHO_WINDOW:
		_echo_history.pop_front()


## This player's recorded state secs_back ago (clamped to the oldest sample,
## so an early-match rewind just goes to the spawn-side of the trail).
func get_echo_state(secs_back: float) -> Dictionary:
	var cutoff := Time.get_ticks_msec() / 1000.0 - secs_back
	for entry in _echo_history:
		if entry["t"] >= cutoff:
			return entry
	if _echo_history.is_empty():
		return {"pos": global_position, "vel": velocity}
	return _echo_history[-1]


## Telegraph the destination, then snap there after the delay. The tween is
## bound to this node, so a mid-telegraph match end can't fire into freed
## memory. Getting tagged during the telegraph stands — that's counterplay.
func start_rewind(target_pos: Vector2, target_vel: Vector2, delay: float) -> void:
	spawn_echo_marker(target_pos, delay)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_finish_rewind.bind(target_pos, target_vel))


func _finish_rewind(target_pos: Vector2, target_vel: Vector2) -> void:
	teleport_to(target_pos)
	velocity = target_vel  # past momentum comes back with you
	dash_left = 0.0


# --- doppel (Decoy class) ---------------------------------------------------

## Fade this pawn for `duration`. The caster passes 0.5 (you must still see
## yourself to play); remote screens pass 0.0 — there, the decoy is all
## anyone can see. Tag detection ignores visuals, so you stay taggable.
func start_cloak(duration: float, alpha: float) -> void:
	_cloak_left = duration
	_cloak_alpha = alpha
	modulate.a = alpha


## Spawn this player's decoy from its current state. Runs on every peer (the
## owner from exact state, others from the puppet); each screen simulates its
## own copy. Standing still works too: the clone runs off in your facing
## direction while you hold your ground.
func spawn_decoy_clone(lifetime: float) -> void:
	var clone := DecoyClone.new()
	clone.global_position = global_position
	clone.velocity = velocity
	clone.clone_color = color
	clone.clone_name = display_name_text
	clone.caster_peer_id = peer_id
	clone.speed = GameConfig.PLAYER_SPEED * player_class.speed_mult
	clone.run_dir = signf(velocity.x) if absf(velocity.x) > 10.0 else (1.0 if facing_right else -1.0)
	clone.facing_right = clone.run_dir > 0.0
	clone.show_it_arrow = is_it()
	clone.lifetime = lifetime
	get_parent().add_child(clone)


# --- ledge (Mason class) ------------------------------------------------------

## Conjure the temporary platform just below this player's feet, clamped
## inside the map. Runs on every peer — each client needs the collision body
## locally for its own pawn to stand on.
func spawn_conjured_ledge(lifetime: float) -> void:
	var half_w := ConjuredPlatform.WIDTH / 2.0
	var cx := clampf(global_position.x, half_w, GameConfig.MAP_WIDTH - half_w)
	var cy := global_position.y + GameConfig.PLAYER_SIZE / 2.0 + ConjuredPlatform.THICKNESS / 2.0 + 4.0
	get_parent().add_child(ConjuredPlatform.create(Vector2(cx, cy), lifetime, color))
	spawn_pulse_ring(45.0)


## Remote VFX entry point: another peer used an ability.
func play_remote_ability(ability_id: String) -> void:
	match ability_id:
		"blink":
			flash_ability_vfx(ability_id)
		"stun":
			spawn_stun_burst(StunAbility.RADIUS)
		"swap":
			spawn_pulse_ring(50.0)
		"rewind":
			spawn_echo_marker(get_echo_state(RewindAbility.REWIND_SECS)["pos"], RewindAbility.TELEGRAPH_SECS)
		"doppel":
			spawn_decoy_clone(DoppelAbility.CLONE_SECS)
			start_cloak(DoppelAbility.CLOAK_SECS, 0.0)
		"build":
			spawn_conjured_ledge(BuildAbility.LEDGE_SECS)
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


## Stun AoE: unlike the thin pulse ring, this fills the whole affected disc
## and holds it at full radius for a beat, so victims (and the Anchor) can
## see exactly who was in range. Targets are picked at cast time, so the
## visual must reach full size near-instantly to be honest.
func spawn_stun_burst(radius: float) -> void:
	var burst := StunBurst.new()
	burst.global_position = global_position
	burst.max_radius = radius
	burst.ring_color = color
	get_parent().add_child(burst)


## Rewind telegraph: a ghost of the player at the destination with a ring
## that shrinks down over the marker's lifetime — when it closes, they snap.
func spawn_echo_marker(pos: Vector2, lifetime: float) -> void:
	var marker := EchoMarker.new()
	marker.global_position = pos
	marker.marker_color = color
	marker.lifetime = lifetime
	get_parent().add_child(marker)


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

	# Body and eyes bank with the slope; the arrow below is drawn after the
	# transform resets so it always points straight down at the player.
	draw_set_transform(Vector2.ZERO, _tilt)
	draw_rect(Rect2(-half, -half, GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE), body_color)
	var eye_dir := 6.0 if facing_right else -6.0
	var eye_color := Color(0.06, 0.06, 0.1)
	draw_circle(Vector2(eye_dir - 4.0, -8.0), 4.0, eye_color)
	draw_circle(Vector2(eye_dir + 8.0, -8.0), 4.0, eye_color)
	draw_set_transform(Vector2.ZERO, 0.0)

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


## Stun AoE visual: fast expand (0.15s) -> hold the filled disc at full
## radius (0.4s) -> fade (0.3s).
class StunBurst:
	extends Node2D
	var max_radius := 150.0
	var ring_color := Color.WHITE
	var _radius_frac := 0.0
	var _alpha := 1.0

	func _ready() -> void:
		var tween := create_tween()
		tween.tween_method(_set_radius, 0.0, 1.0, 0.15)
		tween.tween_interval(0.4)
		tween.tween_method(_set_alpha, 1.0, 0.0, 0.3)
		tween.tween_callback(queue_free)

	func _set_radius(v: float) -> void:
		_radius_frac = v
		queue_redraw()

	func _set_alpha(v: float) -> void:
		_alpha = v
		queue_redraw()

	func _draw() -> void:
		var r := max_radius * _radius_frac
		draw_circle(Vector2.ZERO, r, Color(ring_color, 0.18 * _alpha))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(ring_color, 0.9 * _alpha), 5.0)
		# Inner echo ring so the boundary still reads over busy backgrounds.
		if r > 24.0:
			draw_arc(Vector2.ZERO, r - 12.0, 0.0, TAU, 64, Color(1, 1, 1, 0.35 * _alpha), 2.0)


## Rewind destination telegraph: ghost player square + a ring that shrinks
## over `lifetime` (the snap lands when it closes), then a short fade.
class EchoMarker:
	extends Node2D
	const FADE := 0.15
	var marker_color := Color.WHITE
	var lifetime := 0.3
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= lifetime + FADE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var alpha := 0.6
		if _t > lifetime:
			alpha *= maxf(0.0, 1.0 - (_t - lifetime) / FADE)
		var half := GameConfig.PLAYER_SIZE / 2.0
		draw_rect(Rect2(-half, -half, GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE), Color(marker_color, alpha * 0.45))
		draw_rect(Rect2(-half, -half, GameConfig.PLAYER_SIZE, GameConfig.PLAYER_SIZE), Color(1, 1, 1, alpha * 0.7), false, 2.0)
		var f := clampf(_t / maxf(lifetime, 0.001), 0.0, 1.0)
		draw_arc(Vector2.ZERO, half + 28.0 * (1.0 - f) + 4.0, 0.0, TAU, 32, Color(marker_color, alpha), 2.5)
