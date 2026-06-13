class_name BotDifficulty
extends RefCounted
## Tunable knobs that scale a bot from a forgiving sparring partner to a
## ruthless one. The same nav + policy code runs at every tier; only these
## numbers change.
##
## - reaction:     seconds between re-decisions. Higher = slower to react to a
##                 juke (it chases where you WERE), the main "easiness" lever.
## - lead:         how much of the prey's velocity the chaser leads by, in
##                 seconds. 0 = tails (easy to dodge); higher = cuts you off.
## - evade_smart:  true = flee to the best escape surface; false = just run
##                 away horizontally (and corner yourself, like a newbie).
## - ability_chance: probability of taking a good ability opportunity.
## - hesitate:     chance per decision to freeze for a beat (newbie dithering).

static func params(level: String) -> Dictionary:
	match level:
		"easy":
			return {"reaction": 0.36, "lead": 0.0, "evade_smart": false, "ability_chance": 0.35, "hesitate": 0.12}
		"hard":
			return {"reaction": 0.05, "lead": 0.55, "evade_smart": true, "ability_chance": 1.0, "hesitate": 0.0}
		_:  # medium (default)
			return {"reaction": 0.16, "lead": 0.30, "evade_smart": true, "ability_chance": 0.75, "hesitate": 0.0}


static func levels() -> Array:
	return ["easy", "medium", "hard"]
