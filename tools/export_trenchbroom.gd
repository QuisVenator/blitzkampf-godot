extends SceneTree
## Writes the TrenchBroom game configuration (GameConfig.cfg, icon, FGD) into the repo
## (trenchbroom/Blitzkampf/) and links it into TrenchBroom's user games folder
## (~/.TrenchBroom/games/Blitzkampf), so "Blitzkampf" shows up in
## TrenchBroom's New Map dialog and the files stay under version control. Rerun after
## changing entities (tools/make_map_resources.gd). In TrenchBroom's preferences set the
## game path of Blitzkampf to this project's folder (printed below).
## Run: godot --headless --path . -s res://tools/export_trenchbroom.gd [-- <games folder to link into>]

const CONFIG_PATH := "res://resources/maps/trenchbroom_config.tres"
const LOCAL_CONFIG := "user://func_godot_config.json"
## Inside the project; TrenchBroom reads it through a link (see `_link`).
const CONFIG_FOLDER := "trenchbroom/Blitzkampf"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := args[0] if not args.is_empty() else OS.get_environment("HOME").path_join(".TrenchBroom/games")
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var folder := project.path_join(CONFIG_FOLDER)

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
	_link(games.path_join("Blitzkampf"), folder)
	print("TrenchBroom game path (preferences > Games > Blitzkampf): ", project)
	quit()


## Makes `link` (inside TrenchBroom's games folder) point at the repo's config folder.
func _link(link: String, target: String) -> void:
	var dir := DirAccess.open("/")
	if DirAccess.dir_exists_absolute(link) and not dir.is_link(link):
		printerr("%s is a real folder, not linked to the repo; delete it and rerun" % link)
		return
	DirAccess.make_dir_recursive_absolute(link.get_base_dir())
	if dir.is_link(link):
		DirAccess.remove_absolute(link)
	var error := dir.create_link(target, link)
	print("linked %s -> %s (%s)" % [link, target, error_string(error)])
