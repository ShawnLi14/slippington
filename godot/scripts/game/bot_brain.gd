class_name BotBrain
extends Node
## Drives its parent Player like a basic chaser: run at the nearest other
## player, hop when they're above or occasionally to clear terrain. Used by
## practice mode (the bot never stops, never uses abilities).

var move_dir := 0.0

var _jump_queued := false
var _jump_cooldown := 0.0


func _physics_process(delta: float) -> void:
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	var me := get_parent() as Player
	if me == null:
		return
	var target: Player = null
	var nearest := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == me:
			continue
		var d: float = p.global_position.distance_to(me.global_position)
		if d < nearest:
			nearest = d
			target = p
	if target == null:
		move_dir = 0.0
		return
	var dx := target.global_position.x - me.global_position.x
	move_dir = 0.0 if absf(dx) < 8.0 else signf(dx)
	if me.is_on_floor() and _jump_cooldown <= 0.0 \
			and (target.global_position.y < me.global_position.y - 60.0 or randf() < 0.008):
		_jump_queued = true
		_jump_cooldown = 0.7


## One-shot: true once per queued jump (mirrors is_action_just_pressed).
func poll_jump() -> bool:
	var j := _jump_queued
	_jump_queued = false
	return j
