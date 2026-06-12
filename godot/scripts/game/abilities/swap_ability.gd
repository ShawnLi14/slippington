class_name SwapAbility
extends Ability
## Swap: instantly trade positions with the nearest player in range.
## As prey, the chaser is suddenly standing where you were; as "it", steal
## someone's safe perch. The owner teleports itself optimistically and the
## swap partner is told to teleport via a targeted RPC (each peer owns its
## own body, same pattern as Stun Pulse).

const RANGE := 300.0


func _init() -> void:
	id = "swap"
	display_name = "Swap"
	description = "Trade places with the nearest player."
	cooldown_sec = 14.0


func execute(player: Node) -> bool:
	var nearest: Node = null
	var nearest_d := RANGE
	for other in player.get_tree().get_nodes_in_group("players"):
		if other == player:
			continue
		var d: float = other.global_position.distance_to(player.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = other
	if nearest == null:
		return false  # nobody in range — no cooldown consumed
	var my_pos: Vector2 = player.global_position
	player.spawn_pulse_ring(50.0)
	player.teleport_to(nearest.global_position)
	GameState.send_swap(nearest.peer_id, my_pos)
	return true


func play_remote_vfx(player: Node) -> void:
	player.spawn_pulse_ring(50.0)
