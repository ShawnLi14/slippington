class_name MatchDirector
extends Node
## Host-only match referee: validates tag claims, runs the round timer and
## scoring. Runs nowhere else — clients learn everything via GameState RPCs.
##
## Tag detection happens on the "it" player's own client (true position vs.
## the puppets it sees) so tags land exactly when the chaser sees contact;
## this node arbitrates the claims: only the real "it" can tag, the freshly
## tagged player gets a short immunity window so contact doesn't ping-pong
## the tag, and the claim must be plausible from the host's view of both
## players (generous bound to absorb replication lag).

## Host-side sanity bound on a claimed tag. The claimant's position is up
## to ~150ms stale on the host; at top speed that's ~60px on each player.
const CLAIM_MAX_DISTANCE := 140.0

var game: Node2D  # the Game scene, used to look up player nodes

var _immune_peer := -1
var _immune_until_ms := 0
var _match_duration := GameConfig.MATCH_DURATION_SEC
var _remaining := GameConfig.MATCH_DURATION_SEC
var _last_broadcast_second := -1


func _ready() -> void:
	GameState.match_director = self
	# Test hook: integration tests shorten the match (--match-seconds=N).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--match-seconds="):
			_match_duration = float(arg.trim_prefix("--match-seconds="))


func _exit_tree() -> void:
	if GameState.match_director == self:
		GameState.match_director = null


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or GameState.phase != GameState.Phase.PLAYING:
		return
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


## A peer (or the host player locally) claims it tagged target_peer.
func handle_claim(claimant: int, target_peer: int) -> void:
	if GameState.phase != GameState.Phase.PLAYING:
		return
	if claimant != GameState.it_peer or claimant == target_peer:
		return
	if not GameState.players.has(target_peer):
		return
	if target_peer == _immune_peer and Time.get_ticks_msec() < _immune_until_ms:
		return
	var a: Player = game.get_player_node(claimant)
	var b: Player = game.get_player_node(target_peer)
	if a == null or b == null:
		return
	if a.global_position.distance_to(b.global_position) > CLAIM_MAX_DISTANCE:
		return
	_transfer_tag(claimant, target_peer)


func _transfer_tag(from_peer: int, to_peer: int) -> void:
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
