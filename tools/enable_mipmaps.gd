extends SceneTree
## Makes new textures import with mipmaps (Project Settings > Import Defaults > Texture2D >
## Mipmaps > Generate); without them 3D surfaces seen from afar shimmer and show moire.
## Textures that were already imported keep their own .import settings: tick Mipmaps >
## Generate in the Import dock, or edit `mipmaps/generate` in their .import file, and reimport.
## Run once: godot --headless --path . -s res://tools/enable_mipmaps.gd


func _initialize() -> void:
	var defaults: Dictionary = ProjectSettings.get_setting("importer_defaults/texture", {})
	defaults["mipmaps/generate"] = true
	ProjectSettings.set_setting("importer_defaults/texture", defaults)
	print("importer_defaults/texture = ", defaults, " (", error_string(ProjectSettings.save()), ")")
	quit()
