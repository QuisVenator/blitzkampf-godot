class_name MapWriter
extends RefCounted
## Writes a Quake `.map` (Standard format, as TrenchBroom saves it) from Godot-space
## shapes: boxes, wedges (ramps) and point entities. Positions are metres in Godot axes
## (x east, y up, z south); output is 32 units per metre with FuncGodot's axis mapping
## (qx = gz, qy = gx, qz = gy). Used by the map generator tools in tools/.

const SCALE := 32.0
## UV scale the maps use: a 512 px texture covers 2 m.
const UV_SCALE := 0.125

var _brushes := ""
var _entities := ""


## Brush entity text for the geometry added so far (worldspawn) followed by the point entities.
func text() -> String:
	return '// Game: Blitzkampf\n// Format: Standard\n{\n"classname" "worldspawn"\n%s}\n%s' % [_brushes, _entities]


func save(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text())
	file.close()


## A box from `low` to `high` (metres, Godot axes).
func box(low: Vector3, high: Vector3, texture: String) -> void:
	var v := PackedVector3Array()
	for i in 8:
		v.append(Vector3(
			high.x if i & 1 else low.x,
			high.y if i & 2 else low.y,
			high.z if i & 4 else low.z))
	# Corner index bits: 1 = +x, 2 = +y, 4 = +z.
	_convex(v, [[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]], texture)


## A ramp over the footprint `low`..`high` (x, z; floor at `low.y`) whose top reaches
## `high.y` at its high side. It rises along z (toward `high.z` when `rise_to_high`, else
## toward `low.z`), or along x when `along_x`.
func ramp(low: Vector3, high: Vector3, rise_to_high: bool, along_x: bool, texture: String) -> void:
	# Corners of the footprint at floor level, then the two top corners on the high side.
	var a := Vector3(low.x, low.y, low.z)
	var b := Vector3(high.x, low.y, low.z)
	var c := Vector3(high.x, low.y, high.z)
	var d := Vector3(low.x, low.y, high.z)
	var up := Vector3(0, high.y - low.y, 0)
	var v: PackedVector3Array
	var faces: Array
	if along_x:
		# Rises along x: the high side is x = high.x (or low.x).
		var hi := [b, c] if rise_to_high else [a, d]
		var lo := [a, d] if rise_to_high else [b, c]
		v = PackedVector3Array([lo[0], lo[1], hi[0], hi[1], hi[0] + up, hi[1] + up])
		# 0,1 low edge (floor), 2,3 high edge floor, 4,5 high edge top.
		faces = [[0, 1, 3, 2], [0, 2, 4], [1, 5, 3], [2, 3, 5, 4], [0, 4, 5, 1]]
	else:
		var hi := [d, c] if rise_to_high else [a, b]
		var lo := [a, b] if rise_to_high else [d, c]
		v = PackedVector3Array([lo[0], lo[1], hi[0], hi[1], hi[0] + up, hi[1] + up])
		faces = [[0, 1, 3, 2], [0, 2, 4], [1, 5, 3], [2, 3, 5, 4], [0, 4, 5, 1]]
	_convex(v, faces, texture)


## Steps rising along -z from `start` (the lowest step's front-bottom-left corner) : `count`
## boxes `width` wide, each `run` deep and `rise` higher than the one before.
func stairs(start: Vector3, width: float, run: float, rise: float, count: int, texture: String) -> void:
	for i in count:
		box(
			Vector3(start.x, start.y, start.z - run * (i + 1)),
			Vector3(start.x + width, start.y + rise * (i + 1), start.z - run * i),
			texture)


func point(classname: String, position: Vector3, properties := {}) -> void:
	var text := '{\n"classname" "%s"\n"origin" "%s"\n' % [classname, _units(_quake(position))]
	for key: String in properties:
		text += '"%s" "%s"\n' % [key, properties[key]]
	_entities += text + "}\n"


func _quake(p: Vector3) -> Vector3:
	return Vector3(p.z, p.x, p.y) * SCALE


func _units(p: Vector3) -> String:
	return "%d %d %d" % [roundi(p.x), roundi(p.y), roundi(p.z)]


## A convex brush from its corner points and faces (index lists, any winding).
func _convex(points: PackedVector3Array, faces: Array, texture: String) -> void:
	var q := PackedVector3Array()
	var centre := Vector3.ZERO
	for p in points:
		var u := _quake(p)
		u = Vector3(roundi(u.x), roundi(u.y), roundi(u.z))
		q.append(u)
		centre += u
	centre /= q.size()
	var text := "{\n"
	for face: Array in faces:
		var p0 := q[face[0]]
		var p1 := q[face[1]]
		var p2 := q[face[2]]
		# TrenchBroom wants (p2 - p0) x (p1 - p0) to point out of the brush.
		if (p2 - p0).cross(p1 - p0).dot(p0 - centre) < 0.0:
			var swap := p1
			p1 = p2
			p2 = swap
		text += "( %s ) ( %s ) ( %s ) %s 0 0 0 %s %s\n" % [_units(p0), _units(p1), _units(p2), texture, UV_SCALE, UV_SCALE]
	_brushes += text + "}\n"
