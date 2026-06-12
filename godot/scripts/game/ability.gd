class_name Ability
extends Resource
## Base class for player abilities. Subclasses override execute(); it runs
## optimistically on the owning peer (instant feel), then the use is reported
## to the host for cooldown validation and rebroadcast as remote VFX.

@export var id := ""
@export var display_name := ""
@export var description := ""
@export var cooldown_sec := 10.0
@export var duration_sec := 0.0


## Apply the ability's effect to the local (authority) player.
## Returns true if the ability fired (false = blocked, no cooldown consumed).
func execute(_player: Node) -> bool:
	return false


## Play the visual effect on a remote peer's screen (no gameplay effect).
func play_remote_vfx(player: Node) -> void:
	if player.has_method("flash_ability_vfx"):
		player.flash_ability_vfx(id)
