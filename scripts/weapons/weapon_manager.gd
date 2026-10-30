class_name WeaponManager
extends Node
## Owns the player's held weapon: firing, spread, ammo, reload, pickup and
## dropping. Everything else (HUD, audio, viewmodel) listens to its signals.

signal weapon_changed(definition: WeaponDefinition)
signal ammo_changed(in_mag: int, reserve: int)
signal reloading_changed(reloading: bool)
signal spread_changed(degrees: float)
signal aiming_changed(aiming: bool)
signal fired(definition: WeaponDefinition)
signal reload_started(definition: WeaponDefinition)
signal hit_confirmed
signal picked_up

const MAX_RANGE := 100.0
## Horizontal speed (m/s) above which hip-fire uses the "moving" spread.
const MOVING_SPEED_THRESHOLD := 0.5
const MUZZLE_FALLBACK_DISTANCE := 0.3
## Physics layers a bullet hits: world (1) and target (3).
const BULLET_MASK := (1 << 0) | (1 << 2)
const COOLDOWN_EPSILON := 0.0001

const RECOIL_KICK := 0.08
const RECOIL_KICK_ADS_SCALE := 0.4
const RECOIL_RECOVERY_TIME := 0.2

const THROW_ORIGIN_HEIGHT := 1.1
const THROW_FORWARD_OFFSET := 0.3
const THROW_FORWARD_SPEED := 3.2
const THROW_UP_SPEED := 2.6
const THROW_MAX_TUMBLE := 4.5

@export var starting_weapon: WeaponDefinition
@export var dropped_weapon_scene: PackedScene

var definition: WeaponDefinition
var in_mag := 0
var reserve := 0

var _cooldown := 0.0
var _reload_left := 0.0
var _spread_deg := -1.0
var _viewmodel: Node3D
var _recoil_tween: Tween
var _aiming := false
var _pose_tween: Tween
var _hip_position := Vector3.ZERO
var _hip_yaw := 0.0
var _hip_fov := 75.0

@onready var _player: Player = get_parent()
@onready var _camera: Camera3D = $"../Head/Camera3D"
@onready var _holder: Node3D = $"../Head/Camera3D/WeaponHolder"
@onready var _effects: ShotEffects = $ShotEffects


func _ready() -> void:
	_hip_position = _holder.position
	_hip_yaw = _holder.rotation.y
	_hip_fov = _camera.fov
	equip(starting_weapon)


func is_reloading() -> bool:
	return _reload_left > 0.0


func is_aiming() -> bool:
	return _aiming


func current_spread_deg() -> float:
	return _spread_deg


## Equips `new_definition`. Omit the ammo to get a fresh, fully stocked weapon.
func equip(new_definition: WeaponDefinition, mag := -1, spare := -1) -> void:
	definition = new_definition
	in_mag = new_definition.magazine_size if mag < 0 else mag
	reserve = new_definition.reserve_ammo if spare < 0 else spare
	_cooldown = 0.0
	_reload_left = 0.0
	_rebuild_viewmodel()
	_move_to_pose(_aiming)
	weapon_changed.emit(definition)
	ammo_changed.emit(in_mag, reserve)
	reloading_changed.emit(false)


func _physics_process(delta: float) -> void:
	_update_aiming()
	_update_spread()

	if GameInput.just_pressed(&"interact"):
		_try_interact()
	if GameInput.just_pressed(&"reload"):
		_start_reload()

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return

	_cooldown -= delta
	if GameInput.held(&"fire") and _cooldown <= COOLDOWN_EPSILON and in_mag > 0:
		_cooldown = definition.fire_cooldown
		in_mag -= 1
		ammo_changed.emit(in_mag, reserve)
		_fire()


## Sights come up while the aim button is held, and drop for a reload.
func _update_aiming() -> void:
	var wants_aim := GameInput.held(&"aim") and not is_reloading()
	if wants_aim == _aiming:
		return
	_aiming = wants_aim
	_move_to_pose(_aiming)
	aiming_changed.emit(_aiming)


## Tweens the weapon holder and camera FOV to the hip or the aiming pose.
## Aiming puts the model's "Sight" marker on the camera axis.
func _move_to_pose(aiming: bool) -> void:
	var target_position := _hip_position
	var target_yaw := _hip_yaw
	var target_fov := _hip_fov
	if aiming:
		var sight := _viewmodel.get_node_or_null(^"Sight") as Node3D
		var sight_in_holder := _viewmodel.basis * sight.position if sight else Vector3.ZERO
		target_position = Vector3(0.0, 0.0, -definition.ads_sight_distance) - sight_in_holder
		target_yaw = 0.0
		target_fov = definition.ads_fov

	if _pose_tween:
		_pose_tween.kill()
	_pose_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(_holder, "position", target_position, definition.ads_time)
	_pose_tween.tween_property(_holder, "rotation:y", target_yaw, definition.ads_time)
	_pose_tween.tween_property(_camera, "fov", target_fov, definition.ads_time)


func _update_spread() -> void:
	var degrees: float
	if _aiming:
		degrees = definition.ads_spread_deg
	elif _player.horizontal_speed() > MOVING_SPEED_THRESHOLD:
		degrees = definition.hip_spread_moving_deg
	else:
		degrees = definition.hip_spread_standing_deg
	if not is_equal_approx(degrees, _spread_deg):
		_spread_deg = degrees
		spread_changed.emit(degrees)


func _fire() -> void:
	var origin := _camera.global_position
	var direction := _apply_spread(-_camera.global_basis.z, _camera.global_basis)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_RANGE, BULLET_MASK)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)

	var muzzle := origin + direction * MUZZLE_FALLBACK_DISTANCE
	var muzzle_marker := _viewmodel.get_node_or_null(^"Muzzle") as Node3D if _viewmodel else null
	if muzzle_marker:
		muzzle = muzzle_marker.global_position

	if hit.is_empty():
		_effects.spawn_tracer(muzzle, origin + direction * MAX_RANGE)
	else:
		_effects.spawn_tracer(muzzle, hit["position"])
		_effects.spawn_impact(hit["position"], hit["normal"])
		var collider: Object = hit["collider"]
		if collider.has_method(&"take_hit"):
			collider.take_hit()
			hit_confirmed.emit()

	_kick_recoil()
	fired.emit(definition)


## Random direction inside the shot cone (half-angle `_spread_deg`).
func _apply_spread(forward: Vector3, basis: Basis) -> Vector3:
	if _spread_deg <= 0.0:
		return forward
	var spread := deg_to_rad(_spread_deg)
	var spin := randf() * TAU
	# sqrt() samples the cone's circular cross-section uniformly instead of
	# bunching shots toward the centre.
	var cone := sqrt(randf()) * spread
	return (forward * cos(cone) + basis.x * sin(cone) * cos(spin) + basis.y * sin(cone) * sin(spin)).normalized()


## Kicks the model itself (not the holder), so recoil never fights the aim tween.
func _kick_recoil() -> void:
	if _recoil_tween:
		_recoil_tween.kill()
	_viewmodel.position.z = RECOIL_KICK * (RECOIL_KICK_ADS_SCALE if _aiming else 1.0)
	_recoil_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(_viewmodel, "position:z", 0.0, RECOIL_RECOVERY_TIME)


func _start_reload() -> void:
	if is_reloading() or in_mag >= definition.magazine_size or reserve <= 0:
		return
	_reload_left = definition.reload_duration
	reloading_changed.emit(true)
	reload_started.emit(definition)


func _finish_reload() -> void:
	var transferred := mini(definition.magazine_size - in_mag, reserve)
	in_mag += transferred
	reserve -= transferred
	ammo_changed.emit(in_mag, reserve)
	reloading_changed.emit(false)


func _rebuild_viewmodel() -> void:
	if _recoil_tween:
		_recoil_tween.kill()
	if _viewmodel:
		_holder.remove_child(_viewmodel)
		_viewmodel.queue_free()
	_viewmodel = definition.model.instantiate()
	_holder.add_child(_viewmodel)


func _try_interact() -> void:
	var best: PickupArea = null
	var best_distance := INF
	for area in _player.interact_area.get_overlapping_areas():
		var pickup := area as PickupArea
		if pickup == null or not pickup.available:
			continue
		var distance := _player.global_position.distance_squared_to(pickup.global_position)
		if best == null or pickup.pickup_priority < best.pickup_priority or (pickup.pickup_priority == best.pickup_priority and distance < best_distance):
			best = pickup
			best_distance = distance
	if best == null:
		return

	# The held weapon is always dropped, even when picking up the same type:
	# ammo belongs to the weapon instance, not the weapon type.
	_drop_current()
	equip(best.definition, best.ammo_in_mag, best.ammo_reserve)
	best.collect()
	picked_up.emit()


func _drop_current() -> void:
	var dropped := dropped_weapon_scene.instantiate() as DroppedWeapon
	dropped.setup(definition, in_mag, reserve)
	_player.get_parent().add_child(dropped)

	var forward := Vector3(-sin(_player.yaw), 0.0, -cos(_player.yaw))
	dropped.global_position = _player.global_position + forward * THROW_FORWARD_OFFSET + Vector3.UP * THROW_ORIGIN_HEIGHT
	dropped.linear_velocity = forward * THROW_FORWARD_SPEED + Vector3.UP * THROW_UP_SPEED
	dropped.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * THROW_MAX_TUMBLE
