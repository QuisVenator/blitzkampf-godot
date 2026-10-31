class_name DroppedWeapon
extends RigidBody3D
## A weapon tossed to the ground. It keeps the ammo it had when dropped and
## is removed once someone picks it up. The body needs continuous collision
## detection (set in the scene): without it a small thrown box occasionally
## tunnelled through the floor (about 1 in 10 drops).

## Keeps thin guns from tunnelling through the floor.
const MIN_COLLIDER_SIZE := 0.08

var _definition: WeaponDefinition
var _ammo_in_mag := 0
var _ammo_reserve := 0

@onready var _visual: Node3D = $Visual
@onready var _pickup: PickupArea = $PickupArea


## Call before adding to the scene tree.
func setup(definition: WeaponDefinition, ammo_in_mag: int, ammo_reserve: int) -> void:
	_definition = definition
	_ammo_in_mag = ammo_in_mag
	_ammo_reserve = ammo_reserve


func _ready() -> void:
	var model := _definition.model.instantiate() as Node3D
	_visual.add_child(model)
	var size := ModelBounds.center_in_parent(model) * _visual.scale
	var box := BoxShape3D.new()
	box.size = size.max(Vector3.ONE * MIN_COLLIDER_SIZE)
	$CollisionShape3D.shape = box
	_pickup.definition = _definition
	_pickup.ammo_in_mag = _ammo_in_mag
	_pickup.ammo_reserve = _ammo_reserve
	_pickup.collected.connect(queue_free)
	# The server simulates the fall; other peers just show the replicated transform.
	if not is_multiplayer_authority():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
