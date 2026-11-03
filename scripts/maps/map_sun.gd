class_name MapSun
extends DirectionalLight3D
## A TrenchBroom `env_sun` entity. Its direction comes from the entity's `angles`
## (pitch yaw roll), the rest from the properties below.


## Called by FuncGodot right after the node is created.
func _func_godot_apply_properties(properties: Dictionary) -> void:
	light_energy = properties.get("energy", 1.0)
	light_color = properties.get("color", Color.WHITE)
	shadow_enabled = properties.get("shadows", false)
