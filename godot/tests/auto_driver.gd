extends Node
## Headless integration-test bot. Activated when the game is launched with
## user args, e.g.:
##   godot --headless -- --auto=host --port=7799
##   godot --headless -- --auto=join --port=7799
##   godot --headless -- --auto=host-online --code-file=C:/tmp/code.txt --signaling=ws://127.0.0.1:9080
##   godot --headless -- --auto=join-online --code-file=C:/tmp/code.txt --signaling=ws://127.0.0.1:9080
##
## The host bot walks toward the other player to force a tag; the join bot
## stands still. Each process prints PASS/FAIL lines for its own checks and
## exits 0/1, so two of these running together verify connect → lobby →
## roster sync → spawn → movement replication → tag transfer → timer start.

const TIMEOUT_SEC := 40.0

var mode := ""
var port := 7799
var code_file := ""

var _elapsed := 0.0
var _checks: Dictionary = {}
var _started_game := false
var _used_ability := false
var _done := false


func _release_all() -> void:
	for action in ["move_left", "move_right", "ability_primary"]:
		Input.action_release(action)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto="):
			mode = arg.trim_prefix("--auto=")
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--code-file="):
			code_file = arg.trim_prefix("--code-file=")
		elif arg.begins_with("--signaling="):
			NetworkManager.signaling_url = arg.trim_prefix("--signaling=")

	var is_host := mode.begins_with("host")
	_checks = {
		"session": false,
		"roster_2_players": false,
		"playing_phase": false,
		"it_changed": false,
		"timer_started": false,
		"ability_fired": false,
		"match_ended": false,
	}
	if not is_host:
		_checks["remote_moved"] = false
		_checks["remote_ability"] = false

	GameState.local_name = "HostBot" if is_host else "JoinBot"
	GameState.local_class_id = "bolt" if is_host else "anchor"

	NetworkManager.session_started.connect(func(): _pass("session"))
	NetworkManager.session_failed.connect(func(reason): _fail("session failed: " + reason))
	GameState.players_changed.connect(_on_players_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.it_changed.connect(func(new_it, old_it):
		_pass("it_changed")
		print("[bot %s] tag: %d -> %d" % [mode, old_it, new_it])
	)
	GameState.match_started.connect(func(_remaining): _pass("timer_started"))
	GameState.ability_fired.connect(func(peer_id, ability_id):
		_pass("ability_fired")
		if peer_id != multiplayer.get_unique_id():
			_pass("remote_ability")
		print("[bot %s] ability: %d used %s" % [mode, peer_id, ability_id])
	)
	GameState.match_ended.connect(func(results):
		_pass("match_ended")
		print("[bot %s] results: %s" % [mode, JSON.stringify(results)])
	)
	NetworkManager.hosted_online.connect(_on_hosted_online)

	match mode:
		"shot-menu":
			_take_screenshot(1.0)
			return
		"shot-game":
			# Solo game directly into PLAYING to capture map + HUD.
			NetworkManager.host_lan(port)
			GameState.host_start_game("arena")
			_take_screenshot(1.5)
			return
		"host":
			NetworkManager.host_lan(port)
		"join":
			await get_tree().create_timer(1.5).timeout
			NetworkManager.join_lan("127.0.0.1", port)
		"host-online":
			NetworkManager.host_online()
		"join-online":
			_poll_code_file()


func _take_screenshot(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var main := get_tree().root.get_node("Main")
	if main is Control:
		print("[shot] main rect: ", main.get_global_rect(), " anchors: ", main.anchor_right, ",", main.anchor_bottom)
	var screen: Node = null
	for c in main.get_children():
		if c is Control:
			screen = c
	if screen != null:
		print("[shot] screen rect: ", screen.get_global_rect(), " viewport: ", get_viewport().get_visible_rect())
		for child in screen.get_children():
			if child is Control:
				print("[shot]   child %s rect: %s" % [child.get_class(), child.get_global_rect()])
	var img := get_viewport().get_texture().get_image()
	img.save_png(code_file if code_file != "" else "user://shot.png")
	print("[bot] screenshot saved")
	get_tree().quit(0)


func _on_hosted_online(code: String) -> void:
	if code_file != "":
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		print("[bot] wrote code %s" % code)


func _poll_code_file() -> void:
	for i in 20:
		await get_tree().create_timer(0.5).timeout
		if FileAccess.file_exists(code_file):
			var code := FileAccess.get_file_as_string(code_file).strip_edges()
			if code.length() == 5:
				print("[bot] joining with code %s" % code)
				NetworkManager.join_online(code)
				return
	_fail("never found code file")


func _on_players_changed() -> void:
	if GameState.players.size() >= 2:
		_pass("roster_2_players")
	if mode.begins_with("host") and GameState.phase == GameState.Phase.LOBBY \
			and GameState.players.size() >= 2 and not _started_game:
		var all_ready := true
		for id in GameState.players:
			if not GameState.players[id]["ready"]:
				all_ready = false
		if all_ready:
			_started_game = true
			print("[bot] starting game")
			NetworkManager.close_signaling()
			GameState.host_start_game("arena")


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.LOBBY and not mode.begins_with("host"):
		GameState.submit_ready(true)
	elif phase == GameState.Phase.PLAYING:
		_pass("playing_phase")


func _physics_process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SEC:
		_finish()
		return

	if GameState.phase != GameState.Phase.PLAYING:
		_release_all()
		# After the match ends, every check should be in — wrap up.
		if GameState.phase == GameState.Phase.ENDED and _checks["match_ended"]:
			_finish()
		return
	var game := get_tree().root.get_node_or_null("Main/Screen") as Game
	if game == null:
		return

	# Fire the class ability once the match is underway.
	if GameState.match_running and not _used_ability:
		_used_ability = true
		Input.action_press("ability_primary")
	elif _used_ability:
		Input.action_release("ability_primary")

	if mode.begins_with("host"):
		# Walk toward the nearest other player to force a tag.
		var me := game.local_player()
		var target: Player = null
		for p in game.get_player_nodes():
			if p.peer_id != me.peer_id:
				target = p
		if me == null or target == null:
			return
		if target.global_position.x > me.global_position.x + 10.0:
			Input.action_press("move_right")
			Input.action_release("move_left")
		elif target.global_position.x < me.global_position.x - 10.0:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")
	else:
		# Join bot: verify the host's pawn actually moves on our screen.
		for p in game.get_player_nodes():
			if p.peer_id != multiplayer.get_unique_id():
				if not p.global_position.is_equal_approx(Vector2(300, 1020)) \
						and p.global_position.distance_to(Vector2(300, 1020)) > 50.0:
					_pass("remote_moved")

	# Success: everything checked — wind down early.
	var all_passed := true
	for k in _checks:
		if not _checks[k]:
			all_passed = false
	if all_passed and _elapsed > 8.0:
		_finish()


func _pass(check: String) -> void:
	if _checks.has(check) and not _checks[check]:
		_checks[check] = true
		print("[bot %s] PASS %s" % [mode, check])


func _fail(reason: String) -> void:
	print("[bot %s] FAIL %s" % [mode, reason])
	_done = true
	get_tree().quit(1)


func _finish() -> void:
	_done = true
	var failed := []
	for k in _checks:
		if not _checks[k]:
			failed.append(k)
	if failed.is_empty():
		print("[bot %s] ALL CHECKS PASSED" % mode)
		get_tree().quit(0)
	else:
		print("[bot %s] FAILED CHECKS: %s" % [mode, ", ".join(failed)])
		get_tree().quit(1)
