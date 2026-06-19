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
