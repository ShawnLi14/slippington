class_name MainMenu
extends Control
## Main menu. Design goals (party-game conventions): the live game backdrop
## behind everything, bold title, the actual characters on the class cards,
## one big primary action (CREATE GAME), join-by-code right under it, and
## all advanced networking tucked behind a toggle.

var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _signaling_edit: LineEdit
var _status: Label
var _class_cards: Dictionary = {}
var _selected_class := "slipper"
var _buttons: Array[Button] = []
var _advanced_panel: PanelContainer

const CLASS_CARD_COLORS := {
	"slipper": Color("#4ecdc4"),
	"swapper": Color("#ffd93d"),
	"anchor": Color("#a29bfe"),
	"echo": Color("#fd79a8"),
	"decoy": Color("#ff9f43"),
	"mason": Color("#7bed9f"),
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The game's own animated sky behind the menu — continuity with play.
	UiTheme.menu_backdrop(self)

	var center := VBoxContainer.new()
	# Wide enough for the 6-card class row (6×220 + 5×16 = 1400); grow
	# symmetrically so any future overflow stays centered instead of
	# spilling off the right edge.
	UiTheme.anchor_rect(center, Control.PRESET_CENTER, Rect2(-710, -400, 1420, 800))
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", 18)
	add_child(center)

	# --- title -----------------------------------------------------------
	var title := UiTheme.title("SLIPPINGTON", 84)
	center.add_child(title)
	title.call_deferred("set", "pivot_offset", title.size / 2.0)
	UiAnim.title_idle.call_deferred(title)
	var subtitle := UiTheme.label("don't be IT when the clock runs out", 18, Color(1, 1, 1, 0.85))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.8))
	subtitle.add_theme_constant_override("outline_size", 5)
	center.add_child(subtitle)
	center.add_child(_spacer(6))

	# --- name ------------------------------------------------------------
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	var name_label := UiTheme.label("NAME", 15, Color(1, 1, 1, 0.85))
	name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.8))
	name_label.add_theme_constant_override("outline_size", 4)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = "Player%d" % (randi() % 1000)
	_name_edit.custom_minimum_size = Vector2(260, 42)
	_name_edit.max_length = 16
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 18)
	name_row.add_child(_name_edit)
	center.add_child(name_row)

	# --- class cards -------------------------------------------------------
	var class_row := HBoxContainer.new()
	class_row.alignment = BoxContainer.ALIGNMENT_CENTER
	class_row.add_theme_constant_override("separation", 16)
	for player_class in ClassRegistry.all():
		var card := _make_class_card(player_class)
		_class_cards[player_class.id] = card
		class_row.add_child(card)
	center.add_child(class_row)
	_update_class_selection()

	# --- primary action ------------------------------------------------------
	var create_btn := UiTheme.button("CREATE GAME", true)
	create_btn.custom_minimum_size = Vector2(340, 60)
	create_btn.add_theme_font_size_override("font_size", 24)
	create_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_btn.pressed.connect(_on_host_online)
	center.add_child(create_btn)
	_buttons.append(create_btn)

	# --- join by code ---------------------------------------------------------
	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 10)
	var have_label := UiTheme.label("have a code?", 15, Color(1, 1, 1, 0.85))
	have_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.8))
	have_label.add_theme_constant_override("outline_size", 4)
	join_row.add_child(have_label)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "CODE"
	_code_edit.custom_minimum_size = Vector2(120, 44)
	_code_edit.max_length = 5
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_size_override("font_size", 20)
	join_row.add_child(_code_edit)
	var join_btn := UiTheme.button("JOIN")
	join_btn.custom_minimum_size = Vector2(120, 44)
	join_btn.pressed.connect(_on_join_online)
	UiTheme._apply_button_instance(join_btn, UiTheme.SUN, UiTheme.INK)
	join_row.add_child(join_btn)
	center.add_child(join_row)
	_buttons.append(join_btn)

	var practice_btn := UiTheme.button("PRACTICE VS BOT")
	practice_btn.custom_minimum_size = Vector2(220, 40)
	practice_btn.add_theme_font_size_override("font_size", 15)
	practice_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	practice_btn.pressed.connect(_on_practice)
	center.add_child(practice_btn)

	_status = UiTheme.label("", 15, UiTheme.RED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.9))
	_status.add_theme_constant_override("outline_size", 4)
	center.add_child(_status)

	# --- advanced (collapsed) ---------------------------------------------------
	# LAN / direct-IP uses ENet, which has no HTML5 implementation, so on web the
	# advanced panel offers only the signaling-server override.
	var is_web := OS.has_feature("web")
	var adv_label := "signaling server" if is_web else "LAN / direct connect"
	var adv_toggle := Button.new()
	adv_toggle.text = "▸ advanced: " + adv_label
	adv_toggle.flat = true
	adv_toggle.add_theme_font_size_override("font_size", 13)
	adv_toggle.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	adv_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	adv_toggle.pressed.connect(func():
		_advanced_panel.visible = not _advanced_panel.visible
		adv_toggle.text = ("▾" if _advanced_panel.visible else "▸") + " advanced: " + adv_label
	)
	center.add_child(adv_toggle)

	_advanced_panel = UiTheme.panel()
	_advanced_panel.visible = false
	var lan := VBoxContainer.new()
	lan.add_theme_constant_override("separation", 10)
	_advanced_panel.add_child(lan)
	if not is_web:
		var lan_row := HBoxContainer.new()
		lan_row.alignment = BoxContainer.ALIGNMENT_CENTER
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
		_buttons.append_array([lan_host_btn, lan_join_btn])
	var sig_row := HBoxContainer.new()
	sig_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sig_row.add_theme_constant_override("separation", 10)
	sig_row.add_child(UiTheme.label("signaling server", 13, Color(1, 1, 1, 0.4)))
	_signaling_edit = LineEdit.new()
	_signaling_edit.text = NetworkManager.signaling_url
	_signaling_edit.custom_minimum_size = Vector2(340, 36)
	sig_row.add_child(_signaling_edit)
	lan.add_child(sig_row)
	center.add_child(_advanced_panel)

	# Staggered entrance: fade children in with a slight delay per element.
	# VBoxContainer controls child positions, so the position-slide may not
	# apply; the fade-in is the guaranteed, desired effect.
	var i := 0
	for child in center.get_children():
		if child is Control:
			UiAnim.entrance(child, i)
			i += 1

	# Method connections only — lambdas on autoload signals outlive this
	# screen and crash release builds once it's freed.
	NetworkManager.session_failed.connect(_on_failed)
	NetworkManager.joiner_progress.connect(_on_progress)
	GameState.status_message.connect(_on_status_message)


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _on_progress(text: String) -> void:
	_set_status(text, Color(1, 1, 1, 0.85))


func _on_status_message(text: String) -> void:
	_set_status(text, UiTheme.RED)


func _make_class_card(player_class: PlayerClass) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(220, 170)
	card.toggle_mode = true
	card.pressed.connect(func():
		_selected_class = player_class.id
		_update_class_selection()
	)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var avatar := ClassAvatar.new()
	avatar.avatar_color = CLASS_CARD_COLORS.get(player_class.id, UiTheme.TEAL)
	avatar.custom_minimum_size = Vector2(0, 58)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(avatar)

	var name_label := UiTheme.label(player_class.display_name.to_upper(), 20, UiTheme.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	var desc := UiTheme.label(player_class.description, 12, Color(0.17, 0.14, 0.31, 0.7))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(190, 0)
	content.add_child(desc)
	var ability := UiTheme.label("J · %s" % player_class.primary_ability.display_name, 14, Color(0.0, 0.45, 0.42))
	ability.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(ability)
	return card


func _update_class_selection() -> void:
	for id in _class_cards:
		var card: Button = _class_cards[id]
		var selected: bool = id == _selected_class
		card.button_pressed = selected
		var s := StyleBoxFlat.new()
		# Unselected cards use a muted warm cream (NOT near-white), so a
		# deselected card no longer reads as "going white". The selected card
		# pops with a SUN fill, a teal accent border and a soft teal glow.
		s.bg_color = UiTheme.SUN if selected else Color("#e7d8ba")
		s.border_color = UiTheme.TEAL if selected else UiTheme.INK
		s.set_border_width_all(4 if selected else 3)
		s.border_width_bottom = 7
		s.set_corner_radius_all(14)
		s.set_content_margin_all(10)
		if selected:
			s.shadow_color = Color(UiTheme.TEAL.r, UiTheme.TEAL.g, UiTheme.TEAL.b, 0.55)
			s.shadow_size = 7
		for state in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(state, s)
		card.pivot_offset = card.custom_minimum_size / 2.0
		card.scale = Vector2(1.06, 1.06) if selected else Vector2.ONE
		card.rotation = deg_to_rad(-3) if selected else 0.0


## The in-game character, drawn on the card: rounded square + eyes.
class ClassAvatar:
	extends Control
	var avatar_color := Color.WHITE

	func _draw() -> void:
		var c := size / 2.0
		var half := 24.0
		draw_rect(Rect2(c.x - half, c.y - half, half * 2, half * 2), avatar_color)
		var eye := Color(0.06, 0.06, 0.1)
		draw_circle(c + Vector2(2.0, -6.0), 4.5, eye)
		draw_circle(c + Vector2(14.0, -6.0), 4.5, eye)


func _commit_identity() -> void:
	GameState.local_name = _name_edit.text.strip_edges()
	if GameState.local_name == "":
		GameState.local_name = "Player%d" % (randi() % 1000)
	GameState.local_class_id = _selected_class
	NetworkManager.signaling_url = _signaling_edit.text.strip_edges()
	_set_buttons_disabled(true)


func _on_host_online() -> void:
	_commit_identity()
	NetworkManager.host_online()


func _on_practice() -> void:
	GameState.local_name = _name_edit.text.strip_edges()
	if GameState.local_name == "":
		GameState.local_name = "You"
	GameState.local_class_id = _selected_class
	NetworkManager.leave()
	GameState.start_practice()


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
