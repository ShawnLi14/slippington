class_name BotBrain
extends Node
## Drives its parent Player through the navigation graph: paths to the
## nearest other player and chases — climbing structures, taking springs and
## portals, dropping through one-way platforms as the route demands. The
## practice bot is "it" forever, so chasing is its whole job (role behaviour
## and difficulty tuning build on top of this in later phases).
##
## move_dir + poll_jump() + want_drop mirror exactly the inputs Player reads
## from a human, so the pawn can't tell it's being driven by AI.

var move_dir := 0.0
var want_drop := false

var _jump_queued := false
var _nav: BotNavigator
var _policy := BotPolicy.new()


func _physics_process(delta: float) -> void:
	var me := get_parent() as Player
	if me == null:
		return
	var nav := _navigator(me)
	# BotPolicy chooses the goal by role (chase the prey / flee the hunter);
	# the navigator turns that into movement. The practice bot is always "it",
	# so in practice this resolves to a cut-off chase, but the logic is general.
	var goal := _policy.decide_goal(me, get_tree().get_nodes_in_group("players"), nav.graph, delta)
	var cmd := nav.navigate(me, goal, delta)
	move_dir = cmd["move_dir"]
	want_drop = cmd["drop"]
	if cmd["jump"]:
		_jump_queued = true


## One-shot: true once per queued jump (mirrors is_action_just_pressed).
func poll_jump() -> bool:
	var j := _jump_queued
	_jump_queued = false
	return j


func _navigator(me: Player) -> BotNavigator:
	if _nav == null:
		_nav = BotNavigator.new((me.get_parent() as Game).get_nav_graph())
	return _nav
