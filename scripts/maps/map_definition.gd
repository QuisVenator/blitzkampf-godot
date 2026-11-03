class_name MapDefinition
extends Resource
## One playable map: either a hand-made scene (`scene`) or a TrenchBroom map
## (`map_file`, built at game start by FuncGodot; see `Main._load_map`).

@export var id: StringName
@export var display_name := ""
@export var scene: PackedScene
@export_file("*.map") var map_file := ""
