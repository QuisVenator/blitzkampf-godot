class_name BotInput
extends InputSource
## A simple AI that plays a `Player`: wanders, turns away from walls, and shoots at
## the nearest enemy it can see. No navigation mesh yet, so it is a sparring
## partner for testing rather than a real opponent. Runs on the server only.

const SIGHT_MASK := 1 << 0
const FIRE_RANGE := 40.0
const TURN_RATE := 5.0
## Aim error in radians, re-rolled every AIM_ERROR_INTERVAL seconds.
const AIM_ERROR := 0.05
const AIM_ERROR_INTERVAL := 0.4
const FIRE_ANGLE := 0.07
const WALL_PROBE := 2.0
const TARGET_CHEST := 1.2
const STRAFE_INTERVAL := 1.3
const WANDER_TURN_INTERVAL := 3.0

var _yaw := 0.0
var _pitch := 0.0
var _aim_error := Vector2.ZERO
var _aim_error_timer := 0.0
var _strafe := 1.0
var _strafe_timer := 0.0
var _wander_timer := 0.0
var _wander_yaw := 0.0
var _initialised := false


func sample(input: PlayerInput) -> InputFrame:
	var player := input.get_parent() as Player
	var frame := InputFrame.new()
	var delta := 1.0 / Engine.physics_ticks_per_second
	if not _initialised:
		_initialised = true
		_yaw = player.yaw
		_wander_yaw = _yaw
	frame.yaw = _yaw
	frame.pitch = _pitch
	if not player.alive:
		return frame

	var weapons := player.get_node("WeaponManager") as WeaponManager
	_aim_error_timer -= delta
	if _aim_error_timer <= 0.0:
		_aim_error_timer = AIM_ERROR_INTERVAL
		_aim_error = Vector2(randfn(0.0, AIM_ERROR), randfn(0.0, AIM_ERROR))
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = STRAFE_INTERVAL * randf_range(0.6, 1.4)
		_strafe = -_strafe

	var target := _nearest_enemy(player)
	var desired_yaw := _wander_yaw
	var desired_pitch := 0.0
	var visible_target := false
	if target:
		var to_target := _chest(target) - player.head.global_position
		visible_target = _can_see(player, _chest(target))
		desired_yaw = atan2(-to_target.x, -to_target.z)
		desired_pitch = asin(clampf(to_target.normalized().y, -1.0, 1.0))
		_wander_yaw = desired_yaw
		if not visible_target:
			desired_pitch = 0.0
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = WANDER_TURN_INTERVAL * randf_range(0.5, 1.5)
			_wander_yaw = randf() * TAU
		desired_yaw = _wander_yaw

	if _blocked_ahead(player, desired_yaw):
		_wander_yaw += PI * randf_range(0.4, 0.9) * (1.0 if randf() < 0.5 else -1.0)
		desired_yaw = _wander_yaw
	_yaw = _turn_towards(_yaw, desired_yaw + _aim_error.x, TURN_RATE * delta)
	_pitch = move_toward(_pitch, desired_pitch + _aim_error.y, TURN_RATE * delta)
	frame.yaw = _yaw
	frame.pitch = _pitch

	# Always advance; strafe too while an enemy is in sight.
	frame.move = Vector2(_strafe if visible_target else 0.0, -1.0 if not visible_target else -0.3)
	if visible_target:
		var aimed := absf(angle_difference(_yaw, desired_yaw)) < FIRE_ANGLE
		frame.fire = aimed and player.head.global_position.distance_to(_chest(target)) < FIRE_RANGE
		frame.fire_secondary = frame.fire
	if weapons.primary.in_mag == 0 or (not visible_target and weapons.primary.in_mag < weapons.primary.definition.magazine_size):
		frame.reload_pressed = true
	return frame


func _nearest_enemy(player: Player) -> Player:
	var best: Player
	var best_distance := INF
	for sibling in player.get_parent().get_children():
		var other := sibling as Player
		if other == null or other == player or not other.alive:
			continue
		var distance := player.global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _chest(target: Player) -> Vector3:
	return target.global_position + Vector3.UP * TARGET_CHEST


func _can_see(player: Player, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.head.global_position, point, SIGHT_MASK)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _blocked_ahead(player: Player, yaw: float) -> bool:
	var origin := player.global_position + Vector3.UP * 0.5
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * WALL_PROBE, SIGHT_MASK)
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _turn_towards(current: float, target: float, max_step: float) -> float:
	return current + clampf(angle_difference(current, target), -max_step, max_step)
