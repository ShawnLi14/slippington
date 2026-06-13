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
var rounds_arg := 1
var _playing_entries := 0
var _event_shot_taken := false

## Seconds a nav-test bot may take to reach one target before it's a miss.
const NAV_TARGET_BUDGET := 10.0
## Fraction of reachable surfaces the bot must reach from a COLD SPAWN to
## pass. Deliberately not high: this is the hardest possible nav case —
## planning a whole multi-hop climb from the ground with fixed-height
## bang-bang jumps. Real chasing is far easier (the bot follows the prey one
## hop at a time, re-planning each landing), so this is a regression guard
## against the navigator breaking, not a measure of in-match competence.
## Typical cold-start reach runs ~45-60%; a crater here means nav is broken.
const NAV_PASS_FRACTION := 0.35

var _jump_cooldown := 0.0
var _ability_timer := 0.0
var _nav: BotNavigator
var _policy: BotPolicy
var bot_diff_level := "hard"  # playtest bots default to the toughest tier
var expected_players := 2     # host starts once this many have joined

# nav-test (navigation soundness) state.
var _nav_targets: Array = []
var _nav_i := 0
var _nav_deadline := 0.0
var _nav_reached := 0
var _nav_spawn := Vector2.ZERO
var _nav_trace := -1
var _nav_dbg_t := 0.0

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
		elif arg.begins_with("--rounds="):
			rounds_arg = int(arg.trim_prefix("--rounds="))
			timeout_sec = maxf(timeout_sec, float(rounds_arg) * (timeout_sec * 0.6) + 30.0)
		elif arg.begins_with("--class="):
			bot_class = arg.trim_prefix("--class=")
		elif arg.begins_with("--connect-timeout="):
			NetworkManager.connect_timeout_sec = float(arg.trim_prefix("--connect-timeout="))
		elif arg == "--force-relay":
			# Exercise the TURN relay path: ignore host/reflexive candidates.
			NetworkManager.force_relay = true
		elif arg.begins_with("--trace="):
			_nav_trace = int(arg.trim_prefix("--trace="))
		elif arg.begins_with("--difficulty="):
			bot_diff_level = arg.trim_prefix("--difficulty=")
		elif arg.begins_with("--players="):
			# Host waits for this many players before starting (multi-bot).
			expected_players = int(arg.trim_prefix("--players="))
		elif arg.begins_with("--match-seconds="):
			# The clock only starts at the first tag — leave generous slack.
			timeout_sec = float(arg.trim_prefix("--match-seconds=")) + 45.0

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
			bot_class = "swapper"
		timeout_sec = 25.0
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
	elif mode != "join-bad-online":
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
		if mode == "host" and code_file.ends_with(".png") and shot_event == "tag" and _tag_count == 2:
			_take_screenshot(0.12)
	)
	GameState.match_timer_updated.connect(func(remaining):
		if mode == "host" and code_file.ends_with(".png") and shot_event == "slush" \
				and remaining <= 6.0 and not _event_shot_taken:
			_event_shot_taken = true
			_take_screenshot(0.2)
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
		"shot-practice":
			GameState.local_name = "You"
			GameState.start_practice()
			_take_screenshot(3.0)
			return
		"nav-test":
			# Navigation soundness: drive a pawn through the graph to every
			# reachable surface and assert it actually arrives. Catches maps
			# the planner validates but real physics can't traverse.
			timeout_sec = 160.0
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
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
		"host", "host-swap":
			NetworkManager.host_lan(port)
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
			and GameState.players.size() >= expected_players and not _started_game:
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
		if mode == "nav-test":
			print("[nav-test] FAIL: timed out")
			_done = true
			get_tree().quit(1)
			return
		_finish()
		return

	if GameState.phase != GameState.Phase.PLAYING:
		_release_all()
		# After the match (or series) ends, every check should be in.
		if GameState.phase == GameState.Phase.ENDED and _checks.get("match_ended", false) \
				and (rounds_arg == 1 or GameState.series_final):
			_finish()
		return
	var game := get_tree().root.get_node_or_null("Main/Screen") as Game
	if game == null:
		return

	if mode == "nav-test":
		_nav_test_step(game, delta)
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
			if _elapsed >= _swap_at:
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
				_swap_state = "eval"
				_swap_at = _elapsed + 0.5  # partner RPC + its sync stream round-trip
		"eval":
			if _elapsed >= _swap_at:
				var d_me := me.global_position.distance_to(_swap_pre_other)
				var d_other := other.global_position.distance_to(_swap_pre_me)
				print("[bot %s] after swap: me %s (%.0f px off partner's old spot), other %s (%.0f px off my old spot)" % [mode, me.global_position, d_me, other.global_position, d_other])
				if d_me <= 60.0 and d_other <= 60.0:
					_pass("swap_positions")
					_swap_state = "done"
					_finish()
				else:
					_fail("positions did not truly exchange (me off by %.0f, partner off by %.0f)" % [d_me, d_other])

	# Success: everything checked — wind down early.
	var all_passed := true
	for k in _checks:
		if not _checks[k]:
			all_passed = false
	if all_passed and _elapsed > 8.0:
		_finish()


## Navigation soundness: walk the pawn to every reachable surface and assert
## arrival within a per-target budget. The pawn is Input-driven (the real
## human path), so this validates the planner's arcs against actual physics.
func _nav_test_step(game: Game, delta: float) -> void:
	var me := game.local_player()
	if me == null:
		return
	if _nav == null:
		_nav = BotNavigator.new(game.get_nav_graph())
		for idx in _nav.reachable_indices():
			if idx != _nav.ground_index():
				_nav_targets.append(idx)
		# Cap the count for runtime; evenly sample if there are many surfaces.
		if _nav_targets.size() > 12:
			var sampled: Array = []
			var stride: float = float(_nav_targets.size()) / 12.0
			var f := 0.0
			while sampled.size() < 12 and int(f) < _nav_targets.size():
				sampled.append(_nav_targets[int(f)])
				f += stride
			_nav_targets = sampled
		_nav_spawn = me.global_position
		_nav_deadline = _elapsed + NAV_TARGET_BUDGET
		print("[nav-test] map %s: %d reachable targets" % [GameState.map_seed, _nav_targets.size()])
		if _nav_trace >= 0:
			var surfs: Array = game.get_nav_graph()["surfaces"]
			for si in surfs.size():
				var sr: Rect2 = surfs[si]["rect"]
				print("[surf] %d: %.0f,%.0f %.0fx%.0f thru=%s edges=%s" % [si, sr.position.x, sr.position.y,
					sr.size.x, sr.size.y, surfs[si].get("thru", false), str(game.get_nav_graph()["edges"][si])])

	if _nav_i >= _nav_targets.size():
		_done = true
		var total: int = _nav_targets.size()
		var rate := float(_nav_reached) / maxf(1.0, float(total))
		print("[nav-test] reached %d/%d targets (%.0f%%)" % [_nav_reached, total, rate * 100.0])
		if rate >= NAV_PASS_FRACTION:
			print("[nav-test] ALL CHECKS PASSED")
			get_tree().quit(0)
		else:
			print("[nav-test] FAIL: reach rate %.0f%% below %.0f%% floor" % [rate * 100.0, NAV_PASS_FRACTION * 100.0])
			get_tree().quit(1)
		return

	var tgt: int = _nav_targets[_nav_i]
	var cmd := _nav.navigate(me, _nav.surface_goal(tgt), delta)
	_apply_cmd(cmd)
	if tgt == _nav_trace and _elapsed - _nav_dbg_t > 0.4:
		_nav_dbg_t = _elapsed
		print("[dbg] t%d pos=%.0f,%.0f floor=%s loc=%d md=%.0f jp=%s %s" % [
			tgt, me.global_position.x, me.global_position.y, me.is_on_floor(),
			_nav.localize(me.global_position), cmd["move_dir"], cmd["jump"], _nav.debug_state()])
	if me.is_on_floor() and _nav.localize(me.global_position) == tgt:
		_nav_reached += 1
		print("[nav-test]   reached surface %d (%d/%d)" % [tgt, _nav_reached, _nav_targets.size()])
		_nav_advance(me)
	elif _elapsed > _nav_deadline:
		var r: Rect2 = game.get_nav_graph()["surfaces"][tgt]["rect"]
		print("[nav-test]   MISS surface %d at %.0f,%.0f" % [tgt, r.position.x, r.position.y])
		_nav_advance(me)


## Move to the next target: each is an independent reach-from-spawn check, so
## reset the pawn to the spawn point and clear the navigator's path state.
func _nav_advance(me: Player) -> void:
	_nav_i += 1
	_nav_deadline = _elapsed + NAV_TARGET_BUDGET
	me.global_position = _nav_spawn
	me.velocity = Vector2.ZERO
	_nav.reset()
	_apply_cmd({"move_dir": 0.0, "jump": false, "drop": false})


## Playtest bot: navigate the graph to chase when "it" and to flee when
## hunted, popping an ability when in range. Produces realistic chases (over
## real terrain — walls, springs, ladders) for telemetry.
func _smart_move(game: Game, delta: float) -> void:
	var me := game.local_player()
	if me == null:
		return
	if _nav == null:
		_nav = BotNavigator.new(game.get_nav_graph())
	if _policy == null:
		_policy = BotPolicy.new()
	_ability_timer += delta

	if me.is_it():
		if _nearest_prey(game, me) == null:
			_apply_cmd({"move_dir": 0.0, "jump": false, "drop": false})
			return
	else:
		var hunter := game.get_player_node(GameState.it_peer)
		if hunter == null or hunter.global_position.distance_to(me.global_position) > 520.0:
			# Hunter not a threat — rest (a real player wouldn't sprint forever).
			_apply_cmd({"move_dir": 0.0, "jump": false, "drop": false})
			Input.action_release("ability_primary")
			return

	# BotPolicy picks the goal + ability by role and difficulty; nav routes it.
	var players := game.get_player_nodes()
	var decision := _policy.tick(me, players, _nav.graph, BotDifficulty.params(bot_diff_level), delta)
	_apply_cmd(_nav.navigate(me, decision["goal"], delta))
	if decision["ability"]:
		Input.action_press("ability_primary")
	else:
		Input.action_release("ability_primary")


func _nearest_prey(game: Game, me: Player) -> Player:
	var best: Player = null
	var nearest := INF
	for p in game.get_player_nodes():
		if p.peer_id == me.peer_id:
			continue
		var d: float = p.global_position.distance_to(me.global_position)
		if d < nearest:
			nearest = d
			best = p
	return best


## Translate a BotNavigator command into the same input actions a human uses.
func _apply_cmd(cmd: Dictionary) -> void:
	var d: float = cmd["move_dir"]
	if d > 0.0:
		Input.action_press("move_right")
		Input.action_release("move_left")
	elif d < 0.0:
		Input.action_press("move_left")
		Input.action_release("move_right")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")
	if cmd["drop"]:
		Input.action_press("move_down")
	else:
		Input.action_release("move_down")
	if cmd["jump"]:
		Input.action_press("jump")
	else:
		Input.action_release("jump")


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
