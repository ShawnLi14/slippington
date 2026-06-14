class_name BuildAbility
extends Ability
## Ledge (Mason): conjure a temporary one-way platform just below your feet —
## an air save or an instant high ground. Anyone can stand on
## it (it cuts both ways: the tagger gets a step up too), and it can be
## dropped through like any thru platform. Crumbles after a few seconds.

const LEDGE_SECS := 4.0


func _init() -> void:
	id = "build"
	display_name = "Ledge"
	description = "Conjure a platform under your feet for a few seconds."
	cooldown_sec = 8.0
	duration_sec = LEDGE_SECS


func execute(player: Node) -> bool:
	player.spawn_conjured_ledge(LEDGE_SECS)
	return true


func play_remote_vfx(player: Node) -> void:
	# Not just VFX: every client needs the collision body locally, because
	# each peer runs its own player's physics on its own copy of the world.
	player.spawn_conjured_ledge(LEDGE_SECS)
