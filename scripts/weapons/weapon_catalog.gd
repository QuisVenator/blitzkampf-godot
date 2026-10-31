class_name WeaponCatalog
extends Resource
## Every weapon in the game, looked up by `WeaponDefinition.id`. The network will
## send ids, not Resources. Add a weapon to `resources/weapons/catalog.tres`.

const DEFAULT_PATH := "res://resources/weapons/catalog.tres"

@export var weapons: Array[WeaponDefinition] = []

static var _default: WeaponCatalog


static func get_default() -> WeaponCatalog:
	if _default == null:
		_default = load(DEFAULT_PATH)
	return _default


func find(id: StringName) -> WeaponDefinition:
	for definition in weapons:
		if definition.id == id:
			return definition
	return null
