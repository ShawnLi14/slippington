class_name StunAbility
extends Ability
## Stun Pulse: freezes every other player within the radius for a moment.
## The owner computes targets from replicated positions and sends each one a
## reliable apply_stun RPC — each peer owns its own body, so targets freeze
## themselves. Fine for a friendly game; not cheat-proof by design.

const RADIUS := 150.0
const STUN_DURATION := 1.5


func _init() -> void:
	id = "stun"
	display_name = "Stun Pulse"
	description = "Freeze nearby players in place for a moment."
	cooldown_sec = 12.0
	duration_sec = STUN_DURATION


func execute(player: Node) -> bool:
	player.spawn_stun_burst(RADIUS)
	var game := player.get_parent()
	for other in game.get_children():
		if other == player or not other.is_in_group("players"):
			continue
		if other.global_position.distance_to(player.global_position) <= RADIUS:
			GameState.send_stun(other.peer_id, STUN_DURATION)
	return true


func play_remote_vfx(player: Node) -> void:
	player.spawn_stun_burst(RADIUS)
