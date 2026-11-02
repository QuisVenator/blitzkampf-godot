class_name WeaponViewmodel
extends Node3D
## Root of a weapon's first-person scene: the gun, the hands holding it and an
## `AnimationPlayer` with "draw", "fire", "fire_ads" and "reload". The scene origin is
## the weapon's grip (the holder places and aims it). Built and animated in the
## editor: select the hands or the gun and move/rotate them (a finger curls by
## rotating its joints around X), keyframe in the animation panel. The animations
## start and end at the default pose, as in the RESET animation.
##
## `support_hand` is the hand that only steadies the gun; it is hidden when two
## one-handed weapons are held (each hand has its own gun).

@export var support_hand: Node3D

@onready var _animations := get_node_or_null("AnimationPlayer") as AnimationPlayer


## Plays `animation` if this viewmodel has it, stretched to `duration` seconds
## (0 = its own length).
func play(animation: StringName, duration := 0.0) -> void:
	if _animations == null or not _animations.has_animation(animation):
		return
	var length := _animations.get_animation(animation).length
	_animations.speed_scale = length / duration if duration > 0.0 else 1.0
	_animations.play(animation)


func has_animation(animation: StringName) -> bool:
	return _animations != null and _animations.has_animation(animation)


## Akimbo: each hand has its own gun, so the free hand is hidden; the left gun is
## this same scene mirrored.
func set_akimbo(enabled: bool, left_hand: bool) -> void:
	if support_hand:
		support_hand.visible = not enabled
	scale.x = -1.0 if left_hand else 1.0
