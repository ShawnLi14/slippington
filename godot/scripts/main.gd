extends Node
## Root scene: swaps the active screen as GameState moves through its phases.

var _current: Node


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	_show_for_phase(GameState.phase)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto="):
			add_child(load("res://tests/auto_driver.gd").new())
			break


func _on_phase_changed(phase: GameState.Phase) -> void:
	_show_for_phase(phase)


func _show_for_phase(phase: GameState.Phase) -> void:
	if _current != null:
		if _current is Game:
			# Unreliable sync packets may still be in flight from peers that
			# haven't processed the phase change yet. Keep the node tree alive
			# (but inert and invisible) briefly so they resolve instead of
			# spamming "node not found" errors.
			var dying := _current
			dying.visible = false
			dying.process_mode = Node.PROCESS_MODE_DISABLED
			get_tree().create_timer(1.0).timeout.connect(dying.queue_free)
		else:
			_current.queue_free()
		_current = null
	match phase:
		GameState.Phase.MENU:
			_current = MainMenu.new()
		GameState.Phase.LOBBY:
			_current = Lobby.new()
		GameState.Phase.PLAYING:
			_current = Game.new()
		GameState.Phase.ENDED:
			_current = EndScreen.new()
	if _current is Game:
		# Explicit name so node paths (and therefore RPCs to player nodes
		# inside the game scene) are identical on every peer. Clear any
		# still-dying predecessor first.
		var stale := get_node_or_null("Screen")
		if stale != null:
			stale.name = "DyingScreen"
			stale.queue_free()
		_current.name = "Screen"
	add_child(_current)
