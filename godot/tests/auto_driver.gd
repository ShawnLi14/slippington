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
var shot_event := "tag"
var forced_landmark := ""
var rounds_arg := 1
var forced_version := ""
var _playing_entries := 0

var _jump_cooldown := 0.0
var _ability_timer := 0.0

var _elapsed := 0.0
var _checks: Dictionary = {}
var _started_game := false
var _own_ability_done := false
var _ability_frame := 0
var _tag_count := 0
var _done := false

# host-swap mode state (scripted Swap correctness test).
var _swap_state := "approach"
var _swap_at := 0.0
var _swap_pre_me := Vector2.ZERO
var _swap_pre_other := Vector2.ZERO
var _swap_cast_done := false
var _swap_self_tagged := false


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
		elif arg.begins_with("--shot-event="):
			shot_event = arg.trim_prefix("--shot-event=")
		elif arg.begins_with("--landmark="):
			forced_landmark = arg.trim_prefix("--landmark=")
		elif arg.begins_with("--rounds="):
			rounds_arg = int(arg.trim_prefix("--rounds="))
			timeout_sec = maxf(timeout_sec, float(rounds_arg) * (timeout_sec * 0.6) + 30.0)
		elif arg.begins_with("--force-version="):
			forced_version = arg.trim_prefix("--force-version=")
		elif arg.begins_with("--class="):
			bot_class = arg.trim_prefix("--class=")
		elif arg.begins_with("--connect-timeout="):
			NetworkManager.connect_timeout_sec = float(arg.trim_prefix("--connect-timeout="))
		elif arg == "--force-relay":
			# Exercise the TURN relay path: ignore host/reflexive candidates.
			NetworkManager.force_relay = true
		elif arg.begins_with("--match-seconds="):
			# The clock only starts at the first tag — leave generous slack.
			timeout_sec = float(arg.trim_prefix("--match-seconds=")) + 45.0

	if forced_version != "":
		GameState.version_override = forced_version

	if mode == "update-dryrun":
		_run_update_dryrun()
		return

	var is_host := mode.begins_with("host")
	if mode == "host-deaf" or mode == "join-deaf":
		# Watchdog test: the deaf host opens a real room on the signaling
		# server but never answers WebRTC — like a host whose network
		# silently eats P2P traffic. The joiner must get a clear failure
		# message instead of an endless spinner.
		_checks = {"room_hosted": false} if mode == "host-deaf" else {"ice_failure_surfaced": false}
		timeout_sec = 30.0
	elif mode == "host-swap" or mode == "join-swap":
		# Scripted Swap correctness test: the joiner stands still, the host
		# approaches to a meaningful separation (well past tag contact, inside
		# the 300px Swap range), casts, and asserts a true position exchange.
		# No tags ever land, so the normal match checks don't apply.
		_checks = {"session": false, "roster_2_players": false, "playing_phase": false}
		if mode == "host-swap":
			_checks["swap_positions"] = false
			_checks["no_self_tag"] = false
			bot_class = "swapper"
		timeout_sec = 25.0
	elif mode == "host-idle":
		# Minimal reject-capable host for the version-gate test: just stays up.
		_checks = {}
		timeout_sec = 12.0
	elif mode == "join-badversion":
		# Joins with a deliberately-wrong version; must be bounced to the menu.
		_checks = {"got_rejected": false}
		timeout_sec = 20.0
	else:
		_checks = {
			"session": false,
			"roster_2_players": false,
			"playing_phase": false,
			"stood_on_floor": false,  # catches a broken/missing map
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
		if rounds_arg > 1:
			_checks["round2_started"] = false
			_checks["series_ended"] = false

	GameState.local_name = "HostBot" if is_host else "JoinBot"
	GameState.local_class_id = "swapper" if is_host else "anchor"
	if bot_class != "":
		GameState.local_class_id = bot_class
		GameState.local_name = bot_class.capitalize() + ("H" if is_host else "J")

	NetworkManager.session_started.connect(func(): _pass("session"))
	if mode == "join-deaf":
		NetworkManager.session_failed.connect(func(reason):
			print("[bot join-deaf] session_failed surfaced: " + reason)
			if "blocking P2P" in reason:
				_pass("ice_failure_surfaced")
				_finish()
			else:
				_fail("unexpected failure reason: " + reason)
		)
	elif mode != "join-bad-online" and mode != "join-badversion":
		# (join-bad-online expects its first attempt to fail.)
		NetworkManager.session_failed.connect(func(reason): _fail("session failed: " + reason))
	if mode == "join-badversion":
		GameState.status_message.connect(func(text: String):
			if "Version mismatch" in text:
				_pass("got_rejected")
				_finish()
		)
	GameState.players_changed.connect(_on_players_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.it_changed.connect(func(new_it, old_it):
		_pass("it_changed")
		_tag_count += 1
		if _tag_count >= 2:
			_pass("tag_back")
		if mode == "host-swap" and _swap_cast_done:
			_swap_self_tagged = true
			print("[bot host-swap] SELF-TAG after swap: %d -> %d" % [old_it, new_it])
		print("[bot %s] tag: %d -> %d" % [mode, old_it, new_it])
		# Visual-check mode: capture the tag presentation mid-effect.
		if mode == "host" and code_file.ends_with(".png") and shot_event == "tag" and _tag_count == 2:
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
		"shot-update":
			# Inject a fake available update and re-emit so the already-built
			# menu renders its banner, then screenshot.
			Updater.available_update = {
				"version": "9.9.9",
				"notes_url": "https://github.com/ShawnLi14/slippington/releases",
				"asset_url": "https://example/none.zip",
				"asset_size": 1,
			}
			Updater.update_available.emit(Updater.available_update)
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
		"shot-end":
			_done = true  # prevent _physics_process from calling _finish() early
			NetworkManager.is_host = true
			GameState.results = [
				{"peer_id": 1, "name": "You", "color_index": 0, "time_as_it": 3.2, "was_it_at_end": false},
				{"peer_id": 2, "name": "Maya", "color_index": 1, "time_as_it": 7.8, "was_it_at_end": true},
				{"peer_id": 3, "name": "Sam", "color_index": 2, "time_as_it": 5.1, "was_it_at_end": false},
			]
			GameState.rounds_total = 1
			GameState.end_match(GameState.results, {
				"points": {},
				"number": 1,
				"total": 1,
				"final": true,
				"champion": -1,
			})
			_take_screenshot(1.0)
			return
		"shot-practice":
			GameState.local_name = "You"
			GameState.start_practice()
			_take_screenshot(3.0)
			return
		"shot-game":
			# Solo game directly into PLAYING to capture map + HUD.
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			_take_screenshot(1.5)
			return
		"shot-slope":
			# Drop the player onto the first ramp in the map and screenshot so
			# the slope-bank tilt is visible standing still.
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			await get_tree().create_timer(0.5).timeout
			var g := get_tree().root.get_node_or_null("Main/Screen") as Game
			var me := g.local_player() if g != null else null
			for p in g.map_data["platforms"]:
				if p.get("ramp", 0) != 0:
					var r: Rect2 = p["rect"]
					me.global_position = r.position + Vector2(r.size.x / 2.0, -40.0)
					print("[bot] placed on ramp%d at %s" % [p["ramp"], me.global_position])
					break
			await get_tree().create_timer(1.0).timeout
			print("[bot] tilt = %.1f deg" % rad_to_deg(me._tilt))
			_take_screenshot(0.2)
			return
		"shot-ability":
			# Solo game; run, jump, fire the local class ability (--class=)
			# mid-air, then capture its VFX while it's still on screen. Cast
			# WHILE moving — the worst case for reading an ability's visuals.
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			await get_tree().create_timer(1.2).timeout
			Input.action_press("move_right")
			Input.action_press("jump")
			await get_tree().create_timer(0.05).timeout
			Input.action_release("jump")
			await get_tree().create_timer(0.35).timeout
			Input.action_press("ability_primary")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("ability_primary")
			_take_screenshot(0.5)
			return
		"shot-landmark":
			# Pin a landmark into column 0 and screenshot the live map so each
			# new structure can be eyeballed. The forced landmark sits in
			# column 0 (far left), so teleport the player to that column's
			# center first — the camera is player-centered, so this frames the
			# structure instead of leaving it at the edge. Usage:
			#   --auto=shot-landmark --landmark=mill --code-file=mill.png --map=a3-mill
			MapGenerator.force_landmark = forced_landmark
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			await get_tree().create_timer(0.4).timeout
			var lmg := get_tree().root.get_node_or_null("Main/Screen") as Game
			var lmme := lmg.local_player() if lmg != null else null
			if lmg != null and lmme != null:
				# MAP_WIDTH/8 = center of column 0 (4 columns of width MAP_WIDTH/4).
				lmme.global_position = Vector2(GameConfig.MAP_WIDTH / 8.0, 760.0)
				print("[bot] framed landmark at %s" % lmme.global_position)
			await get_tree().create_timer(0.6).timeout
			_take_screenshot(0.3)
			return
		"launch-test":
			# Regression: an angled launcher is vertical-dominant: its sideways
			# throw is NOT held; air control resumes immediately. Launch with no
			# input — velocity.x must collapse to ~0 within a couple frames — if it stayed
			# near the throw, the planner's air-control reach model would be wrong.
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			await get_tree().create_timer(0.5).timeout
			var lg := get_tree().root.get_node_or_null("Main/Screen") as Game
			var lme := lg.local_player() if lg != null else null
			if lme == null:
				print("[bot launch-test] FAIL: no local player")
				get_tree().quit(1)
				return
			# Launch from wherever it spawned (a valid platform); the up-throw
			# carries it airborne, where air control (no input) zeroes velocity.x.
			lme.apply_launch(Vector2(280, -700))
			await get_tree().create_timer(0.2).timeout  # airborne by now
			var lvx: float = lme.velocity.x
			print("[bot launch-test] velocity.x after launch = %.0f (expect ~0, not held)" % lvx)
			if absf(lvx) < 60.0:
				print("[bot launch-test] ALL CHECKS PASSED")
				get_tree().quit(0)
			else:
				print("[bot launch-test] FAIL: horizontal throw was held (vx=%.0f, expected ~0)" % lvx)
				get_tree().quit(1)
			return
		"host", "host-swap":
			NetworkManager.host_lan(port)
		"host-idle":
			NetworkManager.host_lan(port)
		"join-badversion":
			await get_tree().create_timer(1.5).timeout
			NetworkManager.join_lan("127.0.0.1", port)
		"join", "join-swap":
			await get_tree().create_timer(1.5).timeout
			NetworkManager.join_lan("127.0.0.1", port)
		"host-online":
			NetworkManager.host_online()
		"join-online":
			_poll_code_file()
		"host-deaf":
			var sig := SignalingClient.new()
			add_child(sig)
			sig.hosted.connect(func(code, _peer_id, _ice_servers):
				_pass("room_hosted")
				_on_hosted_online(code)
			)
			sig.connect_to(NetworkManager.signaling_url)
			sig.host_room()
		"join-deaf":
			if NetworkManager.connect_timeout_sec > 10.0:
				NetworkManager.connect_timeout_sec = 8.0
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
	if img == null:
		print("[bot] screenshot skipped (headless/null texture)")
	else:
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
	if mode.begins_with("host") and mode != "host-idle" and GameState.phase == GameState.Phase.LOBBY \
			and GameState.players.size() >= 2 and not _started_game:
		var all_ready := true
		for id in GameState.players:
			if not GameState.players[id]["ready"]:
				all_ready = false
		if all_ready:
			_started_game = true
			print("[bot] starting game")
			NetworkManager.close_signaling()
			GameState.host_start_game(map_choice, 1, rounds_arg)  # host starts "it"


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.LOBBY and not mode.begins_with("host"):
		GameState.submit_ready(true)
	elif phase == GameState.Phase.PLAYING:
		_pass("playing_phase")
		_playing_entries += 1
		if _playing_entries >= 2:
			_pass("round2_started")
	elif phase == GameState.Phase.ENDED and GameState.series_final:
		_pass("series_ended")


func _physics_process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > timeout_sec:
		_finish()
		return

	if GameState.phase != GameState.Phase.PLAYING:
		_release_all()
		# After the match (or series) ends, every check should be in.
		if GameState.phase == GameState.Phase.ENDED and _checks["match_ended"] \
				and (rounds_arg == 1 or GameState.series_final):
			_finish()
		return
	var game := get_tree().root.get_node_or_null("Main/Screen") as Game
	if game == null:
		return

	var floor_me := game.local_player()
	if floor_me != null and floor_me.is_on_floor():
		_pass("stood_on_floor")

	if mode == "join-swap":
		# Stand perfectly still as the swap partner; quit once the host has
		# had ample time to run its assertions.
		if _elapsed > 16.0:
			_finish()
		return
	if mode == "host-swap":
		_swap_test_step(game)
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


## Scripted Swap correctness test (host-swap mode). The join-swap partner
## stands perfectly still, so its puppet position is exact and tolerances can
## be tight: after the cast, each player must be standing where the OTHER one
## was. The approach stops well outside tag contact, so a pass can't come
## from "both already in the same spot".
func _swap_test_step(game: Game) -> void:
	var me := game.local_player()
	if me == null:
		return
	var other: Player = null
	for p in game.get_player_nodes():
		if p.peer_id != me.peer_id:
			other = p
	if other == null:
		return
	match _swap_state:
		"approach":
			var dx := other.global_position.x - me.global_position.x
			if absf(dx) > 220.0:
				Input.action_press("move_right" if dx > 0.0 else "move_left")
			else:
				_release_all()
				Input.action_release("move_left")
				Input.action_release("move_right")
				_swap_state = "settle"
				_swap_at = _elapsed + 0.6  # let velocity and the puppet stream settle
		"settle":
			# Cast only AFTER the pregame grace ends (match_running), so the tag
			# rules are live and a buggy swap-as-it self-tag can actually surface.
			if _elapsed >= _swap_at and GameState.match_running:
				_swap_pre_me = me.global_position
				_swap_pre_other = other.global_position
				var sep := _swap_pre_me.distance_to(_swap_pre_other)
				print("[bot %s] swap cast: me %s other %s (separation %.0f px)" % [mode, _swap_pre_me, _swap_pre_other, sep])
				if sep < 150.0:
					_fail("swap test separation too small to be meaningful")
					return
				me.try_use_ability()
				if me.get_cooldown_remaining() <= 0.0:
					_fail("swap did not fire (no cooldown started)")
					return
				_swap_cast_done = true
				_swap_state = "eval"
				_swap_at = _elapsed + 0.5  # partner RPC + its sync stream round-trip
		"eval":
			if _elapsed >= _swap_at:
				var d_me := me.global_position.distance_to(_swap_pre_other)
				var d_other := other.global_position.distance_to(_swap_pre_me)
				print("[bot %s] after swap: me %s (%.0f px off partner's old spot), other %s (%.0f px off my old spot)" % [mode, me.global_position, d_me, other.global_position, d_other])
				if d_me > 60.0 or d_other > 60.0:
					_fail("positions did not truly exchange (me off by %.0f, partner off by %.0f)" % [d_me, d_other])
					return
				_pass("swap_positions")
				# A swap cast while "it" must NOT manufacture a tag: teleporting
				# onto the partner through the replication window is not contact.
				if _swap_self_tagged:
					_fail("swap-as-it self-tagged through the replication window")
					return
				_pass("no_self_tag")
				_swap_state = "done"
				_finish()

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


# --- update-dryrun: exercises Updater's swap engine on scratch dirs ----------
# Both Windows and macOS swap logic are pure path-ops, so BOTH are testable on
# any host OS (chmod is best-effort and no-ops off macOS).

func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _make_zip(zip_path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for name in entries:
		packer.start_file(name)
		packer.write_file((entries[name] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()

func _run_update_dryrun() -> void:
	var fails := 0
	var root := OS.get_cache_dir().path_join("slip_dryrun")
	_rm_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	# 1a) cleanup_leftovers reaps *.old artifacts WHEN the live binary exists.
	var c := root.path_join("cleanup")
	DirAccess.make_dir_recursive_absolute(c.path_join("Slippington.app.old"))
	DirAccess.make_dir_recursive_absolute(c.path_join("Slippington.app"))
	_put(c.path_join("Slippington.exe"), "live")
	_put(c.path_join("Slippington.console.exe"), "live")
	_put(c.path_join("Slippington.old.exe"), "x")
	_put(c.path_join("Slippington.console.old.exe"), "x")
	_put(c.path_join("Slippington.app.old").path_join("f"), "x")
	_put(c.path_join("Slippington.app").path_join("f"), "live")
	Updater.cleanup_leftovers(c)
	if FileAccess.file_exists(c.path_join("Slippington.old.exe")) \
			or FileAccess.file_exists(c.path_join("Slippington.console.old.exe")) \
			or DirAccess.dir_exists_absolute(c.path_join("Slippington.app.old")):
		print("FAIL dryrun: leftovers not cleaned (live present)"); fails += 1
	else:
		print("PASS dryrun: leftovers cleaned")

	# 1b) cleanup_leftovers PRESERVES a *.old when its live binary is MISSING
	# (double-fault recovery — never reap the sole surviving copy).
	var c2 := root.path_join("cleanup_orphan")
	DirAccess.make_dir_recursive_absolute(c2.path_join("Slippington.app.old"))
	_put(c2.path_join("Slippington.old.exe"), "sole")
	_put(c2.path_join("Slippington.app.old").path_join("f"), "sole")
	Updater.cleanup_leftovers(c2)
	if FileAccess.file_exists(c2.path_join("Slippington.old.exe")) \
			and DirAccess.dir_exists_absolute(c2.path_join("Slippington.app.old")):
		print("PASS dryrun: leftovers preserved when live missing")
	else:
		print("FAIL dryrun: orphan .old wrongly reaped"); fails += 1

	# 2) Windows swap happy path via install_from_zip(fixture).
	var w := root.path_join("win")
	DirAccess.make_dir_recursive_absolute(w)
	_put(w.path_join("Slippington.exe"), "OLDEXE")
	_put(w.path_join("Slippington.console.exe"), "OLDCON")
	var zip := root.path_join("fixture-win.zip")
	_make_zip(zip, {"Slippington.exe": "NEWEXE", "Slippington.console.exe": "NEWCON", "HOW_TO_PLAY.txt": "ignore me"})
	Updater.test_fail_on = ""
	if Updater.install_from_zip(zip, w) \
			and _read(w.path_join("Slippington.exe")) == "NEWEXE" \
			and _read(w.path_join("Slippington.console.exe")) == "NEWCON" \
			and _read(w.path_join("Slippington.old.exe")) == "OLDEXE":
		print("PASS dryrun: windows swap + backup")
	else:
		print("FAIL dryrun: windows swap"); fails += 1

	# 3) Windows restore-on-failure (inject a mid-swap failure on the 2nd file).
	var wr := root.path_join("winr")
	var st := wr.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(st)
	_put(wr.path_join("Slippington.exe"), "OLDEXE")
	_put(wr.path_join("Slippington.console.exe"), "OLDCON")
	_put(st.path_join("Slippington.exe"), "NEWEXE")
	_put(st.path_join("Slippington.console.exe"), "NEWCON")
	Updater.test_fail_on = "Slippington.console.exe"
	var w_ok := Updater.apply_windows_swap(wr, st)
	Updater.test_fail_on = ""
	if not w_ok \
			and _read(wr.path_join("Slippington.exe")) == "OLDEXE" \
			and _read(wr.path_join("Slippington.console.exe")) == "OLDCON" \
			and not FileAccess.file_exists(wr.path_join("Slippington.old.exe")):
		print("PASS dryrun: windows restore-on-failure")
	else:
		print("FAIL dryrun: windows restore"); fails += 1

	# 4) macOS swap happy path (call apply_macos_swap directly).
	var m := root.path_join("mac")
	var m_inner := "Slippington.app/Contents/MacOS/Slippington"
	var ms := m.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(m.path_join("Slippington.app/Contents/MacOS"))
	DirAccess.make_dir_recursive_absolute(ms.path_join("Slippington.app/Contents/MacOS"))
	_put(m.path_join(m_inner), "OLDAPP")
	_put(ms.path_join(m_inner), "NEWAPP")
	Updater.test_fail_on = ""
	if Updater.apply_macos_swap(m, ms) \
			and _read(m.path_join(m_inner)) == "NEWAPP" \
			and _read(m.path_join("Slippington.app.old/Contents/MacOS/Slippington")) == "OLDAPP":
		print("PASS dryrun: macos swap + backup")
	else:
		print("FAIL dryrun: macos swap"); fails += 1

	# 5) macOS restore-on-failure.
	var mr := root.path_join("macr")
	var mrs := mr.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(mr.path_join("Slippington.app/Contents/MacOS"))
	DirAccess.make_dir_recursive_absolute(mrs.path_join("Slippington.app/Contents/MacOS"))
	_put(mr.path_join(m_inner), "OLDAPP")
	_put(mrs.path_join(m_inner), "NEWAPP")
	Updater.test_fail_on = "macos"
	var m_ok := Updater.apply_macos_swap(mr, mrs)
	Updater.test_fail_on = ""
	if not m_ok and _read(mr.path_join(m_inner)) == "OLDAPP":
		print("PASS dryrun: macos restore-on-failure")
	else:
		print("FAIL dryrun: macos restore"); fails += 1

	# 6) write probe: true for a writable dir, false for a bogus one.
	if Updater._dir_writable(root) and not Updater._dir_writable("Z:/slip_nope/never"):
		print("PASS dryrun: write probe")
	else:
		print("FAIL dryrun: write probe"); fails += 1

	# clean abort: a zip with no platform binaries → install_from_zip returns
	# false and the existing install is left untouched (invariant's abort branch).
	var ca := root.path_join("cleanabort")
	DirAccess.make_dir_recursive_absolute(ca)
	_put(ca.path_join("Slippington.exe"), "LIVEEXE")
	_put(ca.path_join("Slippington.console.exe"), "LIVECON")
	var badzip := root.path_join("fixture-bad.zip")
	_make_zip(badzip, {"README.txt": "nothing relevant here"})
	Updater.test_fail_on = ""
	if not Updater.install_from_zip(badzip, ca) \
			and _read(ca.path_join("Slippington.exe")) == "LIVEEXE" \
			and _read(ca.path_join("Slippington.console.exe")) == "LIVECON" \
			and not FileAccess.file_exists(ca.path_join("Slippington.old.exe")):
		print("PASS dryrun: clean abort on irrelevant zip")
	else:
		print("FAIL dryrun: clean abort"); fails += 1

	_rm_tree(root)
	if fails == 0:
		print("[bot update-dryrun] ALL CHECKS PASSED"); get_tree().quit(0)
	else:
		print("[bot update-dryrun] FAILED: %d" % fails); get_tree().quit(1)
