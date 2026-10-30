class_name PickupArea
extends Area3D
## A weapon the player can take with the interact key. The owner (spawner or
## dropped weapon) fills in what it offers and reacts to `collected`.

signal collected

## Lower wins when several pickups are in reach (dropped weapons beat spawners).
@export var pickup_priority := 0

var definition: WeaponDefinition
## -1 means "fully stocked" (a fresh spawner weapon).
var ammo_in_mag := -1
var ammo_reserve := -1
var available := true


func collect() -> void:
	collected.emit()
