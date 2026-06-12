class_name MapPresets
## Hand-crafted maps. Redesigned for the real 1920x1080 playfield — the old
## repo's presets.ts still used 800x600-era coordinates (latent bug).
## Vertical gaps stay near 100px: max jump height is ~126px (450^2 / 2*800),
## so every step is comfortably reachable.

const PRESETS := {
	"arena": "Arena",
	"towers": "Towers",
}


static func get_preset(id: String) -> Dictionary:
	match id:
		"arena":
			return _arena()
		"towers":
			return _towers()
	push_error("Unknown map preset: %s" % id)
	return MapGenerator.generate(id)


static func _p(x: float, y: float, w: float, type: String = "solid") -> Dictionary:
	var h := MapGenerator.GROUND_HEIGHT if y >= 1060.0 else MapGenerator.PLATFORM_HEIGHT
	return {"rect": Rect2(x, y, w, h), "type": type}


static func _arena() -> Dictionary:
	return {
		"seed": "arena",
		"width": GameConfig.MAP_WIDTH,
		"height": GameConfig.MAP_HEIGHT,
		"platforms": [
			_p(0, 1060, 1920),                       # ground
			_p(120, 960, 360), _p(1440, 960, 360),   # lower shelves
			_p(810, 920, 300),                       # center step
			_p(300, 820, 280, "passthrough"), _p(1340, 820, 280, "passthrough"),
			_p(760, 720, 400),                       # central stage
			_p(160, 620, 240), _p(1520, 620, 240),   # upper sides
			_p(660, 520, 600, "passthrough"),        # high bridge
			_p(400, 420, 200), _p(1320, 420, 200),   # top shelves
			_p(860, 320, 200),                       # crown
		],
		"objects": [
			{"type": "spring", "pos": Vector2(200, 1053)},
			{"type": "spring", "pos": Vector2(1720, 1053)},
			{"type": "spring", "pos": Vector2(960, 713)},
		],
		"spawn_points": [
			Vector2(300, 1020), Vector2(1620, 1020),
			Vector2(960, 680), Vector2(960, 280),
		],
	}


static func _towers() -> Dictionary:
	var platforms: Array[Dictionary] = [_p(0, 1060, 1920)]
	for y in [960, 860, 760, 660, 560, 460]:
		platforms.append(_p(80, float(y), 160))      # left tower steps
		platforms.append(_p(1680, float(y), 160))    # right tower steps
	platforms.append(_p(880, 960, 160))              # center stepping stone
	platforms.append(_p(320, 710, 1280, "passthrough"))  # low bridge
	platforms.append(_p(480, 510, 960, "ice"))           # high bridge: slippery
	return {
		"seed": "towers",
		"width": GameConfig.MAP_WIDTH,
		"height": GameConfig.MAP_HEIGHT,
		"platforms": platforms,
		"objects": [
			{"type": "spring", "pos": Vector2(320, 1053)},
			{"type": "spring", "pos": Vector2(1600, 1053)},
		],
		"spawn_points": [
			Vector2(160, 1020), Vector2(1760, 1020),
			Vector2(160, 420), Vector2(1760, 420),
		],
	}
