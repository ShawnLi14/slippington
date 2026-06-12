class_name GameBackground
extends CanvasLayer
## Themed, animated in-match backdrop. Replaces the old flat ColorRect with a
## layered sky: gradient + optional sun/aurora + parallax silhouettes + drifting
## clouds + ambient particles. Everything is built procedurally from a theme
## Dictionary (see BackgroundThemes), so it costs ~nothing to ship and a new map
## look is just new data. Lives on a negative CanvasLayer so it sits behind the
## world (platforms/players, layer 0) and the HUD.

const AURORA_SHADER := preload("res://scripts/game/aurora.gdshader")

const MAP_W := float(GameConfig.MAP_WIDTH)
const MAP_H := float(GameConfig.MAP_HEIGHT)

var bg_theme: Dictionary = {}


func _ready() -> void:
	layer = -10
	if bg_theme.is_empty():
		bg_theme = BackgroundThemes.frozen_lake()

	# Deterministic per-map layout so the scene looks intentional and identical
	# across reconnects (cosmetic, so cross-client exactness isn't required).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(GameState.map_seed)

	_build_sky()
	if bg_theme.get("sun", false):
		_build_sun()
	if bg_theme.get("aurora", false):
		_build_aurora()
	_build_silhouettes(rng)
	if bg_theme.get("clouds", false):
		_build_clouds(rng)
	_build_particles()


func _build_sky() -> void:
	var grad := Gradient.new()
	grad.set_color(0, bg_theme["sky_top"])
	grad.set_color(1, bg_theme["sky_bottom"])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)  # vertical
	tex.width = 8
	tex.height = 256
	var sky := TextureRect.new()
	sky.texture = tex
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.position = Vector2.ZERO
	sky.size = Vector2(MAP_W, MAP_H)
	add_child(sky)


func _build_sun() -> void:
	var sun := TextureRect.new()
	sun.texture = _radial(bg_theme["sun_color"])
	sun.stretch_mode = TextureRect.STRETCH_SCALE
	var d := 820.0
	sun.size = Vector2(d, d)
	sun.position = Vector2(MAP_W * 0.70 - d * 0.5, MAP_H * 0.24 - d * 0.5)
	add_child(sun)


func _build_aurora() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = AURORA_SHADER
	mat.set_shader_parameter("color_a", bg_theme.get("aurora_a", Color("#4ecdc4")))
	mat.set_shader_parameter("color_b", bg_theme.get("aurora_b", Color("#7c5cff")))
	var rect := ColorRect.new()
	rect.material = mat
	rect.color = Color(1, 1, 1, 1)  # shader writes the real colour + alpha
	rect.position = Vector2.ZERO
	rect.size = Vector2(MAP_W, MAP_H)
	add_child(rect)


func _build_silhouettes(rng: RandomNumberGenerator) -> void:
	match bg_theme.get("silhouettes", ""):
		"mountains":
			# Two ranges for depth: a paler far range, a darker capped near range.
			add_child(_mountain_layer(rng, MAP_H * 0.94, 200.0, 340.0,
				bg_theme["silhouette_color"].lightened(0.18), 6, false))
			add_child(_mountain_layer(rng, MAP_H + 10.0, 300.0, 470.0,
				bg_theme["silhouette_color"], 5, true))
		"islands":
			add_child(_island_layer(rng))


func _mountain_layer(rng: RandomNumberGenerator, base_y: float, h_min: float,
		h_max: float, color: Color, count: int, capped: bool) -> BgLayer:
	var layer := BgLayer.new()
	var step := (MAP_W + 400.0) / float(count)
	for i in count:
		var w := rng.randf_range(420.0, 760.0)
		var e := {
			"type": "mountain",
			"x": -200.0 + step * i + rng.randf_range(-60.0, 60.0),
			"base_y": base_y,
			"w": w,
			"h": rng.randf_range(h_min, h_max),
			"color": color,
		}
		if capped:
			e["cap_color"] = bg_theme["cap_color"]
		layer.elements.append(e)
	return layer


func _island_layer(rng: RandomNumberGenerator) -> BgLayer:
	var layer := BgLayer.new()
	layer.scroll_speed = 4.0
	layer.wrap_span = MAP_W + 700.0
	var count := 4
	var step := (MAP_W + 300.0) / float(count)
	for i in count:
		layer.elements.append({
			"type": "island",
			"x": -150.0 + step * i + rng.randf_range(-50.0, 50.0),
			"y": rng.randf_range(180.0, 600.0),
			"w": rng.randf_range(120.0, 250.0),
			"color": bg_theme["silhouette_color"],
			"top_color": bg_theme["island_top_color"],
		})
	return layer


func _build_clouds(rng: RandomNumberGenerator) -> void:
	# Far layer: small, slow, faint. Near layer: bigger, faster, solid.
	add_child(_cloud_layer(rng, 5, 0.45, 8.0, 0.5))
	add_child(_cloud_layer(rng, 4, 0.95, 22.0, 1.0))


func _cloud_layer(rng: RandomNumberGenerator, count: int, scale: float,
		speed: float, alpha: float) -> BgLayer:
	var layer := BgLayer.new()
	layer.scroll_speed = speed
	layer.wrap_span = MAP_W + 700.0
	var base: Color = bg_theme.get("cloud_color", Color(1, 1, 1, 0.85))
	var color := Color(base.r, base.g, base.b, base.a * alpha)
	var step := (MAP_W + 400.0) / float(count)
	for i in count:
		layer.elements.append({
			"type": "cloud",
			"x": -200.0 + step * i + rng.randf_range(-80.0, 80.0),
			"y": rng.randf_range(80.0, MAP_H * 0.5),
			"scale": scale * rng.randf_range(0.8, 1.3),
			"color": color,
		})
	return layer


func _build_particles() -> void:
	match bg_theme.get("particles", ""):
		"snow":
			_add_particles(140, 20.0, Vector2(MAP_W * 0.5, -20.0),
				Vector2(MAP_W * 0.5, 4.0), Vector2(0.15, 1.0), 6.0,
				Vector2(6, 0), 45.0, 75.0, 0.15, 0.4)
		"motes":
			_add_particles(60, 14.0, Vector2(MAP_W * 0.5, MAP_H * 0.5),
				Vector2(MAP_W * 0.5, MAP_H * 0.5), Vector2(0, -1.0), 55.0,
				Vector2(0, -2), 6.0, 16.0, 0.1, 0.3)


func _add_particles(amount: int, lifetime: float, pos: Vector2, extents: Vector2,
		direction: Vector2, spread: float, gravity: Vector2, vmin: float,
		vmax: float, smin: float, smax: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = _radial(Color.WHITE)
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime  # pre-fill so the screen isn't empty on spawn
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.direction = direction
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color = bg_theme.get("particle_color", Color.WHITE)
	add_child(p)


## White core fading to transparent — used for the sun glow and soft particles.
func _radial(core: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, core)
	g.set_color(1, Color(core.r, core.g, core.b, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t
