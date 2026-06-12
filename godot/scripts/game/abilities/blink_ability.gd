class_name BlinkAbility
extends Ability
## Blink: instantly teleport a short distance in the facing direction.
## Ported from the old BlinkAbility.ts (150px, 10s cooldown, bounds-clamped).

const BLINK_DISTANCE := 150.0


func _init() -> void:
	id = "blink"
	display_name = "Blink"
	description = "Instantly teleport a short distance in your facing direction."
	cooldown_sec = 10.0


func execute(player: Node) -> bool:
	var direction := 1.0 if player.facing_right else -1.0
	var half := GameConfig.PLAYER_SIZE / 2.0
	var target_x: float = clampf(
		player.global_position.x + BLINK_DISTANCE * direction,
		half,
		GameConfig.MAP_WIDTH - half
	)
	player.spawn_blink_trail(player.global_position, Vector2(target_x, player.global_position.y))
	player.global_position.x = target_x
	return true


func play_remote_vfx(player: Node) -> void:
	player.flash_ability_vfx(id)
