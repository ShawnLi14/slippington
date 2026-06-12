class_name GameHud
extends CanvasLayer
## In-match HUD: countdown timer (top center), ability cooldown box
## (bottom right), pre-match status, and the TAG! flash.

var game: Node2D

var _timer_label: Label
var _status_label: Label
var _ability_name: Label
var _ability_key: Label
var _cooldown_fill: ColorRect
var _flash_label: Label

const TEAL := Color("#4ecdc4")
const RED := Color("#ff6b6b")


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.position = Vector2(-100, 16)
	_timer_label.size = Vector2(200, 48)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 40)
	root.add_child(_timer_label)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-300, 64)
	_status_label.size = Vector2(600, 24)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	root.add_child(_status_label)

	var ability_box := PanelContainer.new()
	ability_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ability_box.position = Vector2(-220, -110)
	ability_box.size = Vector2(196, 86)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.border_color = TEAL
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	ability_box.add_theme_stylebox_override("panel", style)
	root.add_child(ability_box)

	var vbox := VBoxContainer.new()
	ability_box.add_child(vbox)

	_ability_name = Label.new()
	_ability_name.add_theme_font_size_override("font_size", 18)
	_ability_name.add_theme_color_override("font_color", TEAL)
	vbox.add_child(_ability_name)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.12)
	bar_bg.custom_minimum_size = Vector2(170, 8)
	vbox.add_child(bar_bg)
	_cooldown_fill = ColorRect.new()
	_cooldown_fill.color = TEAL
	_cooldown_fill.size = Vector2(170, 8)
	bar_bg.add_child(_cooldown_fill)

	_ability_key = Label.new()
	_ability_key.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_ability_key)

	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_CENTER)
	_flash_label.position = Vector2(-300, -120)
	_flash_label.size = Vector2(600, 80)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 56)
	_flash_label.modulate.a = 0.0
	root.add_child(_flash_label)


func _process(_delta: float) -> void:
	if GameState.match_running:
		var remaining := int(ceil(GameState.match_remaining))
		_timer_label.text = str(remaining)
		_timer_label.add_theme_color_override("font_color", RED if remaining <= 10 else Color.WHITE)
		var me_it := GameState.it_peer == multiplayer.get_unique_id()
		_status_label.text = "RUN — you're IT!" if me_it else "Don't get tagged!"
	else:
		_timer_label.text = "%d player%s" % [GameState.players.size(), "" if GameState.players.size() == 1 else "s"]
		_status_label.text = "First tag starts the clock"

	var me: Player = game.local_player() if game != null else null
	if me != null and me.player_class != null and me.player_class.primary_ability != null:
		var ability := me.player_class.primary_ability
		_ability_name.text = ability.display_name.to_upper()
		var remaining_cd := me.get_cooldown_remaining()
		if remaining_cd <= 0.0:
			_cooldown_fill.size.x = 170
			_ability_key.text = "[Q]  READY"
			_ability_key.add_theme_color_override("font_color", TEAL)
		else:
			_cooldown_fill.size.x = 170.0 * (1.0 - remaining_cd / ability.cooldown_sec)
			_ability_key.text = "[Q]  %.1fs" % remaining_cd
			_ability_key.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))


func flash_tag(you_are_it: bool) -> void:
	_flash_label.text = "TAG — YOU'RE IT!" if you_are_it else "TAG!"
	_flash_label.add_theme_color_override("font_color", RED if you_are_it else Color.WHITE)
	_flash_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_flash_label, "modulate:a", 0.0, 0.5)
