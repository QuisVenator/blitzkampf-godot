class_name WeaponDefinition
extends Resource
## Static stats and visuals of one weapon type. Add a weapon by adding a
## .tres (and a model scene), not by branching in code.

@export var id: StringName
@export var display_name := ""
## Scene with a "Muzzle" Marker3D, used for the viewmodel, pickups and drops.
@export var model: PackedScene

@export_group("Firing")
@export var fire_cooldown := 0.35
## Multiplies the fire sound's pitch so weapons sound distinct.
@export var fire_pitch_scale := 1.0

@export_group("Ammo")
@export var magazine_size := 8
## Spare rounds outside the magazine when fully stocked.
@export var reserve_ammo := 24
@export var reload_duration := 1.2

@export_group("Spread (shot cone half-angle, degrees)")
@export var ads_spread_deg := 0.1
@export var hip_spread_standing_deg := 1.2
@export var hip_spread_moving_deg := 2.4
