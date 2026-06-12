class_name GameConfig
## Central gameplay constants, ported from the old lib/game/constants.ts.

const MAP_WIDTH := 1920
const MAP_HEIGHT := 1080

const GRAVITY := 800.0
const JUMP_VELOCITY := -450.0
const PLAYER_SPEED := 300.0
const PLAYER_SIZE := 40.0

const ICE_ACCEL := 700.0  # px/s^2 toward target speed while on ice

# Endgame slush: rises from the map bottom over the final seconds,
# heavily slowing anyone caught in it — forces the finish upward.
const SLUSH_FINAL_SEC := 15.0
const SLUSH_RISE := 560.0
const SLUSH_SLOW := 0.45

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
