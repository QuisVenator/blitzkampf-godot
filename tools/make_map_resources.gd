extends SceneTree
## Regenerates the TrenchBroom/FuncGodot resources in resources/maps/: the entity
## definitions (FGD), the map settings and the TrenchBroom game config. The weapon
## spawner's weapon checkboxes come from the weapon catalog, so rerun this after adding
## a weapon (and give it a unique `WeaponDefinition.map_bit`).
## Run: godot --headless --path . -s res://tools/make_map_resources.gd
## Then export to TrenchBroom: tools/export_trenchbroom.gd

const FGD_PATH := "res://resources/maps/blitzkampf_fgd.tres"
const SETTINGS_PATH := "res://resources/maps/map_settings.tres"
const CONFIG_PATH := "res://resources/maps/trenchbroom_config.tres"
const ADDON_FGD := "res://addons/func_godot/fgd/func_godot_fgd.tres"
const SPAWNER_SCENE := "res://scenes/weapons/weapon_spawner.tscn"
const TARGET_SCENE := "res://scenes/world/target.tscn"
const GAME_NAME := "Blitzkampf"


func _initialize() -> void:
	var fgd := _make_fgd()
	_save(fgd, FGD_PATH)
	fgd = load(FGD_PATH)

	var settings := FuncGodotMapSettings.new()
	settings.entity_fgd = fgd
	settings.base_texture_dir = "res://textures"
	# Maps are built at runtime, possibly from an exported game: nothing may be written to res://.
	settings.save_generated_materials = false
	# The addon's own default material samples nearest-neighbour; ours filters with mipmaps and
	# anisotropy (the textures need mipmaps enabled in their import settings too).
	settings.default_material = load("res://resources/maps/default_material.tres")
	_save(settings, SETTINGS_PATH)

	var config := TrenchBroomGameConfig.new()
	config.game_name = GAME_NAME
	config.fgd_file = fgd
	config.textures_root_folder = "textures"
	config.default_uv_scale = Vector2(0.125, 0.125)  # 512 px textures cover 2 m
	config.palette_path = "addons/func_godot/palette.lmp"
	_save(config, CONFIG_PATH)
	quit()


func _make_fgd() -> FuncGodotFGDFile:
	var fgd := FuncGodotFGDFile.new()
	fgd.fgd_name = GAME_NAME
	fgd.base_fgd_files = [load(ADDON_FGD)]
	fgd.entity_definitions = [_player_spawn(), _weapon_spawner(), _target(), _sun(), _world()]
	return fgd


func _player_spawn() -> FuncGodotFGDPointClass:
	var entity := FuncGodotFGDPointClass.new()
	entity.classname = "player_spawn"
	entity.description = "Where players appear. Place it on the floor; the arrow shows where they look."
	entity.node_class = "Marker3D"
	entity.node_groups = ["player_spawn"]
	entity.class_properties = {"angle": 0.0}
	entity.class_property_descriptions = {"angle": "Facing (yaw, degrees)"}
	# FuncGodot writes an AABB as "position, size"; TrenchBroom wants "mins, maxs".
	entity.meta_properties = {"size": AABB(Vector3(-16, -16, 0), Vector3(16, 16, 58)), "color": Color(0.2, 0.9, 0.3)}
	return entity


func _weapon_spawner() -> FuncGodotFGDPointClass:
	var flags: Array = []
	var bits := {}
	for definition in WeaponCatalog.get_default().weapons:
		assert(not bits.has(definition.map_bit), "%s and %s share map_bit %d" % [definition.id, bits.get(definition.map_bit), definition.map_bit])
		bits[definition.map_bit] = definition.id
		flags.append([definition.display_name, 1 << definition.map_bit, 1])
	var entity := FuncGodotFGDPointClass.new()
	entity.classname = "weapon_spawner"
	entity.description = "Offers one of the ticked weapons (none ticked = all) and offers another after it was taken."
	entity.scene_file = load(SPAWNER_SCENE)
	entity.class_properties = {"weapons": flags, "respawn_delay": 8.0}
	entity.class_property_descriptions = {"respawn_delay": "Seconds until a new weapon appears"}
	entity.meta_properties = {"size": AABB(Vector3(-16, -16, 0), Vector3(16, 16, 16)), "color": Color(1.0, 0.6, 0.1)}
	return entity


func _target() -> FuncGodotFGDPointClass:
	var entity := FuncGodotFGDPointClass.new()
	entity.classname = "target"
	entity.description = "A practice target (a sphere that flashes when hit). The origin is its centre."
	entity.scene_file = load(TARGET_SCENE)
	entity.meta_properties = {"size": AABB(Vector3(-16, -16, -16), Vector3(16, 16, 16)), "color": Color(1.0, 0.2, 0.2)}
	return entity


func _sun() -> FuncGodotFGDPointClass:
	var entity := FuncGodotFGDPointClass.new()
	entity.classname = "env_sun"
	entity.description = "Directional light. Pitch Yaw Roll in 'angles': pitch 90 shines straight down."
	entity.node_class = "MapSun"
	entity.class_properties = {"angles": Vector3(50, 45, 0), "energy": 1.0, "color": Color(1, 1, 1), "shadows": false}
	entity.class_property_descriptions = {"angles": "Pitch Yaw Roll", "energy": "Light energy", "shadows": "Cast shadows"}
	entity.meta_properties = {"size": AABB(Vector3(-8, -8, -8), Vector3(8, 8, 8)), "color": Color(1.0, 0.9, 0.3)}
	return entity


func _world() -> FuncGodotFGDPointClass:
	var entity := FuncGodotFGDPointClass.new()
	entity.classname = "env_world"
	entity.description = "Sky colour and ambient light. One per map."
	entity.node_class = "MapEnvironment"
	entity.class_properties = {"sky_color": Color(0.529, 0.808, 0.922), "ambient_color": Color(0.85, 0.85, 0.9), "ambient_energy": 1.0}
	entity.class_property_descriptions = {"sky_color": "Background colour", "ambient_color": "Flat ambient light colour", "ambient_energy": "Ambient light energy"}
	entity.meta_properties = {"size": AABB(Vector3(-8, -8, -8), Vector3(8, 8, 8)), "color": Color(0.4, 0.7, 1.0)}
	return entity


func _save(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	print("%s %s" % [path, error_string(error)])
	if error != OK:
		quit(1)
