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

## Lag compensation: a claim is validated against where the TARGET was on
## the claimant's screen — the target's host-side history rewound by the
## claimant's RTT plus the interpolation delay — never further back than
## this cap (the industry-standard bound: Overwatch/Battlefield use 250ms).
## High-ping claimants get clamped and must lead their target, exactly like
## high-ping shooters in an FPS.
const MAX_REWIND := 0.25
## Contact box for host validation: the sprites' size plus a little slack
## for measurement noise (client claims already require deeper contact).
const VALIDATE_CONTACT_SIZE := GameConfig.PLAYER_SIZE * 1.2
## Anti-garbage bound: the claimed position must be near where the host
## believes the claimant is (their puppet lags by ~RTT + interp).
const CLAIMANT_POS_TOLERANCE := 150.0

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


## A peer (or the host player locally) claims it tagged target_peer at
## claimant_pos while rendering the target interp_delay in the past.
## Validated with bounded lag compensation: was the target actually within
## contact range of that position, on the claimant's screen?
func handle_claim(claimant: int, target_peer: int, claimant_pos: Vector2, interp_delay: float) -> void:
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
	# The claimed position must roughly match the host's view of the claimant.
	if a.global_position.distance_to(claimant_pos) > CLAIMANT_POS_TOLERANCE:
		return
	# Rewind the target to the moment the claimant saw: its position packets
	# took ~RTT/2 each way through the host relay plus the claim's own
	# transit, i.e. one full claimant RTT, plus the claimant's actual render
	# delay for this target (adaptive, so it's sent with the claim; clamped
	# to its legal range as an anti-garbage measure).
	var rewind: float = minf(
		GameState.get_peer_rtt(claimant) + clampf(interp_delay, Player.DELAY_MIN, Player.DELAY_MAX),
		MAX_REWIND
	)
	var target_then: Vector2 = b.position_at(Time.get_ticks_msec() / 1000.0 - rewind)
	if absf(target_then.x - claimant_pos.x) < VALIDATE_CONTACT_SIZE \
			and absf(target_then.y - claimant_pos.y) < VALIDATE_CONTACT_SIZE:
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
