extends Node
## GameState autoload: session phase machine, the replicated player roster,
## and every game-flow RPC. Autoloads have identical node paths on all peers,
## which makes them the natural home for RPCs.
##
## Authority model: the host (peer 1) owns the roster, tag state, match timer
## and scoring. Clients send requests up; the host broadcasts truth down.

enum Phase { MENU, LOBBY, PLAYING, ENDED }

signal phase_changed(phase: Phase)
signal players_changed
signal it_changed(new_it: int, old_it: int)
signal match_started(remaining: float)
signal match_timer_updated(remaining: float)
signal match_ended(results: Array)
signal stunned(duration: float)
signal ability_fired(peer_id: int, ability_id: String)
signal player_left_game(peer_id: int)
signal status_message(text: String)

const ABILITY_COOLDOWN_TOLERANCE_MS := 250

var phase: Phase = Phase.MENU
var local_name := "Player"
var local_class_id := "slipper"

## peer_id -> {name, class_id, ready, color_index, is_it, time_as_it}
var players: Dictionary = {}
var it_peer := -1
var map_seed := ""
var match_running := false
var match_remaining := 0.0
var results: Array = []

var _host_ability_last_use: Dictionary = {}  # peer_id -> {ability_id: msec}
var _next_color := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_host() -> bool:
	return multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


func _set_phase(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


# --- session lifecycle -------------------------------------------------------

## Called by NetworkManager once we are in a session (hosting or joined).
func enter_lobby() -> void:
	if is_host():
		players.clear()
		_next_color = 0
		_host_add_player(1, local_name, local_class_id)
	else:
		register_player.rpc_id(1, local_name, local_class_id)
	_set_phase(Phase.LOBBY)


## Local hard reset back to the menu (connection lost, left voluntarily...).
func reset_to_menu(message := "") -> void:
	players.clear()
	results.clear()
	it_peer = -1
	map_seed = ""
	match_running = false
	match_remaining = 0.0
	_host_ability_last_use.clear()
	_set_phase(Phase.MENU)
	if message != "":
		status_message.emit(message)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	if players.has(peer_id):
		players.erase(peer_id)
		_host_ability_last_use.erase(peer_id)
		# If "it" left mid-match, hand the tag to an arbitrary survivor.
		if it_peer == peer_id and phase == Phase.PLAYING and not players.is_empty():
			set_it.rpc(players.keys()[0], -1)
		sync_roster.rpc(players)
		peer_removed.rpc(peer_id)


# --- lobby: client -> host ---------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func register_player(p_name: String, class_id: String) -> void:
	if not is_host():
		return
	_host_add_player(multiplayer.get_remote_sender_id(), p_name, class_id)


@rpc("any_peer", "call_remote", "reliable")
func set_player_info(p_name: String, class_id: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["name"] = p_name
		players[sender]["class_id"] = class_id
		sync_roster.rpc(players)


@rpc("any_peer", "call_remote", "reliable")
func set_ready(ready: bool) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ready"] = ready
		sync_roster.rpc(players)


## Local-friendly wrappers so the host player uses the same code path.
func submit_player_info(p_name: String, class_id: String) -> void:
	local_name = p_name
	local_class_id = class_id
	if is_host():
		if players.has(1):
			players[1]["name"] = p_name
			players[1]["class_id"] = class_id
			sync_roster.rpc(players)
	else:
		set_player_info.rpc_id(1, p_name, class_id)


func submit_ready(ready: bool) -> void:
	if is_host():
		if players.has(1):
			players[1]["ready"] = ready
			sync_roster.rpc(players)
	else:
		set_ready.rpc_id(1, ready)


func _host_add_player(peer_id: int, p_name: String, class_id: String) -> void:
	if players.size() >= GameConfig.MAX_PLAYERS:
		return
	players[peer_id] = {
		"name": p_name if p_name != "" else "Player %d" % peer_id,
		"class_id": class_id,
		"ready": peer_id == 1,  # host is implicitly ready
		"color_index": _next_color % GameConfig.PLAYER_COLORS.size(),
		"is_it": false,
		"time_as_it": 0.0,
	}
	_next_color += 1
	sync_roster.rpc(players)


# --- lobby/roster: host -> all -----------------------------------------------

@rpc("authority", "call_local", "reliable")
func sync_roster(roster: Dictionary) -> void:
	players = roster
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func peer_removed(peer_id: int) -> void:
	player_left_game.emit(peer_id)
	players_changed.emit()


# --- match flow: host -> all -------------------------------------------------

## Host-only entry point from the lobby Start button.
func host_start_game(map_choice: String) -> void:
	if not is_host():
		return
	var seed_str := map_choice
	if seed_str == "random":
		seed_str = "%d_%06d" % [Time.get_ticks_msec(), randi() % 1000000]
	for id in players:
		players[id]["is_it"] = id == 1
		players[id]["time_as_it"] = 0.0
		players[id]["ready"] = id == 1
	_host_ability_last_use.clear()
	start_game.rpc(seed_str, players)


@rpc("authority", "call_local", "reliable")
func start_game(seed_str: String, roster: Dictionary) -> void:
	players = roster
	map_seed = seed_str
	match_running = false
	match_remaining = GameConfig.MATCH_DURATION_SEC
	results.clear()
	it_peer = 1
	_set_phase(Phase.PLAYING)


@rpc("authority", "call_local", "reliable")
func set_it(new_it: int, old_it: int) -> void:
	for id in players:
		players[id]["is_it"] = id == new_it
	it_peer = new_it
	it_changed.emit(new_it, old_it)


@rpc("authority", "call_local", "reliable")
func timer_started(remaining: float) -> void:
	match_running = true
	match_remaining = remaining
	match_started.emit(remaining)


@rpc("authority", "call_local", "reliable")
func timer_synced(remaining: float) -> void:
	match_remaining = remaining
	match_timer_updated.emit(remaining)


@rpc("authority", "call_local", "reliable")
func end_match(ranked_results: Array) -> void:
	match_running = false
	results = ranked_results
	_set_phase(Phase.ENDED)
	match_ended.emit(ranked_results)


## Host-only: Play Again from the end screen.
func host_return_to_lobby() -> void:
	if not is_host():
		return
	do_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func do_return_to_lobby() -> void:
	for id in players:
		players[id]["is_it"] = false
		players[id]["time_as_it"] = 0.0
		players[id]["ready"] = id == 1
	it_peer = -1
	match_running = false
	results.clear()
	_set_phase(Phase.LOBBY)
	players_changed.emit()


# --- tagging -----------------------------------------------------------------

## Set by the host's MatchDirector while a match is running; it arbitrates
## tag claims (immunity, plausibility) and owns the timer/scoring.
var match_director: Node = null


## Called by the local "it" player when it detects contact.
func claim_tag_local(target_peer: int, my_pos: Vector2) -> void:
	if is_host():
		_host_handle_claim(1, target_peer, my_pos)
	else:
		claim_tag.rpc_id(1, target_peer, my_pos)


@rpc("any_peer", "call_remote", "reliable")
func claim_tag(target_peer: int, claimant_pos: Vector2) -> void:
	if not is_host():
		return
	_host_handle_claim(multiplayer.get_remote_sender_id(), target_peer, claimant_pos)


func _host_handle_claim(claimant: int, target_peer: int, claimant_pos: Vector2) -> void:
	if match_director != null:
		match_director.handle_claim(claimant, target_peer, claimant_pos)


# --- RTT measurement (host pings peers; used for lag-compensated claims) ------

var _peer_rtt: Dictionary = {}  # peer_id -> seconds (EMA)
var _ping_accumulator := 0.0


func _process(delta: float) -> void:
	if not is_host() or multiplayer.multiplayer_peer == null:
		return
	_ping_accumulator += delta
	if _ping_accumulator >= 1.0:
		_ping_accumulator = 0.0
		for peer_id in multiplayer.get_peers():
			ping.rpc_id(peer_id, Time.get_ticks_msec())


@rpc("authority", "call_remote", "unreliable")
func ping(host_ms: int) -> void:
	pong.rpc_id(1, host_ms)


@rpc("any_peer", "call_remote", "unreliable")
func pong(host_ms: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var rtt := float(Time.get_ticks_msec() - host_ms) / 1000.0
	var prev: float = _peer_rtt.get(sender, rtt)
	_peer_rtt[sender] = lerpf(prev, rtt, 0.3)


## Host-side estimate of a peer's round-trip time (0 for the host itself).
func get_peer_rtt(peer_id: int) -> float:
	return _peer_rtt.get(peer_id, 0.0)


# --- abilities ---------------------------------------------------------------

## Called by the local player right after optimistically executing an ability.
func report_ability_used(ability_id: String) -> void:
	if is_host():
		_host_handle_ability(1, ability_id)
	else:
		request_ability.rpc_id(1, ability_id)


@rpc("any_peer", "call_remote", "reliable")
func request_ability(ability_id: String) -> void:
	if not is_host():
		return
	_host_handle_ability(multiplayer.get_remote_sender_id(), ability_id)


func _host_handle_ability(peer_id: int, ability_id: String) -> void:
	var player_class := ClassRegistry.get_class_by_id(players.get(peer_id, {}).get("class_id", "slipper"))
	var ability := player_class.primary_ability
	if ability == null or ability.id != ability_id:
		return
	var now := Time.get_ticks_msec()
	var last: int = _host_ability_last_use.get(peer_id, {}).get(ability_id, -(1 << 40))
	if now < last + int(ability.cooldown_sec * 1000.0) - ABILITY_COOLDOWN_TOLERANCE_MS:
		return  # too soon — drop silently, owner already played it locally
	if not _host_ability_last_use.has(peer_id):
		_host_ability_last_use[peer_id] = {}
	_host_ability_last_use[peer_id][ability_id] = now
	ability_executed.rpc(peer_id, ability_id)


@rpc("authority", "call_local", "reliable")
func ability_executed(peer_id: int, ability_id: String) -> void:
	ability_fired.emit(peer_id, ability_id)


@rpc("any_peer", "call_remote", "reliable")
func apply_stun(duration: float) -> void:
	stunned.emit(duration)
