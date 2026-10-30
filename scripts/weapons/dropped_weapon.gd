class_name DroppedWeapon
extends RigidBody3D
## A weapon tossed to the ground. It keeps the ammo it had when dropped and
## is removed once someone picks it up.

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
	_visual.add_child(_definition.model.instantiate())
	_pickup.definition = _definition
	_pickup.ammo_in_mag = _ammo_in_mag
	_pickup.ammo_reserve = _ammo_reserve
	_pickup.collected.connect(queue_free)
