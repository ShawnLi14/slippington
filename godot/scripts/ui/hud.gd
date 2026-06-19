class_name GameHud
extends CanvasLayer
## In-match HUD: countdown timer (top center), ability cooldown box
## (bottom left, styled like the menu cards), pre-match status, and the
## TAG! flash.

var game: Node2D

var _timer_label: Label
var _status_label: Label
var _ability_name: Label
var _ability_status: Label
var _ability_box_style: StyleBoxFlat
var _keycap_style: StyleBoxFlat
var _keycap_label: Label
var _cooldown_fill: Panel
var _flash_label: Label
var _was_running := false

const TEAL := Color("#4ecdc4")
const RED := Color("#ff6b6b")
const ABILITY_KEY := "J"
const BAR_W := 190.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_timer_label = Label.new()
	UiTheme.anchor_rect(_timer_label, Control.PRESET_CENTER_TOP, Rect2(-100, 16, 200, 48))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 40)
	_timer_label.add_theme_font_override("font", UiTheme.FONT_DISPLAY)
	_outline(_timer_label, 8)
	root.add_child(_timer_label)

	_status_label = Label.new()
	UiTheme.anchor_rect(_status_label, Control.PRESET_CENTER_TOP, Rect2(-300, 64, 600, 24))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_font_override("font", UiTheme.body(600))
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_outline(_status_label, 5)
	root.add_child(_status_label)

	var ability_box := PanelContainer.new()
	UiTheme.anchor_rect(ability_box, Control.PRESET_BOTTOM_LEFT, Rect2(24, -136, 304, 112))
	_ability_box_style = StyleBoxFlat.new()
	_ability_box_style.bg_color = Color(0.06, 0.07, 0.13, 0.45)
	_ability_box_style.border_color = TEAL
	_ability_box_style.set_border_width_all(2)
	_ability_box_style.set_corner_radius_all(12)
	_ability_box_style.set_content_margin_all(14)
	ability_box.add_theme_stylebox_override("panel", _ability_box_style)
	root.add_child(ability_box)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	ability_box.add_child(hbox)

	var keycap := PanelContainer.new()
	keycap.custom_minimum_size = Vector2(56, 56)
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_keycap_style = StyleBoxFlat.new()
	_keycap_style.bg_color = Color(1, 1, 1, 0.08)
	_keycap_style.border_color = TEAL
	_keycap_style.set_border_width_all(2)
	_keycap_style.set_corner_radius_all(10)
	keycap.add_theme_stylebox_override("panel", _keycap_style)
	hbox.add_child(keycap)
	_keycap_label = Label.new()
	_keycap_label.text = ABILITY_KEY
	_keycap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keycap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_keycap_label.add_theme_font_size_override("font_size", 30)
	_keycap_label.add_theme_font_override("font", UiTheme.FONT_DISPLAY)
	_keycap_label.add_theme_color_override("font_color", TEAL)
	keycap.add_child(_keycap_label)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(vbox)

	_ability_name = Label.new()
	_ability_name.add_theme_font_size_override("font_size", 20)
	_ability_name.add_theme_font_override("font", UiTheme.body(600))
	_ability_name.add_theme_color_override("font_color", TEAL)
	vbox.add_child(_ability_name)

	var bar_bg := Panel.new()
	var bar_bg_style := StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(1, 1, 1, 0.1)
	bar_bg_style.set_corner_radius_all(6)
	bar_bg.add_theme_stylebox_override("panel", bar_bg_style)
	bar_bg.custom_minimum_size = Vector2(BAR_W, 12)
	vbox.add_child(bar_bg)
	_cooldown_fill = Panel.new()
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = TEAL
	fill_style.set_corner_radius_all(6)
	_cooldown_fill.add_theme_stylebox_override("panel", fill_style)
	_cooldown_fill.size = Vector2(BAR_W, 12)
	bar_bg.add_child(_cooldown_fill)

	_ability_status = Label.new()
	_ability_status.add_theme_font_size_override("font_size", 15)
	_ability_status.add_theme_font_override("font", UiTheme.body(600))
	vbox.add_child(_ability_status)

	_flash_label = Label.new()
	UiTheme.anchor_rect(_flash_label, Control.PRESET_CENTER, Rect2(-300, -120, 600, 80))
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 56)
	_flash_label.add_theme_font_override("font", UiTheme.FONT_DISPLAY)
	_outline(_flash_label, 10)
	_flash_label.modulate.a = 0.0
	root.add_child(_flash_label)


## Dark outline so HUD text stays readable over bright sky backgrounds.
func _outline(label: Label, size: int) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.12, 0.85))
	label.add_theme_constant_override("outline_size", size)


func _process(_delta: float) -> void:
	if GameState.practice_mode:
		_timer_label.text = "PRACTICE"
		_timer_label.add_theme_color_override("font_color", TEAL)
		var n: int = GameState.practice_caught
		_status_label.text = "caught %d time%s  ·  ESC to quit" % [n, "" if n == 1 else "s"]
	elif GameState.match_running:
		var remaining := int(ceil(GameState.match_remaining))
		_timer_label.text = str(remaining)
		_timer_label.add_theme_color_override("font_color", RED if remaining <= 10 else Color.WHITE)
		var me_it := GameState.it_peer == multiplayer.get_unique_id()
		_status_label.text = "RUN — you're IT!" if me_it else "Don't get tagged!"
	else:
		# Pre-match grace: a "get ready" countdown to the auto-start. Reads off
		# the shared world_clock, so every screen shows the same number.
		var countdown := ceili(maxf(0.0, MatchDirector.PREGAME_SEC - GameState.world_clock))
		_timer_label.text = str(maxi(countdown, 1))
		_timer_label.add_theme_color_override("font_color", TEAL)
		var me_it := GameState.it_peer == multiplayer.get_unique_id()
		_status_label.text = "Get ready — you're IT!" if me_it else "Get ready to run!"

	# When the clock starts, sell it with a GO! flash on every screen.
	if GameState.match_running and not _was_running:
		_flash_label.text = "GO!"
		_flash_label.add_theme_color_override("font_color", TEAL)
		_flash_label.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_interval(0.5)
		tween.tween_property(_flash_label, "modulate:a", 0.0, 0.4)
	_was_running = GameState.match_running

	var me: Player = game.local_player() if game != null else null
	if me != null and me.player_class != null and me.player_class.primary_ability != null:
		var ability := me.player_class.primary_ability
		_ability_name.text = ability.display_name.to_upper()
		var remaining_cd := me.get_cooldown_remaining()
		if remaining_cd <= 0.0:
			_cooldown_fill.size.x = BAR_W
			_ability_status.text = "READY"
			_ability_status.add_theme_color_override("font_color", TEAL)
			_ability_box_style.border_color = TEAL
			_keycap_style.border_color = TEAL
			_keycap_label.add_theme_color_override("font_color", TEAL)
		else:
			_cooldown_fill.size.x = BAR_W * (1.0 - remaining_cd / ability.cooldown_sec)
			_ability_status.text = "%.1fs" % remaining_cd
			_ability_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
			var dim := Color(1, 1, 1, 0.22)
			_ability_box_style.border_color = dim
			_keycap_style.border_color = dim
			_keycap_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))


func flash_tag(you_are_it: bool) -> void:
	_flash_label.text = "TAG — YOU'RE IT!" if you_are_it else "TAG!"
	_flash_label.add_theme_color_override("font_color", RED if you_are_it else Color.WHITE)
	_flash_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_flash_label, "modulate:a", 0.0, 0.5)
