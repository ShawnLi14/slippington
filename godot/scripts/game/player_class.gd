class_name PlayerClass
extends Resource
## A playable class: stat multipliers + primary ability.

@export var id := ""
@export var display_name := ""
@export var description := ""
@export var speed_mult := 1.0
@export var jump_mult := 1.0
@export var mass_mult := 1.0
var primary_ability: Ability


func _init(p_id := "", p_name := "", p_desc := "", p_speed := 1.0, p_jump := 1.0, p_mass := 1.0, p_ability: Ability = null) -> void:
	id = p_id
	display_name = p_name
	description = p_desc
	speed_mult = p_speed
	jump_mult = p_jump
	mass_mult = p_mass
	primary_ability = p_ability
