class_name MapEnvironment
extends WorldEnvironment
## A TrenchBroom `env_world` entity (one per map): plain sky colour and flat ambient light,
## like the test arena's environment.


## Called by FuncGodot right after the node is created.
func _func_godot_apply_properties(properties: Dictionary) -> void:
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = properties.get("sky_color", Color(0.529, 0.808, 0.922))
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = properties.get("ambient_color", Color(0.85, 0.85, 0.9))
	settings.ambient_light_energy = properties.get("ambient_energy", 1.0)
	environment = settings
