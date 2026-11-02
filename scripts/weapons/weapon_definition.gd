class_name WeaponDefinition
extends Resource
## Static stats and visuals of one weapon type. Add a weapon by adding a
## .tres (and a model scene), not by branching in code.

@export var id: StringName
@export var display_name := ""
## Scene used for the viewmodel, pickups and drops. Barrel along -Z, with a
## "Muzzle" Marker3D (tracer origin) and a "Sight" Marker3D (the point that
## lines up with the screen centre while aiming down sights).
@export var model: PackedScene
## First-person scene (a `WeaponViewmodel`: gun, hands and animations). The viewmodel
## falls back to `model` when this is empty.
@export var viewmodel: PackedScene

## One-handed weapons can be wielded in pairs (akimbo); the rest need both hands.
@export var one_handed := false

@export_group("Firing")
@export var fire_cooldown := 0.35
## Multiplies the fire sound's pitch so weapons sound distinct.
@export var fire_pitch_scale := 1.0

@export_group("Aiming down sights")
## Vertical FOV (degrees) while aiming; the hip FOV is the camera's own.
@export var ads_fov := 62.0
## Seconds to raise or lower the weapon between hip and sights.
@export var ads_time := 0.15
## How far in front of the camera (m) the Sight marker sits while aiming. Larger
## for weapons whose rear (stock) would otherwise crowd the view.
@export var ads_sight_distance := 0.42

@export_group("Damage")
## Health removed per hit (one ray per shot).
@export var damage := 25

@export_group("Ammo")
@export var magazine_size := 8
## Spare rounds outside the magazine when fully stocked.
@export var reserve_ammo := 24
@export var reload_duration := 1.2

@export_group("Spread (shot cone half-angle, degrees)")
@export var ads_spread_deg := 0.1
@export var hip_spread_standing_deg := 1.2
@export var hip_spread_moving_deg := 2.4
