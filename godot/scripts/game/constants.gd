class_name GameConfig
## Central gameplay constants, ported from the old lib/game/constants.ts.

const MAP_WIDTH := 1920
const MAP_HEIGHT := 1080

## The running game version — single source of truth for the menu label, the
## host-authoritative join gate, and the auto-update check. BUMP THIS every
## release (and keep export_presets.cfg's version fields in sync). A forgotten
## bump makes the new build reject same-release joiners.
const GAME_VERSION := "2.1.0"

const GRAVITY := 800.0
const JUMP_VELOCITY := -450.0
const PLAYER_SPEED := 300.0
const PLAYER_SIZE := 40.0

const ICE_ACCEL := 700.0  # px/s^2 toward target speed while on ice

## Minimum clear space between neighboring platforms — and between any
## platform and the map border. 2.5 player-widths: enough to fall through
## cleanly, so layouts read as islands rather than broken floors. (The
## full-width ground is the deliberate exception.)
const PLATFORM_GAP := 100.0

const TAG_RANGE := 40.0
const TAG_IMMUNITY_SEC := 1.5
const MATCH_DURATION_SEC := 60.0

const SYNC_HZ := 60.0
const MAX_PLAYERS := 8

const PLAYER_COLORS: Array[Color] = [
	Color("#ff6b6b"), Color("#4ecdc4"), Color("#45b7d1"), Color("#96ceb4"),
	Color("#ffeaa7"), Color("#dfe6e9"), Color("#fd79a8"), Color("#a29bfe"),
	Color("#6c5ce7"), Color("#00b894"), Color("#e17055"), Color("#74b9ff"),
]

# Collision layers
const LAYER_WORLD := 1
const LAYER_PASSTHROUGH := 2
