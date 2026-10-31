class_name Target
extends StaticBody3D
## Shootable dummy that flashes white when hit.

const FLASH_DURATION := 0.15

@export var color := Color(1.0, 0.267, 0.267)

var hits := 0

var _material := StandardMaterial3D.new()
var _flash_tween: Tween

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	_mesh.material_override = _material


func take_damage(_amount: int, _attacker: Node = null) -> void:
	hits += 1
	_flash()
	_flash.rpc()


@rpc("authority", "call_remote", "unreliable")
func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "emission", Color.BLACK, FLASH_DURATION).from(Color.WHITE)
