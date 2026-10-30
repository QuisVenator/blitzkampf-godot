class_name WeaponSlot
extends RefCounted
## One hand's worth of weapon state: what is held, its ammo, timers and the
## viewmodel shown for it. `WeaponManager` owns two (primary right, secondary
## left); an empty slot has no `definition`.

var definition: WeaponDefinition
var in_mag := 0
var reserve := 0
var cooldown := 0.0
var reload_left := 0.0
var spread_deg := -1.0

## Node the viewmodel hangs under, and its resting (hip) pose.
var holder: Node3D
var hip_position := Vector3.ZERO
var hip_yaw := 0.0
var viewmodel: Node3D
var recoil_tween: Tween


func _init(holder_node: Node3D) -> void:
	holder = holder_node
	hip_position = holder_node.position
	hip_yaw = holder_node.rotation.y


func is_empty() -> bool:
	return definition == null


func is_reloading() -> bool:
	return reload_left > 0.0


func muzzle_marker() -> Node3D:
	return viewmodel.find_child("Muzzle", true, false) as Node3D if viewmodel else null
