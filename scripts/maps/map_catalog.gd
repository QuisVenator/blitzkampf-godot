class_name MapCatalog
extends Resource
## Every map the game can start, looked up by `MapDefinition.id`. The first one is the
## default. Add a map to `resources/maps/catalog.tres`.

const DEFAULT_PATH := "res://resources/maps/catalog.tres"

@export var maps: Array[MapDefinition] = []

static var _default: MapCatalog


static func get_default() -> MapCatalog:
	if _default == null:
		_default = load(DEFAULT_PATH)
	return _default


## The map with this id, or null.
func find(id: StringName) -> MapDefinition:
	for definition in maps:
		if definition.id == id:
			return definition
	return null


## The map with this id, or the first one when the id is empty or unknown.
func find_or_default(id: StringName) -> MapDefinition:
	var found := find(id)
	return found if found else maps[0]
