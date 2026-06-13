extends Control
## Root scene: swaps the active screen as GameState moves through its phases.
## Must be a Control (sized to the window) so the UI screens' full-rect and
## centered anchors have a real parent rect to resolve against.

var _current: Node
var _host_warning: CanvasLayer


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	_show_for_phase(GameState.phase)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto="):
			add_child(load("res://tests/auto_driver.gd").new())
			break
	# A hidden browser tab is throttled to a near-stop, so a host who switches
	# away freezes the match (and the lobby) for everyone. Warn them. Web only —
	# desktop windows keep running in the background.
	if OS.has_feature("web"):
		_build_host_warning()


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


# --- host "keep this tab active" warning (web) --------------------------------

func _notification(what: int) -> void:
	if _host_warning == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if _hosting_live_match():
				_host_warning.visible = true
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# It was set visible while hidden (and couldn't render); now that
			# we're back, leave it up briefly so they actually see it, then clear.
			if _host_warning.visible:
				get_tree().create_timer(5.0).timeout.connect(_hide_host_warning)


func _hosting_live_match() -> bool:
	return NetworkManager.is_host \
			and GameState.phase in [GameState.Phase.LOBBY, GameState.Phase.PLAYING]


func _hide_host_warning() -> void:
	if is_instance_valid(_host_warning):
		_host_warning.visible = false


func _build_host_warning() -> void:
	_host_warning = CanvasLayer.new()
	_host_warning.layer = 200  # above the HUD and everything else
	_host_warning.visible = false
	add_child(_host_warning)

	var panel := PanelContainer.new()
	UiTheme.anchor_rect(panel, Control.PRESET_CENTER_TOP, Rect2(-350, 24, 700, 120))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.07, 0.06, 0.96)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = UiTheme.RED
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	_host_warning.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var title := UiTheme.label("⚠  Keep this tab active while hosting", 18, UiTheme.RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	var body := UiTheme.label(
		"The game pauses for everyone when Slippington isn't the foreground tab — "
		+ "friends can't join and the match freezes while you're away.",
		14, Color(1, 1, 1, 0.85))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(660, 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
