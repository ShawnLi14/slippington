class_name MatchDirector
extends Node
## Host-only match rules: tag detection, the round timer and scoring.
## Runs nowhere else — clients learn everything via GameState RPC broadcasts.
##
## Tagging is edge-triggered (you must leave tag range and re-enter to tag
## again) and the freshly tagged player gets a short immunity window so two
## players brushing past each other don't ping-pong the tag.

var game: Node2D  # the Game scene, used to look up player nodes

var _colliding: Dictionary = {}      # peer_id -> true while inside tag range
var _immune_peer := -1
var _immune_until_ms := 0
var _match_duration := GameConfig.MATCH_DURATION_SEC
var _remaining := GameConfig.MATCH_DURATION_SEC
var _last_broadcast_second := -1


func _ready() -> void:
	# Test hook: integration tests shorten the match (--match-seconds=N).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--match-seconds="):
			_match_duration = float(arg.trim_prefix("--match-seconds="))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or GameState.phase != GameState.Phase.PLAYING:
		return

	_check_tags()

	if GameState.match_running:
		var it := GameState.it_peer
		if GameState.players.has(it):
			GameState.players[it]["time_as_it"] += delta
		_remaining -= delta
		var whole_second := int(ceil(_remaining))
		if whole_second != _last_broadcast_second:
			_last_broadcast_second = whole_second
			GameState.timer_synced.rpc(maxf(0.0, _remaining))
		if _remaining <= 0.0:
			_end_match()


func _check_tags() -> void:
	var it_node: Player = game.get_player_node(GameState.it_peer)
	if it_node == null:
		return
	var now := Time.get_ticks_msec()
	for other in game.get_player_nodes():
		if other.peer_id == it_node.peer_id:
			continue
		var in_range := it_node.global_position.distance_to(other.global_position) < GameConfig.TAG_RANGE
		if in_range:
			if not _colliding.has(other.peer_id):
				_colliding[other.peer_id] = true
				var immune: bool = other.peer_id == _immune_peer and now < _immune_until_ms
				if not immune:
					_transfer_tag(it_node.peer_id, other.peer_id)
					return
		else:
			_colliding.erase(other.peer_id)


func _transfer_tag(from_peer: int, to_peer: int) -> void:
	_colliding.clear()
	_immune_peer = from_peer  # the old "it" can't be tagged right back
	_immune_until_ms = Time.get_ticks_msec() + int(GameConfig.TAG_IMMUNITY_SEC * 1000.0)
	GameState.set_it.rpc(to_peer, from_peer)
	if not GameState.match_running:
		_remaining = _match_duration
		GameState.timer_started.rpc(_remaining)


func _end_match() -> void:
	var ranked: Array = []
	for id in GameState.players:
		var p: Dictionary = GameState.players[id]
		ranked.append({
			"peer_id": id,
			"name": p["name"],
			"time_as_it": p["time_as_it"],
			"was_it_at_end": id == GameState.it_peer,
			"color_index": p["color_index"],
		})
	# Least time as "it" wins; whoever held the tag at zero sorts last on ties.
	ranked.sort_custom(func(a, b):
		if a["was_it_at_end"] != b["was_it_at_end"]:
			return b["was_it_at_end"]
		if a["time_as_it"] != b["time_as_it"]:
			return a["time_as_it"] < b["time_as_it"]
		return a["peer_id"] < b["peer_id"]
	)
	GameState.end_match.rpc(ranked)
