class_name Lobby
extends Control
## Pre-game lobby: shows the join code, connected players with class and
## ready state. The host picks a map and starts once everyone is ready.

var _player_list: VBoxContainer
var _start_btn: Button
var _map_picker: OptionButton
var _ready_btn: Button
var _is_ready := false

const MAP_CHOICES := [["random", "Random map"], ["arena", "Arena"], ["towers", "Towers"]]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.fullscreen_bg(self)

	var center := VBoxContainer.new()
	UiTheme.anchor_rect(center, Control.PRESET_CENTER, Rect2(-330, -300, 660, 600))
	center.add_theme_constant_override("separation", 16)
	add_child(center)

	center.add_child(UiTheme.title("LOBBY", 36))

	if NetworkManager.join_code != "":
		var code_panel := UiTheme.panel()
		var code_box := VBoxContainer.new()
		code_panel.add_child(code_box)
		var share_label := UiTheme.label("SHARE THIS CODE", 13, Color(1, 1, 1, 0.5))
		share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_box.add_child(share_label)
		var code_row := HBoxContainer.new()
		code_row.alignment = BoxContainer.ALIGNMENT_CENTER
		code_row.add_theme_constant_override("separation", 16)
		var code_label := UiTheme.label(NetworkManager.join_code, 48, UiTheme.TEAL)
		code_row.add_child(code_label)
		var copy_btn := UiTheme.button("COPY")
		copy_btn.custom_minimum_size = Vector2(110, 44)
		copy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		copy_btn.pressed.connect(func():
			DisplayServer.clipboard_set(NetworkManager.join_code)
			copy_btn.text = "COPIED!"
			get_tree().create_timer(1.2).timeout.connect(func():
				if is_instance_valid(copy_btn):
					copy_btn.text = "COPY"
			)
		)
		code_row.add_child(copy_btn)
		code_box.add_child(code_row)
		center.add_child(code_panel)

	var list_panel := UiTheme.panel()
	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 8)
	_player_list.custom_minimum_size = Vector2(600, 220)
	list_panel.add_child(_player_list)
	center.add_child(list_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	if NetworkManager.is_host:
		_map_picker = OptionButton.new()
		_map_picker.custom_minimum_size = Vector2(180, 44)
		for choice in MAP_CHOICES:
			_map_picker.add_item(choice[1])
		bottom.add_child(_map_picker)
		_start_btn = UiTheme.button("START GAME", true)
		_start_btn.pressed.connect(_on_start)
		bottom.add_child(_start_btn)
	else:
		_ready_btn = UiTheme.button("READY", true)
		_ready_btn.pressed.connect(_on_ready_toggled)
		bottom.add_child(_ready_btn)
	var leave_btn := UiTheme.button("LEAVE")
	leave_btn.pressed.connect(_on_leave)
	bottom.add_child(leave_btn)
	center.add_child(bottom)

	GameState.players_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	var ids: Array = GameState.players.keys()
	ids.sort()
	var all_ready := true
	for id in ids:
		var p: Dictionary = GameState.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = GameConfig.PLAYER_COLORS[p["color_index"]]
		swatch.custom_minimum_size = Vector2(22, 22)
		row.add_child(swatch)
		var name_text: String = p["name"]
		if id == 1:
			name_text += "  (host)"
		if id == multiplayer.get_unique_id():
			name_text += "  — you"
		row.add_child(UiTheme.label(name_text, 18))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(UiTheme.label(ClassRegistry.get_class_by_id(p["class_id"]).display_name, 16, Color(1, 1, 1, 0.6)))
		var ready_text := "READY" if p["ready"] else "..."
		row.add_child(UiTheme.label(ready_text, 16, UiTheme.TEAL if p["ready"] else Color(1, 1, 1, 0.35)))
		_player_list.add_child(row)
		if not p["ready"]:
			all_ready = false

	if _start_btn != null:
		_start_btn.disabled = not all_ready or ids.size() < 2
		_start_btn.tooltip_text = "" if all_ready else "Waiting for everyone to ready up"


func _on_ready_toggled() -> void:
	_is_ready = not _is_ready
	_ready_btn.text = "UNREADY" if _is_ready else "READY"
	GameState.submit_ready(_is_ready)


func _on_start() -> void:
	NetworkManager.close_signaling()  # lobby's over — no more late joiners
	GameState.host_start_game(MAP_CHOICES[_map_picker.selected][0])


func _on_leave() -> void:
	NetworkManager.leave()
	GameState.reset_to_menu()
