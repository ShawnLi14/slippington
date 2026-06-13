class_name BotPolicy
extends RefCounted
## Decides WHERE a bot wants to be; BotNavigator decides how to get there.
## As "it" the goal leads the prey (cut it off, don't tail it); as prey the
## goal is an escape surface that's far from the hunter, not a dead end, and
## biased upward so chases go vertical (where the juking happens). Evade goals
## are recomputed on a cadence and held, so the bot commits to a route instead
## of dithering every frame.

var _goal := Vector2.ZERO
var _want_ability := false
var _cd := 0.0
var _inited := false
# Per-bot RNG seeded from (map, peer) so the hesitation/ability rolls are
# reproducible run-to-run instead of pulling from the global randf() state —
# makes telemetry comparable across runs (network jitter aside).
var _rng := RandomNumberGenerator.new()
var _seeded := false


## Re-decide goal + ability on the difficulty's reaction cadence, holding the
## decision in between. The stale window IS the difficulty: a high reaction
## means the bot commits to where you were and is easy to juke. Returns
## {goal, ability}. players = game.get_player_nodes(), diff = BotDifficulty.params.
func tick(me: Node, players: Array, graph: Dictionary, diff: Dictionary, delta: float) -> Dictionary:
	if not _seeded:
		_seeded = true
		_rng.seed = hash("%s:%d" % [GameState.map_seed, me.peer_id])
	_cd -= delta
	if not _inited or _cd <= 0.0:
		_inited = true
		_cd = diff.get("reaction", 0.16)
		_recompute(me, players, graph, diff)
	return {"goal": _goal, "ability": _want_ability}


func _recompute(me: Node, players: Array, graph: Dictionary, diff: Dictionary) -> void:
	# Newbie dithering: freeze for a beat instead of reacting.
	if diff.get("hesitate", 0.0) > 0.0 and _rng.randf() < diff["hesitate"]:
		_goal = me.global_position
		_want_ability = false
		return
	if me.is_it():
		var prey := _nearest_other(me, players)
		_goal = chase_goal(me, prey, diff.get("lead", 0.3)) if prey != null else me.global_position
	else:
		var hunter := _hunter(me, players)
		_goal = evade_goal(me.global_position, hunter.global_position, graph, diff.get("evade_smart", true)) if hunter != null else me.global_position
	_want_ability = _rng.randf() < diff.get("ability_chance", 0.75) and should_use_ability(me, players)


## Lead the prey by `lead` seconds of its current velocity so the chaser
## arrives where the prey is going (cut-off), not where it was (tailing).
static func chase_goal(me: Node, prey: Node, lead := 0.3) -> Vector2:
	return prey.global_position + prey.velocity * lead


## Where to flee. Smart: the best escape surface (far from the hunter, not a
## dead end, mild height bias). Dumb: just bolt away horizontally — which runs
## you into a wall and corners you, exactly how a new player loses.
static func evade_goal(me_pos: Vector2, hunter_pos: Vector2, graph: Dictionary, smart := true) -> Vector2:
	if not smart:
		var dir := signf(me_pos.x - hunter_pos.x)
		if dir == 0.0:
			dir = 1.0
		return Vector2(clampf(me_pos.x + dir * 600.0, 80.0, GameConfig.MAP_WIDTH - 80.0), me_pos.y)
	var surfaces: Array = graph["surfaces"]
	var cut: Array = graph["cut"]
	var best := me_pos
	var best_score := -INF
	for i in surfaces.size():
		var r: Rect2 = surfaces[i]["rect"]
		var c := Vector2(r.get_center().x, r.position.y - GameConfig.PLAYER_SIZE * 0.5)
		var score := c.distance_to(hunter_pos) - 0.5 * c.distance_to(me_pos)
		if i < cut.size() and cut[i]:
			score -= 280.0  # dead end — don't corner yourself
		score += (GameConfig.MAP_HEIGHT - c.y) * 0.08  # mild preference for high ground
		if score > best_score:
			best_score = score
			best = c
	return best


## Should this bot fire its ability right now? Class- and role-aware, instead
## of mashing it on cooldown. Cooldown itself is enforced by try_use_ability,
## so this only encodes intent: when does this ability actually help?
static func should_use_ability(me: Node, players: Array) -> bool:
	if me.player_class == null or me.player_class.primary_ability == null:
		return false
	var other := _nearest_other(me, players)
	if other == null:
		return false
	var dist: float = other.global_position.distance_to(me.global_position)
	var it: bool = me.is_it()
	match me.player_class.primary_ability.id:
		"blink":
			# Teleport: close the gap as hunter, bolt clear as prey.
			return dist < 260.0 if it else dist < 180.0
		"swap":
			# Trade places: as hunter, snap onto prey from just out of reach;
			# as prey, only worth it with a third player to swap toward.
			if it:
				return dist > 70.0 and dist < SwapAbility.RANGE
			return players.size() > 2 and dist < 150.0
		"stun":
			# Freeze: only when someone's actually in the blast radius.
			return dist < StunAbility.RADIUS - 10.0
		"rewind":
			# Snap to the past: an escape, so fire it cornered as prey.
			return not it and dist < 150.0
		"doppel":
			# Decoy + vanish: break an active chase as prey.
			return not it and dist < 230.0
		"build":
			# Conjure a ledge: an escape upward, used as prey when pressed.
			return not it and dist < 170.0
		"dash":
			return dist < 300.0
	return false


static func _nearest_other(me: Node, players: Array) -> Node:
	var best: Node = null
	var nearest := INF
	for p in players:
		if p == me:
			continue
		var d: float = p.global_position.distance_to(me.global_position)
		if d < nearest:
			nearest = d
			best = p
	return best


static func _hunter(me: Node, players: Array) -> Node:
	for p in players:
		if p != me and p.is_it():
			return p
	return null
