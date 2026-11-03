extends SceneTree
## Writes the TrenchBroom game configuration (GameConfig.cfg, icon, FGD) for this project
## to TrenchBroom's user games folder, so "Blitzkampf" shows up in TrenchBroom's New Map
## dialog. Rerun after changing entities (tools/make_map_resources.gd).
## Run: godot --headless --path . -s res://tools/export_trenchbroom.gd [-- <games folder>]
## Default folder: ~/.config/TrenchBroom/games/Blitzkampf. In TrenchBroom's preferences
## set the game path of Blitzkampf to this project's folder (printed below).

const CONFIG_PATH := "res://resources/maps/trenchbroom_config.tres"
const LOCAL_CONFIG := "user://func_godot_config.json"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else OS.get_environment("HOME").path_join(".config/TrenchBroom/games/Blitzkampf")
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")

	# FuncGodot reads where to export from this per-machine file (kept if it already has other settings).
	var settings := {}
	if FileAccess.file_exists(LOCAL_CONFIG):
		settings = JSON.parse_string(FileAccess.get_file_as_string(LOCAL_CONFIG))
	settings["TRENCHBROOM_GAME_CONFIG_FOLDER"] = folder
	settings["MAP_EDITOR_GAME_PATH"] = project
	var file := FileAccess.open(LOCAL_CONFIG, FileAccess.WRITE)
	file.store_line(JSON.stringify(settings))
	file.close()

	(load(CONFIG_PATH) as TrenchBroomGameConfig).export_file()
	print("TrenchBroom game path (preferences > Games > Blitzkampf): ", project)
	quit()
