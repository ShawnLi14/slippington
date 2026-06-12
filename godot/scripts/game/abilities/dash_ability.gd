class_name DashAbility
extends Ability
## Dash: a short horizontal burst of speed. Gravity is ignored during the
## dash so it can be used to cross gaps or close a tag.

const DASH_SPEED := 900.0
const DASH_DURATION := 0.25


func _init() -> void:
	id = "dash"
	display_name = "Dash"
	description = "Burst forward at high speed for a moment."
	cooldown_sec = 6.0
	duration_sec = DASH_DURATION


func execute(player: Node) -> bool:
	player.start_dash(DASH_SPEED, DASH_DURATION)
	return true
