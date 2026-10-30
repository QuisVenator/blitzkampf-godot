class_name ShotEffects
extends Node3D
## Tracer lines and bullet-hole decals. Must stay at the world origin
## (top_level), since spawned effects use world-space coordinates.

const TRACER_LIFETIME := 0.1
const MARK_RADIUS := 0.035
const MARK_SURFACE_OFFSET := 0.01
## Capped and recycled oldest-first so a burst's scatter pattern stays visible.
const MAX_MARKS := 60

var _tracer_material := StandardMaterial3D.new()
var _mark_material := StandardMaterial3D.new()
var _mark_mesh := CylinderMesh.new()
var _marks: Array[MeshInstance3D] = []


func _ready() -> void:
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = Color("ffe066")

	_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_material.albedo_color = Color(0.07, 0.07, 0.07, 0.85)
	_mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mark_mesh.top_radius = MARK_RADIUS
	_mark_mesh.bottom_radius = MARK_RADIUS
	_mark_mesh.height = 0.002
	_mark_mesh.radial_segments = 10
	_mark_mesh.rings = 1
	_mark_mesh.material = _mark_material


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES, _tracer_material)
	line.surface_add_vertex(from)
	line.surface_add_vertex(to)
	line.surface_end()

	var instance := MeshInstance3D.new()
	instance.mesh = line
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	get_tree().create_timer(TRACER_LIFETIME).timeout.connect(instance.queue_free)


func spawn_impact(point: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	mark.global_position = point + normal * MARK_SURFACE_OFFSET
	mark.quaternion = Quaternion(Vector3.UP, normal)
	_marks.append(mark)

	if _marks.size() > MAX_MARKS:
		_marks.pop_front().queue_free()
