class_name UiTheme
## Tiny shared helpers so the menu/lobby/end screens look consistent.

const TEAL := Color("#4ecdc4")
const RED := Color("#ff6b6b")
const BG := Color("#0f0f1a")
const PANEL := Color("#191b2e")

# --- Playful-Party palette (extends the originals above) ---
const INK := Color("#2b2350")     # outlines, borders, text-on-light, hard shadows
const CREAM := Color("#fff7ec")   # card / input fill
const CORAL := RED                # alias: primary action / danger / IT
const SUN := Color("#ffd93d")     # secondary accent (JOIN, highlights)

# --- Fonts (bundled, OFL) ---
const FONT_DISPLAY := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const _FONT_BODY_SRC := preload("res://assets/fonts/Fredoka-VariableFont_wdth,wght.ttf")

## Fredoka is a variable font; expose weighted instances. Cached so we build each once.
static var _body_cache := {}
static func body(weight := 500) -> FontVariation:
	if not _body_cache.has(weight):
		var fv := FontVariation.new()
		fv.base_font = _FONT_BODY_SRC
		fv.variation_opentype = {"wght": float(weight)}
		_body_cache[weight] = fv
	return _body_cache[weight]


static func title(text: String, size := 42) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT_DISPLAY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 6)
	return l


static func label(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body(500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## accent=true keeps the CORAL primary fill from the Theme; accent=false
## recolors to neutral CREAM (secondary actions like LEAVE / JOIN-by-default).
static func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 48)
	if not accent:
		_apply_button_instance(b, CREAM, INK)
	return b


## Per-instance recolor (reuses the Theme's geometry via the same builder).
static func _apply_button_instance(b: Button, fill: Color, fg: Color) -> void:
	var tmp := Theme.new()
	_apply_button(tmp, "Button", fill, fg)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, tmp.get_stylebox(s, "Button"))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL, Color(1, 1, 1, 0.10), 1, 16))
	return p


static func pill(text: String, size := 14, fg := INK, bg := CREAM) -> PanelContainer:
	var p := PanelContainer.new()
	var box := _box(bg, INK, 2, 18)
	box.content_margin_left = 12; box.content_margin_right = 12
	box.content_margin_top = 4; box.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", box)
	var l := label(text, size, fg)
	l.add_theme_font_override("font", body(600))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## The global Theme. Applied once at the root (see main.gd) so every control
## inherits the party look and no Godot default styling leaks through.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body(500)
	t.default_font_size = 16

	# Labels
	t.set_color("font_color", "Label", Color.WHITE)

	# Buttons — chunky party look: thick INK border, heavy bottom edge = depth.
	_apply_button(t, "Button", CORAL, Color.WHITE)
	t.set_font("font", "Button", FONT_DISPLAY)
	t.set_font_size("font_size", "Button", 18)

	# OptionButton shares Button styling; its popup is themed too.
	_apply_button(t, "OptionButton", CREAM, INK)
	t.set_font("font", "OptionButton", body(600))
	t.set_font_size("font_size", "OptionButton", 16)
	var popup := _box(INK.darkened(0.1), CREAM, 2, 10)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", SUN)

	# LineEdit — cream field, INK border.
	var le := _box(CREAM, INK, 3, 10)
	le.content_margin_left = 12; le.content_margin_right = 12
	le.content_margin_top = 6; le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	var le_focus := le.duplicate(); le_focus.border_color = TEAL
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_font("font", "LineEdit", body(500))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK.lightened(0.45))
	t.set_color("caret_color", "LineEdit", INK)

	# PanelContainer — cards/panels.
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(1,1,1,0.10), 1, 14))
	return t


## A party button stylebox set (normal/hover/pressed/disabled) on `type`.
## Depth comes from a heavy INK bottom border; pressed reduces it so the button
## "sits down". No custom drawing needed.
static func _apply_button(t: Theme, type: String, fill: Color, fg: Color) -> void:
	var normal := _box(fill, INK, 3, 14)
	normal.border_width_bottom = 7
	normal.content_margin_top = 9; normal.content_margin_bottom = 9
	normal.content_margin_left = 16; normal.content_margin_right = 16
	var hover := normal.duplicate(); hover.bg_color = fill.lightened(0.10)
	var pressed := normal.duplicate()
	pressed.border_width_bottom = 3
	pressed.content_margin_top = 13; pressed.content_margin_bottom = 5
	var disabled := normal.duplicate(); disabled.bg_color = fill.darkened(0.25); disabled.border_color = INK.lightened(0.3)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, hover.duplicate())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg)
	t.set_color("font_pressed_color", type, fg)


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	return s


## Anchor a control with a rect expressed relative to the anchor point.
## (Setting .position after an anchor preset is wrong — position is always
## parent-relative; offsets are what's anchor-relative.)
static func anchor_rect(c: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.position.x + rect.size.x
	c.offset_bottom = rect.position.y + rect.size.y


static func fullscreen_bg(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -1
	parent.add_child(bg)


## The game's animated sky + a readability veil — shared by menu screens.
static func menu_backdrop(parent: Control) -> void:
	var bg := GameBackground.new()
	bg.bg_theme = BackgroundThemes.sky_islands()
	parent.add_child(bg)
	var veil := ColorRect.new()
	veil.color = Color(0.05, 0.06, 0.12, 0.42)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(veil)
