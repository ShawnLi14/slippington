class_name BotPolicy
extends RefCounted
## Decides WHERE a bot wants to be; BotNavigator decides how to get there.
## As "it" the goal leads the prey (cut it off, don't tail it); as prey the
## goal is an escape surface that's far from the hunter, not a dead end, and
## biased upward so chases go vertical (where the juking happens). Evade goals
## are recomputed on a cadence and held, so the bot commits to a route instead
## of dithering every frame.

const EVADE_REPLAN := 0.4

var _evade_goal := Vector2.ZERO
var _evade_cd := 0.0


## The point this bot should head for this frame. players = game.get_player_nodes().
func decide_goal(me: Node, players: Array, graph: Dictionary, delta: float) -> Vector2:
	if me.is_it():
		var prey := _nearest_other(me, players)
		if prey == null:
			return me.global_position
		return chase_goal(me, prey)
	var hunter := _hunter(me, players)
	if hunter == null:
		return me.global_position
	_evade_cd -= delta
	if _evade_cd <= 0.0 or _evade_goal == Vector2.ZERO:
		_evade_cd = EVADE_REPLAN
		_evade_goal = evade_goal(me.global_position, hunter.global_position, graph)
	return _evade_goal


## Lead the prey by a little of its current velocity so the chaser arrives
## where the prey is going, scaled by how far off it is.
static func chase_goal(me: Node, prey: Node) -> Vector2:
	var dist: float = me.global_position.distance_to(prey.global_position)
	var lead: float = clampf(dist / GameConfig.PLAYER_SPEED, 0.0, 0.55)
	return prey.global_position + prey.velocity * lead


## Pick the surface that best gets away from the hunter: far from it, not too
## far from us (so we can actually reach it), penalise cut-vertex dead ends,
## and lightly favour height.
static func evade_goal(me_pos: Vector2, hunter_pos: Vector2, graph: Dictionary) -> Vector2:
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
