class_name DoppelAbility
extends Ability
## Doppel: send out a decoy that keeps running the way you were going while
## you fade out — half-transparent on your own screen so you can still play
## yourself, fully invisible on everyone else's. You stay taggable the whole
## time: the ability buys confusion, not safety. The clone pops in a puff
## when an opponent touches it or when it expires.

const CLOAK_SECS := 1.5
const SELF_ALPHA := 0.5
const CLONE_SECS := 2.5


func _init() -> void:
	id = "doppel"
	display_name = "Doppel"
	description = "Send out a decoy and vanish from enemy screens."
	cooldown_sec = 9.0
	duration_sec = CLOAK_SECS


func execute(player: Node) -> bool:
	player.spawn_decoy_clone(CLONE_SECS)
	player.start_cloak(CLOAK_SECS, SELF_ALPHA)
	return true


func play_remote_vfx(player: Node) -> void:
	# On other screens the caster vanishes completely — the clone is all
	# they have to chase.
	player.spawn_decoy_clone(CLONE_SECS)
	player.start_cloak(CLOAK_SECS, 0.0)
