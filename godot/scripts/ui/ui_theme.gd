class_name UiTheme
## Tiny shared helpers so the menu/lobby/end screens look consistent.

const TEAL := Color("#4ecdc4")
const RED := Color("#ff6b6b")
const BG := Color("#0f0f1a")
const PANEL := Color("#191b2e")


static func title(text: String, size := 42) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEAL)
	return label


static func label(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 18)
	if accent:
		var style := StyleBoxFlat.new()
		style.bg_color = TEAL
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		b.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = TEAL.lightened(0.15)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_color_override("font_color", Color("#0f0f1a"))
		b.add_theme_color_override("font_hover_color", Color("#0f0f1a"))
	return b


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", style)
	return p


static func fullscreen_bg(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -1
	parent.add_child(bg)
