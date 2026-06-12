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

var timeout_sec := 40.0

var mode := ""
var port := 7799
var code_file := ""
## "simple" = deterministic regression bots (chase when it, stand still
## otherwise). "smart" = playtest bots: flee, jump, use abilities — produces
## meaningful telemetry instead of pass/fail checks.
var bot_style := "simple"
var bot_class := ""

var map_choice := "arena"

var _jump_cooldown := 0.0
var _ability_timer := 0.0

var _elapsed := 0.0
var _checks: Dictionary = {}
var _started_game := false
var _own_ability_done := false
var _ability_frame := 0
var _tag_count := 0
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
		elif arg.begins_with("--bot-style="):
			bot_style = arg.trim_prefix("--bot-style=")
		elif arg.begins_with("--map="):
			map_choice = arg.trim_prefix("--map=")
		elif arg.begins_with("--class="):
			bot_class = arg.trim_prefix("--class=")
		elif arg.begins_with("--match-seconds="):
			# The clock only starts at the first tag — leave generous slack.
			timeout_sec = float(arg.trim_prefix("--match-seconds=")) + 45.0

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
	# At least 2 tags must land: the first comes from the host bot, the
	# tag-back from the client bot — proving remote tag claims register.
	_checks["tag_back"] = false

	GameState.local_name = "HostBot" if is_host else "JoinBot"
	GameState.local_class_id = "swapper" if is_host else "anchor"
	if bot_class != "":
		GameState.local_class_id = bot_class
		GameState.local_name = bot_class.capitalize() + ("H" if is_host else "J")

	NetworkManager.session_started.connect(func(): _pass("session"))
	if mode != "join-bad-online":
		# (join-bad-online expects its first attempt to fail.)
		NetworkManager.session_failed.connect(func(reason): _fail("session failed: " + reason))
	GameState.players_changed.connect(_on_players_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.it_changed.connect(func(new_it, old_it):
		_pass("it_changed")
		_tag_count += 1
		if _tag_count >= 2:
			_pass("tag_back")
		print("[bot %s] tag: %d -> %d" % [mode, old_it, new_it])
		# Visual-check mode: capture the tag presentation mid-effect.
		if mode == "host" and code_file.ends_with(".png") and _tag_count == 2:
			_take_screenshot(0.12)
	)
	GameState.match_started.connect(func(_remaining): _pass("timer_started"))
	GameState.ability_fired.connect(func(peer_id, ability_id):
		_pass("ability_fired")
		if peer_id != multiplayer.get_unique_id():
			_pass("remote_ability")
		else:
			_own_ability_done = true
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
		"shot-lobby":
			# Fake a populated online lobby (no network) to render the code
			# panel, player rows and pickers.
			NetworkManager.join_code = "ABC12"
			NetworkManager.is_host = true
			GameState.enter_lobby()
			GameState.players[2] = {"name": "Maya", "class_id": "swapper", "ready": true, "color_index": 1, "is_it": false, "time_as_it": 0.0}
			GameState.players[3] = {"name": "Sam", "class_id": "anchor", "ready": false, "color_index": 2, "is_it": false, "time_as_it": 0.0}
			GameState.players[4] = {"name": "Riko", "class_id": "slipper", "ready": true, "color_index": 3, "is_it": false, "time_as_it": 0.0}
			GameState.players_changed.emit()
			_take_screenshot(1.0)
			return
		"shot-game":
			# Solo game directly into PLAYING to capture map + HUD.
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
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
		"join-bad-online":
			# Regression: joining a nonexistent code must fail cleanly and
			# leave the client able to join a real game afterwards.
			NetworkManager.session_failed.connect(_on_bad_join_failed)
			NetworkManager.join_online("ZZZZ9")


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


var _bad_join_done := false


func _on_bad_join_failed(reason: String) -> void:
	if _bad_join_done:
		_fail("second join also failed: " + reason)
		return
	_bad_join_done = true
	print("[bot] bad code rejected as expected (%s), joining real game" % reason)
	_poll_code_file()


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
			GameState.host_start_game(map_choice, 1)  # host starts "it": bots assume it


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.LOBBY and not mode.begins_with("host"):
		GameState.submit_ready(true)
	elif phase == GameState.Phase.PLAYING:
		_pass("playing_phase")


func _physics_process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > timeout_sec:
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

	if bot_style == "smart":
		_smart_move(game, delta)
		return

	# Fire the class ability once the match is underway. Retry with fresh
	# presses until it registers — a press can land during tag hit-stop.
	if GameState.match_running and not _own_ability_done:
		_ability_frame += 1
		if _ability_frame % 12 == 1:
			Input.action_press("ability_primary")
		else:
			Input.action_release("ability_primary")
	else:
		Input.action_release("ability_primary")

	# Whoever is "it" chases the other player; everyone else stands still.
	# With contact re-tagging after immunity, the tag ping-pongs — exercising
	# tag claims from BOTH the host and the remote client.
	var me := game.local_player()
	if me == null:
		return
	if me.is_it():
		var target: Player = null
		for p in game.get_player_nodes():
			if p.peer_id != me.peer_id:
				target = p
		if target == null:
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
		Input.action_release("move_left")
		Input.action_release("move_right")

	if not mode.begins_with("host"):
		# Join bot: verify the host's pawn actually moves on our screen.
		for p in game.get_player_nodes():
			if p.peer_id != multiplayer.get_unique_id():
				if p.global_position.distance_to(Vector2(300, 1020)) > 50.0:
					_pass("remote_moved")

	# Success: everything checked — wind down early.
	var all_passed := true
	for k in _checks:
		if not _checks[k]:
			all_passed = false
	if all_passed and _elapsed > 8.0:
		_finish()


## Playtest bot: chase with jumps when "it"; flee, jump and panic-ability
## when hunted. Produces realistic-ish chases for telemetry.
func _smart_move(game: Game, delta: float) -> void:
	var me := game.local_player()
	if me == null:
		return
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	_ability_timer += delta
	Input.action_release("jump")

	var it_id := GameState.it_peer
	if me.is_it():
		var target: Player = null
		var nearest := INF
		for p in game.get_player_nodes():
			if p.peer_id == me.peer_id:
				continue
			var d: float = p.global_position.distance_to(me.global_position)
			if d < nearest:
				nearest = d
				target = p
		if target == null:
			return
		_run_toward(target.global_position.x, me)
		# Jump if prey is above us, or periodically to clear platforms.
		if me.is_on_floor() and _jump_cooldown <= 0.0 \
				and (target.global_position.y < me.global_position.y - 60.0 or randf() < 0.01):
			Input.action_press("jump")
			_jump_cooldown = 0.6
		if _ability_timer > 2.0 and nearest < 350.0:
			_ability_timer = 0.0
			Input.action_press("ability_primary")
		else:
			Input.action_release("ability_primary")
	else:
		var hunter := game.get_player_node(it_id)
		Input.action_release("ability_primary")
		if hunter == null:
			_stop(me)
			return
		var dist: float = hunter.global_position.distance_to(me.global_position)
		if dist < 520.0:
			# Run away; hop when cornered or when the hunter is close.
			var flee_dir: float = signf(me.global_position.x - hunter.global_position.x)
			if flee_dir == 0.0:
				flee_dir = 1.0
			var cornered: bool = (me.global_position.x < 120.0 and flee_dir < 0.0) \
				or (me.global_position.x > GameConfig.MAP_WIDTH - 120.0 and flee_dir > 0.0)
			if cornered:
				flee_dir = -flee_dir
			_run_dir(flee_dir, me)
			if me.is_on_floor() and _jump_cooldown <= 0.0 and (dist < 180.0 or cornered or randf() < 0.02):
				Input.action_press("jump")
				_jump_cooldown = 0.5
			if dist < 200.0 and _ability_timer > 1.5:
				_ability_timer = 0.0
				Input.action_press("ability_primary")
		else:
			_stop(me)


func _run_toward(x: float, me: Player) -> void:
	if x > me.global_position.x + 12.0:
		_run_dir(1.0, me)
	elif x < me.global_position.x - 12.0:
		_run_dir(-1.0, me)
	else:
		_stop(me)


func _run_dir(dir: float, _me: Player) -> void:
	if dir > 0.0:
		Input.action_press("move_right")
		Input.action_release("move_left")
	else:
		Input.action_press("move_left")
		Input.action_release("move_right")


func _stop(_me: Player) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


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
	if bot_style == "smart":
		# Playtest runs are for telemetry, not pass/fail.
		print("[bot %s] smart playtest complete" % mode)
		get_tree().quit(0)
		return
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
