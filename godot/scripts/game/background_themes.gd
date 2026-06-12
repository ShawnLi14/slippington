class_name BackgroundThemes
## Data-driven background themes consumed by GameBackground. A theme is just a
## Dictionary of colours + flags, so adding a new map look is ~15 lines here and
## costs nothing at runtime (no art assets, no import pipeline).

## Pick a theme for a map. Presets map to a fixed look; random seeds pick
## deterministically so every client sees the same place.
static func theme_for_seed(seed_or_preset: String) -> Dictionary:
	match seed_or_preset:
		"towers":
			return frozen_lake()
		"arena":
			return sky_islands()
	return frozen_lake() if absi(hash(seed_or_preset)) % 2 == 0 else sky_islands()


static func frozen_lake() -> Dictionary:
	return {
		"sky_top": Color("#0a1030"),
		"sky_bottom": Color("#1d3f59"),
		"aurora": true,
		"aurora_a": Color("#4ecdc4"),
		"aurora_b": Color("#7c5cff"),
		"silhouettes": "mountains",
		"silhouette_color": Color("#0e1d36"),
		"cap_color": Color("#33506f"),
		"clouds": false,
		"particles": "snow",
		"particle_color": Color(0.92, 0.97, 1.0, 0.9),
	}


static func sky_islands() -> Dictionary:
	return {
		"sky_top": Color("#7ec6ff"),
		"sky_bottom": Color("#ffe2b0"),
		"sun": true,
		"sun_color": Color("#fff4cb"),
		"aurora": false,
		"silhouettes": "islands",
		"silhouette_color": Color(0.45, 0.58, 0.78, 0.5),
		"island_top_color": Color(0.62, 0.82, 0.62, 0.6),
		"clouds": true,
		"cloud_color": Color(1, 1, 1, 0.85),
		"particles": "motes",
		"particle_color": Color(1, 1, 1, 0.45),
	}
