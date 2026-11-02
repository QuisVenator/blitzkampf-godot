extends Node
## Put on a node that should exist only in the editor (a preview camera): it removes
## itself when the game runs. (Not a `@tool` script, so it does nothing in the editor.)


func _ready() -> void:
	queue_free()
