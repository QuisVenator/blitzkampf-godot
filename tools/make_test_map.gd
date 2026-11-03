extends SceneTree
## Generates maps/test_large.map: an 80 x 80 m level for trying out TrenchBroom editing and
## the game (hall with a catwalk, ramps, stairs, a sniper platform, cover, a row of
## ledges to test the ledge climb, 8 spawns, 8 weapon spawners, targets). It is a starting
## point: after the first save in TrenchBroom the .map is the source of truth, so don't
## rerun this on top of your edits.
## Run: godot --headless --path . -s res://tools/make_test_map.gd

const OUT := "res://maps/test_large.map"
const CONCRETE := "ambientcg/concrete"
const BRICKS := "ambientcg/bricks"
const METAL := "ambientcg/metal"
const PAINTED := "ambientcg/painted_metal"
const TILES := "ambientcg/tiles"

var _map := MapWriter.new()


func _initialize() -> void:
	_floor()
	_outer_walls()
	_hall()
	_ramps_and_stairs()
	_cover()
	_ledge_row()
	_entities()
	_map.save(OUT)
	print("wrote ", OUT)
	quit()


func _box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, texture: String) -> void:
	_map.box(Vector3(x0, y0, z0), Vector3(x1, y1, z1), texture)


## Concrete everywhere except tiles inside the hall; separate slabs so no faces overlap.
func _floor() -> void:
	_box(-40, -1, -40, -12, 0, 40, CONCRETE)
	_box(12, -1, -40, 40, 0, 40, CONCRETE)
	_box(-12, -1, -40, 12, 0, -12, CONCRETE)
	_box(-12, -1, 12, 12, 0, 40, CONCRETE)
	_box(-12, -1, -12, 12, 0, 12, TILES)


func _outer_walls() -> void:
	_box(-41, -1, -41, 41, 10, -40, BRICKS)
	_box(-41, -1, 40, 41, 10, 41, BRICKS)
	_box(-41, -1, -40, -40, 10, 40, BRICKS)
	_box(40, -1, -40, 41, 10, 40, BRICKS)


## A 24 m square hall, 5 m walls with a 4 m wide, 3.5 m high doorway in the middle of every
## side, and a 3 m wide catwalk at 3 m height along the inside of the walls.
func _hall() -> void:
	for side in [-1.0, 1.0]:
		var edge: float = 12.0 * side
		var outer: float = edge + 0.5 * side
		var inner: float = edge - 0.5 * side
		# North/south walls (along x) and east/west walls (along z): two pieces + a lintel each.
		for pair in [[-12.5, -2.0], [2.0, 12.5]]:
			_box(pair[0], 0, minf(outer, inner), pair[1], 5, maxf(outer, inner), BRICKS)
			_box(minf(outer, inner), 0, pair[0], maxf(outer, inner), 5, pair[1], BRICKS)
		_box(-2.0, 3.5, minf(outer, inner), 2.0, 5, maxf(outer, inner), BRICKS)
		_box(minf(outer, inner), 3.5, -2.0, maxf(outer, inner), 5, 2.0, BRICKS)
	# Catwalk: a ring just inside the walls (x/z from 8.5 to 11.5), top at 3 m.
	_box(-11.5, 2.7, -11.5, 11.5, 3.0, -8.5, METAL)
	_box(-11.5, 2.7, 8.5, 11.5, 3.0, 11.5, METAL)
	_box(-11.5, 2.7, -8.5, -8.5, 3.0, 8.5, METAL)
	_box(8.5, 2.7, -8.5, 11.5, 3.0, 8.5, METAL)


func _ramps_and_stairs() -> void:
	# Hall ramp up to the north end of the catwalk (rises toward -z, 3 m over 16.5 m).
	_map.ramp(Vector3(-8, 0, -8.5), Vector3(-5, 3, 8), false, false, METAL)
	# Stairs (12 steps of 25 cm, rising toward -z) to a 3 m platform in the north-east.
	_map.stairs(Vector3(20, 0, -10), 3, 0.5, 0.25, 12, CONCRETE)
	_box(17, 0, -28, 29, 3, -16, METAL)
	# Sniper platform in the west with a long ramp up (rises toward -x, 3.5 m over 12 m).
	_box(-40, 0, 10, -34, 3.5, 22, METAL)
	_map.ramp(Vector3(-34, 0, 10), Vector3(-22, 3.5, 13), false, true, METAL)


func _cover() -> void:
	# Pillars.
	for corner in [Vector2(-25, -25), Vector2(25, -25), Vector2(-25, 25), Vector2(25, 25)]:
		_box(corner.x - 0.5, 0, corner.y - 0.5, corner.x + 0.5, 6, corner.y + 0.5, CONCRETE)
	# Low walls (1.2 m, jumpable) and crate stacks.
	_box(-30, 0, -8, -22, 1.2, -7.5, BRICKS)
	_box(22, 0, 14, 30, 1.2, 14.5, BRICKS)
	_box(-6, 0, -30, 6, 1.2, -29.5, BRICKS)
	for crate in [Vector3(-4, 0, 4), Vector3(4.2, 0, -4.2), Vector3(-3, 0, -3)]:
		_box(crate.x - 0.75, 0, crate.z - 0.75, crate.x + 0.75, 1.5, crate.z + 0.75, PAINTED)
	_box(-3.5, 1.5, -3.5, -2.5, 2.5, -2.5, PAINTED)
	_box(26, 0, 26, 28, 1.0, 28, PAINTED)
	_box(28, 0, 28, 30, 2.0, 30, PAINTED)
	_box(-28, 0, 28, -26, 1.5, 30, PAINTED)


## Blocks of rising height in a row on the south side: 0.5, 1.0, 1.5 m can be climbed,
## 1.9 and 2.2 m are too high (tests the ledge climb rule).
func _ledge_row() -> void:
	var heights := [0.5, 1.0, 1.5, 1.9, 2.2]
	for i in heights.size():
		var x := -16.0 + i * 3.5
		_box(x, 0, 33, x + 2.0, heights[i], 35, PAINTED)


func _entities() -> void:
	# Eight spawns around the edge, facing the middle.
	var spawns := [
		Vector3(-34, 0.5, -34), Vector3(34, 0.5, -34), Vector3(-34, 0.5, 34), Vector3(34, 0.5, 34),
		Vector3(0, 0.5, -34), Vector3(0, 0.5, 26), Vector3(-34, 0.5, 0), Vector3(34, 0.5, 0),
	]
	for position: Vector3 in spawns:
		var forward := Vector2(-position.x, -position.z).normalized()
		var yaw := rad_to_deg(atan2(-forward.x, -forward.y))
		_map.point("player_spawn", position, {"angle": roundi(yaw - 180.0)})
	# Weapon spawners; "weapons" is a bit mask over the weapons' map_bit (pistol 1, SMG 2, shotgun 4, none = all).
	var spawners := [
		[Vector3(0, 0, 0), 0], [Vector3(-9, 3, -10), 4], [Vector3(24, 3, -22), 6],
		[Vector3(-37, 3.5, 16), 4], [Vector3(-25, 0, -25), 3], [Vector3(25, 0, 20), 2],
		[Vector3(0, 0, -36), 1], [Vector3(0, 0, 30), 7],
	]
	for entry in spawners:
		_map.point("weapon_spawner", entry[0], {"weapons": entry[1], "respawn_delay": 8})
	for x in [-24, -12, 0, 12, 24]:
		_map.point("target", Vector3(x, 1.5, -37))
	_map.point("env_sun", Vector3(0, 12, 0), {"angles": "54.74 -135 0"})
	_map.point("env_world", Vector3(0, 14, 0), {"sky_color": "135 206 235", "ambient_color": "217 217 230", "ambient_energy": 0.5})
