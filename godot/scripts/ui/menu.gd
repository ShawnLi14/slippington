class_name MainMenu
extends Control
## Main menu: pick a name + class, then host or join a game.
## Online games go through join codes; Direct Connect (ENet by IP) is the
## LAN / port-forward fallback.

var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _signaling_edit: LineEdit
var _status: Label
var _class_buttons: Dictionary = {}
var _selected_class := "slipper"
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.fullscreen_bg(self)

	var center := VBoxContainer.new()
	UiTheme.anchor_rect(center, Control.PRESET_CENTER, Rect2(-380, -330, 760, 660))
	center.add_theme_constant_override("separation", 14)
	add_child(center)

	center.add_child(UiTheme.title("SLIPPINGTON"))
	center.add_child(UiTheme.label("multiplayer tag", 16, Color(1, 1, 1, 0.5)))

	# Name
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(UiTheme.label("Name", 18))
	_name_edit = LineEdit.new()
	_name_edit.text = "Player%d" % (randi() % 1000)
	_name_edit.custom_minimum_size = Vector2(280, 40)
	_name_edit.max_length = 16
	name_row.add_child(_name_edit)
	center.add_child(name_row)

	# Class cards
	center.add_child(UiTheme.label("Class", 18))
	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 12)
	for player_class in ClassRegistry.all():
		var card := _make_class_card(player_class)
		_class_buttons[player_class.id] = card
		class_row.add_child(card)
	center.add_child(class_row)
	_update_class_selection()

	# Online play
	var online_panel := UiTheme.panel()
	var online := VBoxContainer.new()
	online.add_theme_constant_override("separation", 10)
	online_panel.add_child(online)
	online.add_child(UiTheme.label("PLAY ONLINE", 14, UiTheme.TEAL))
	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 10)
	var host_btn := UiTheme.button("CREATE GAME", true)
	host_btn.pressed.connect(_on_host_online)
	online_row.add_child(host_btn)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "CODE"
	_code_edit.custom_minimum_size = Vector2(120, 44)
	_code_edit.max_length = 5
	online_row.add_child(_code_edit)
	var join_btn := UiTheme.button("JOIN")
	join_btn.pressed.connect(_on_join_online)
	online_row.add_child(join_btn)
	online.add_child(online_row)
	center.add_child(online_panel)
	_buttons.append_array([host_btn, join_btn])

	# Direct connect (advanced)
	var lan_panel := UiTheme.panel()
	var lan := VBoxContainer.new()
	lan.add_theme_constant_override("separation", 10)
	lan_panel.add_child(lan)
	lan.add_child(UiTheme.label("DIRECT CONNECT (LAN / advanced)", 14, Color(1, 1, 1, 0.5)))
	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 10)
	var lan_host_btn := UiTheme.button("HOST LAN")
	lan_host_btn.pressed.connect(_on_host_lan)
	lan_row.add_child(lan_host_btn)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host ip, e.g. 192.168.1.20"
	_ip_edit.custom_minimum_size = Vector2(240, 44)
	lan_row.add_child(_ip_edit)
	var lan_join_btn := UiTheme.button("JOIN IP")
	lan_join_btn.pressed.connect(_on_join_lan)
	lan_row.add_child(lan_join_btn)
	lan.add_child(lan_row)
	var sig_row := HBoxContainer.new()
	sig_row.add_theme_constant_override("separation", 10)
	sig_row.add_child(UiTheme.label("Signaling server", 13, Color(1, 1, 1, 0.4)))
	_signaling_edit = LineEdit.new()
	_signaling_edit.text = NetworkManager.signaling_url
	_signaling_edit.custom_minimum_size = Vector2(340, 36)
	sig_row.add_child(_signaling_edit)
	lan.add_child(sig_row)
	center.add_child(lan_panel)
	_buttons.append_array([lan_host_btn, lan_join_btn])

	_status = UiTheme.label("", 15, UiTheme.RED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_status)

	NetworkManager.session_failed.connect(_on_failed)
	NetworkManager.joiner_progress.connect(func(text): _set_status(text, Color(1, 1, 1, 0.6)))
	GameState.status_message.connect(func(text): _set_status(text, UiTheme.RED))


func _make_class_card(player_class: PlayerClass) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 120)
	card.toggle_mode = true
	card.text = "%s\n%s\nQ: %s" % [
		player_class.display_name.to_upper(),
		player_class.description,
		player_class.primary_ability.display_name,
	]
	card.pressed.connect(func():
		_selected_class = player_class.id
		_update_class_selection()
	)
	return card


func _update_class_selection() -> void:
	for id in _class_buttons:
		_class_buttons[id].button_pressed = id == _selected_class


func _commit_identity() -> void:
	GameState.local_name = _name_edit.text.strip_edges()
	if GameState.local_name == "":
		GameState.local_name = _name_edit.placeholder_text
	GameState.local_class_id = _selected_class
	NetworkManager.signaling_url = _signaling_edit.text.strip_edges()
	_set_buttons_disabled(true)


func _on_host_online() -> void:
	_commit_identity()
	NetworkManager.host_online()


func _on_join_online() -> void:
	if _code_edit.text.strip_edges().length() < 4:
		_set_status("Enter the 5-letter game code", UiTheme.RED)
		return
	_commit_identity()
	NetworkManager.join_online(_code_edit.text)


func _on_host_lan() -> void:
	_commit_identity()
	NetworkManager.host_lan()


func _on_join_lan() -> void:
	if _ip_edit.text.strip_edges() == "":
		_set_status("Enter the host's IP address", UiTheme.RED)
		return
	_commit_identity()
	NetworkManager.join_lan(_ip_edit.text.strip_edges())


func _on_failed(reason: String) -> void:
	_set_status(reason, UiTheme.RED)
	_set_buttons_disabled(false)


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _set_buttons_disabled(disabled: bool) -> void:
	for b in _buttons:
		b.disabled = disabled
