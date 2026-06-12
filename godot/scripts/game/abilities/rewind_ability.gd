class_name RewindAbility
extends Ability
## Rewind: snap back to where you were 2 seconds ago. A ghost "echo" marks
## the destination for a beat before the teleport, so chasers get a read —
## the skill is making your past position a good future one. The owner keeps
## its own short position history (see Player._record_echo); puppets keep an
## approximate one from the sync stream so remote screens can show the
## telegraph too.

const REWIND_SECS := 2.0
const TELEGRAPH_SECS := 0.3
## A rewind that goes nowhere is a no-op — don't burn the cooldown.
const MIN_DISTANCE := 60.0


func _init() -> void:
	id = "rewind"
	display_name = "Rewind"
	description = "Snap back to where you were 2 seconds ago."
	cooldown_sec = 9.0


func execute(player: Node) -> bool:
	var past: Dictionary = player.get_echo_state(REWIND_SECS)
	if (past["pos"] as Vector2).distance_to(player.global_position) < MIN_DISTANCE:
		return false
	player.start_rewind(past["pos"], past["vel"], TELEGRAPH_SECS)
	return true


func play_remote_vfx(player: Node) -> void:
	# Telegraph at this client's own view of the puppet's trail — close
	# enough for a read; the actual snap arrives exactly via position sync.
	var past: Dictionary = player.get_echo_state(REWIND_SECS)
	player.spawn_echo_marker(past["pos"], TELEGRAPH_SECS)
