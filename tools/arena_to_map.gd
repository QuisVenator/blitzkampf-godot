extends SceneTree
## One-off converter: writes scenes/maps/test_arena.tscn (CSG boxes, spawn markers, weapon
## spawners, targets, sun, environment) as a TrenchBroom map, maps/test_arena.map. Kept as
## a record of how the starter map came to be; new maps are made in TrenchBroom.
## Run: godot --headless --path . -s res://tools/arena_to_map.gd
##
## Coordinates: one Godot metre is 32 TrenchBroom units, and FuncGodot maps Quake
## (x, y, z) to Godot (y, z, x): qx = gz, qy = gx, qz = gy (times 32).

const ARENA := "res://scenes/maps/test_arena.tscn"
const OUT := "res://maps/test_arena.map"
const SCALE := 32.0

var _bodies := ""
var _entities := ""


func _initialize() -> void:
	var arena := (load(ARENA) as PackedScene).instantiate()
	var colors: Dictionary = (load("res://tools/make_textures.gd") as GDScript).get_script_constant_map()["COLORS"]
	for node in arena.get_children():
		if node is CSGBox3D:
			var box := node as CSGBox3D
			var material := box.material as StandardMaterial3D
			_bodies += _brush(box.position - box.size / 2.0, box.position + box.size / 2.0, _texture_for(material.albedo_color, colors))
		elif node is Marker3D:
			_point("player_spawn", node.position - Vector3(0, 0.0, 0), {"angle": _angle(node)})
		elif node is WeaponSpawner:
			_point("weapon_spawner", node.position - Vector3(0, 0.04, 0), {"weapons": str(_mask(node.offers))})
		elif node.scene_file_path == "res://scenes/world/target.tscn":
			_point("target", node.position, {})
		elif node is DirectionalLight3D:
			var euler := (node as Node3D).basis.get_euler() * (180.0 / PI)
			_point("env_sun", Vector3.ZERO, {"angles": "%s %s %s" % [snappedf(-euler.x, 0.01), snappedf(euler.y - 180.0, 0.01), snappedf(-euler.z, 0.01)]})
		elif node is WorldEnvironment:
			var environment := (node as WorldEnvironment).environment
			_point("env_world", Vector3(0, 8, 0), {
				"sky_color": _color(environment.background_color),
				"ambient_color": _color(environment.ambient_light_color),
			})
	DirAccess.make_dir_recursive_absolute("res://maps")
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string('{\n"classname" "worldspawn"\n%s}\n%s' % [_bodies, _entities])
	file.close()
	print("wrote ", OUT)
	quit()


## Godot position to TrenchBroom units.
func _quake(position: Vector3) -> Vector3:
	return Vector3(position.z, position.x, position.y) * SCALE


func _texture_for(color: Color, colors: Dictionary) -> String:
	var best := ""
	var best_distance := INF
	for texture_name: String in colors:
		var c: Color = colors[texture_name]
		var distance := Vector3(c.r - color.r, c.g - color.g, c.b - color.b).length()
		if distance < best_distance:
			best_distance = distance
			best = texture_name
	return "prototype/" + best


## Brush text for a box from `low` to `high` (Godot coordinates). Each face is three points
## on its plane, ordered so the normal (p2 - p0) x (p1 - p0) points outward.
func _brush(low: Vector3, high: Vector3, texture: String) -> String:
	var a := _quake(low)
	var b := _quake(high)
	var mins := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var maxs := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var faces := [
		[Vector3(-1, 0, 0), mins, Vector3(mins.x, maxs.y, mins.z), Vector3(mins.x, mins.y, maxs.z)],
		[Vector3(1, 0, 0), Vector3(maxs.x, mins.y, mins.z), Vector3(maxs.x, mins.y, maxs.z), Vector3(maxs.x, maxs.y, mins.z)],
		[Vector3(0, -1, 0), mins, Vector3(mins.x, mins.y, maxs.z), Vector3(maxs.x, mins.y, mins.z)],
		[Vector3(0, 1, 0), Vector3(mins.x, maxs.y, mins.z), Vector3(maxs.x, maxs.y, mins.z), Vector3(mins.x, maxs.y, maxs.z)],
		[Vector3(0, 0, -1), mins, Vector3(maxs.x, mins.y, mins.z), Vector3(mins.x, maxs.y, mins.z)],
		[Vector3(0, 0, 1), Vector3(mins.x, mins.y, maxs.z), Vector3(mins.x, maxs.y, maxs.z), Vector3(maxs.x, mins.y, maxs.z)],
	]
	var text := "{\n"
	for face in faces:
		var normal: Vector3 = face[0]
		var p0: Vector3 = face[1]
		var p1: Vector3 = face[2]
		var p2: Vector3 = face[3]
		if (p2 - p0).cross(p1 - p0).dot(normal) < 0.0:
			var swap := p1
			p1 = p2
			p2 = swap
		text += "( %s ) ( %s ) ( %s ) %s 0 0 0 1 1\n" % [_point_text(p0), _point_text(p1), _point_text(p2), texture]
	return text + "}\n"


func _point_text(p: Vector3) -> String:
	return "%d %d %d" % [roundi(p.x), roundi(p.y), roundi(p.z)]


func _point(classname: String, position: Vector3, properties: Dictionary) -> void:
	var text := '{\n"classname" "%s"\n"origin" "%s"\n' % [classname, _point_text(_quake(position))]
	for key: String in properties:
		text += '"%s" "%s"\n' % [key, properties[key]]
	_entities += text + "}\n"


## TrenchBroom `angle` for a marker facing where the player will look: the marker's yaw is
## `angle + 180` degrees (FuncGodot), and the player's yaw is the marker's.
func _angle(marker: Node3D) -> int:
	return roundi(rad_to_deg(marker.rotation.y)) - 180


func _color(color: Color) -> String:
	return "%d %d %d" % [color.r8, color.g8, color.b8]


func _mask(offers: Array[WeaponDefinition]) -> int:
	var mask := 0
	for definition in offers:
		mask |= 1 << definition.map_bit
	return mask
