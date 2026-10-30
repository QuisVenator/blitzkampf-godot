class_name WeaponManager
extends Node
## Owns the player's held weapons: firing, spread, ammo, reload, pickup and
## dropping. Everything else (HUD, audio, viewmodel) listens to its signals.
##
## There are two slots, primary (right hand) and secondary (left hand). One-handed
## weapons can fill both (akimbo). With two weapons the sights are unavailable:
## LMB (`fire`) shoots the primary and RMB (`fire_secondary`) the secondary. That
## button scheme is a deliberate default that may become configurable later; the
## two roles are separate Input Map actions so rebinding needs no code change.
## Two-handed weapons always occupy the primary slot alone.

## `definition` is null when the slot has just been emptied.
signal weapon_changed(slot: int, definition: WeaponDefinition)
signal ammo_changed(slot: int, in_mag: int, reserve: int)
signal reloading_changed(slot: int, reloading: bool)
signal spread_changed(degrees: float)
signal aiming_changed(aiming: bool)
signal fired(definition: WeaponDefinition)
signal reload_started(definition: WeaponDefinition)
signal hit_confirmed
signal picked_up

const PRIMARY := 0
const SECONDARY := 1

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
## Sideways offset per hand so two weapons dropped together don't overlap.
const THROW_SIDE_OFFSET := 0.12
const THROW_FORWARD_SPEED := 3.2
const THROW_UP_SPEED := 2.6
const THROW_MAX_TUMBLE := 4.5

@export var starting_weapon: WeaponDefinition
@export var dropped_weapon_scene: PackedScene

var primary: WeaponSlot
var secondary: WeaponSlot

var _slots: Array[WeaponSlot] = []
## Slots waiting for the reload in progress to finish (left hand goes first).
var _reload_queue: Array[int] = []
var _crosshair_spread_deg := -1.0
var _aiming := false
var _pose_tween: Tween
var _hip_fov := 75.0

@onready var _player: Player = get_parent()
@onready var _camera: Camera3D = $"../Head/Camera3D"
@onready var _effects: ShotEffects = $ShotEffects


func _ready() -> void:
	_hip_fov = _camera.fov
	primary = WeaponSlot.new($"../Head/Camera3D/WeaponHolder")
	secondary = WeaponSlot.new($"../Head/Camera3D/WeaponHolderLeft")
	_slots = [primary, secondary]
	equip(PRIMARY, starting_weapon)


## True while any weapon is reloading or waiting to; firing is blocked meanwhile.
func is_reloading() -> bool:
	return primary.is_reloading() or secondary.is_reloading() or not _reload_queue.is_empty()


func is_aiming() -> bool:
	return _aiming


func is_akimbo() -> bool:
	return not secondary.is_empty()


## The crosshair spread: the widest cone of the weapons held.
func current_spread_deg() -> float:
	return _crosshair_spread_deg


## Puts `new_definition` into a slot. Omit the ammo to get a fresh, fully stocked weapon.
func equip(slot_index: int, new_definition: WeaponDefinition, mag := -1, spare := -1) -> void:
	var slot := _slots[slot_index]
	slot.definition = new_definition
	slot.in_mag = new_definition.magazine_size if mag < 0 else mag
	slot.reserve = new_definition.reserve_ammo if spare < 0 else spare
	slot.cooldown = 0.0
	slot.reload_left = 0.0
	_reload_queue.erase(slot_index)
	_rebuild_viewmodel(slot)
	_advance_reload_queue()
	_move_to_pose(_aiming)
	_update_spread()
	weapon_changed.emit(slot_index, new_definition)
	ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
	reloading_changed.emit(slot_index, false)


func _clear(slot_index: int) -> void:
	var slot := _slots[slot_index]
	slot.definition = null
	slot.reload_left = 0.0
	_reload_queue.erase(slot_index)
	_rebuild_viewmodel(slot)
	_advance_reload_queue()
	_update_spread()
	weapon_changed.emit(slot_index, null)
	reloading_changed.emit(slot_index, false)


func _physics_process(delta: float) -> void:
	_update_aiming()
	_update_spread()

	if GameInput.just_pressed(&"interact"):
		_try_pickup(false)
	elif GameInput.just_pressed(&"interact_alt"):
		_try_pickup(true)
	if GameInput.just_pressed(&"reload"):
		_start_reload()

	_tick_slot(PRIMARY, &"fire", delta)
	_tick_slot(SECONDARY, &"fire_secondary", delta)


func _tick_slot(slot_index: int, fire_action: StringName, delta: float) -> void:
	var slot := _slots[slot_index]
	if slot.is_empty():
		return
	if slot.reload_left > 0.0:
		slot.reload_left -= delta
		if slot.reload_left <= 0.0:
			_finish_reload(slot_index)
		return

	slot.cooldown -= delta
	if GameInput.held(fire_action) and not is_reloading() and slot.cooldown <= COOLDOWN_EPSILON and slot.in_mag > 0:
		slot.cooldown = slot.definition.fire_cooldown
		slot.in_mag -= 1
		ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
		_fire(slot)


## Sights come up while the aim button is held. They drop for a reload and are
## unavailable while wielding two weapons (the aim button's role there is firing).
func _update_aiming() -> void:
	var wants_aim := GameInput.held(&"aim") and not is_akimbo() and not primary.is_reloading()
	if wants_aim == _aiming:
		return
	_aiming = wants_aim
	_move_to_pose(_aiming)
	aiming_changed.emit(_aiming)


## Tweens the primary weapon holder and camera FOV to the hip or the aiming pose.
## Aiming puts the model's "Sight" marker on the camera axis. The secondary
## weapon always rests at its hip pose.
func _move_to_pose(aiming: bool) -> void:
	var definition := primary.definition
	var target_position := primary.hip_position
	var target_yaw := primary.hip_yaw
	var target_fov := _hip_fov
	if aiming:
		var viewmodel := primary.viewmodel
		var sight := viewmodel.find_child("Sight", true, false) as Node3D
		var sight_in_holder := viewmodel.basis * viewmodel.to_local(sight.global_position) if sight else Vector3.ZERO
		target_position = Vector3(0.0, 0.0, -definition.ads_sight_distance) - sight_in_holder
		target_yaw = 0.0
		target_fov = definition.ads_fov

	if _pose_tween:
		_pose_tween.kill()
	_pose_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(primary.holder, "position", target_position, definition.ads_time)
	_pose_tween.tween_property(primary.holder, "rotation:y", target_yaw, definition.ads_time)
	_pose_tween.tween_property(_camera, "fov", target_fov, definition.ads_time)


func _update_spread() -> void:
	var widest := 0.0
	for slot in _slots:
		if slot.is_empty():
			continue
		if _aiming and slot == primary:
			slot.spread_deg = slot.definition.ads_spread_deg
		elif _player.horizontal_speed() > MOVING_SPEED_THRESHOLD:
			slot.spread_deg = slot.definition.hip_spread_moving_deg
		else:
			slot.spread_deg = slot.definition.hip_spread_standing_deg
		widest = maxf(widest, slot.spread_deg)
	if not is_equal_approx(widest, _crosshair_spread_deg):
		_crosshair_spread_deg = widest
		spread_changed.emit(widest)


func _fire(slot: WeaponSlot) -> void:
	var origin := _camera.global_position
	var direction := _apply_spread(-_camera.global_basis.z, _camera.global_basis, slot.spread_deg)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_RANGE, BULLET_MASK)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)

	var muzzle := origin + direction * MUZZLE_FALLBACK_DISTANCE
	var muzzle_marker := slot.muzzle_marker()
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

	_kick_recoil(slot)
	fired.emit(slot.definition)


## Random direction inside the shot cone (half-angle `spread_deg`).
func _apply_spread(forward: Vector3, basis: Basis, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return forward
	var spread := deg_to_rad(spread_deg)
	var spin := randf() * TAU
	# sqrt() samples the cone's circular cross-section uniformly instead of
	# bunching shots toward the centre.
	var cone := sqrt(randf()) * spread
	return (forward * cos(cone) + basis.x * sin(cone) * cos(spin) + basis.y * sin(cone) * sin(spin)).normalized()


## Kicks the model itself (not the holder), so recoil never fights the aim tween.
func _kick_recoil(slot: WeaponSlot) -> void:
	if slot.recoil_tween:
		slot.recoil_tween.kill()
	slot.viewmodel.position.z = RECOIL_KICK * (RECOIL_KICK_ADS_SCALE if _aiming else 1.0)
	slot.recoil_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	slot.recoil_tween.tween_property(slot.viewmodel, "position:z", 0.0, RECOIL_RECOVERY_TIME)


## Reloads every weapon that isn't full, left hand first, one after the other.
## Full weapons are skipped; if all are full nothing happens.
func _start_reload() -> void:
	if is_reloading():
		return
	for slot_index in [SECONDARY, PRIMARY]:
		if _needs_reload(_slots[slot_index]):
			_reload_queue.append(slot_index)
	_advance_reload_queue()


func _needs_reload(slot: WeaponSlot) -> bool:
	return not slot.is_empty() and slot.in_mag < slot.definition.magazine_size and slot.reserve > 0


## Starts the next queued reload, if none is running.
func _advance_reload_queue() -> void:
	if primary.is_reloading() or secondary.is_reloading():
		return
	while not _reload_queue.is_empty():
		var slot_index: int = _reload_queue.pop_front()
		var slot := _slots[slot_index]
		if not _needs_reload(slot):
			continue
		slot.reload_left = slot.definition.reload_duration
		reloading_changed.emit(slot_index, true)
		reload_started.emit(slot.definition)
		return


func _finish_reload(slot_index: int) -> void:
	var slot := _slots[slot_index]
	var transferred := mini(slot.definition.magazine_size - slot.in_mag, slot.reserve)
	slot.in_mag += transferred
	slot.reserve -= transferred
	ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
	reloading_changed.emit(slot_index, false)
	_advance_reload_queue()


func _rebuild_viewmodel(slot: WeaponSlot) -> void:
	if slot.recoil_tween:
		slot.recoil_tween.kill()
	if slot.viewmodel:
		slot.holder.remove_child(slot.viewmodel)
		slot.viewmodel.queue_free()
		slot.viewmodel = null
	if slot.definition:
		slot.viewmodel = slot.definition.model.instantiate()
		slot.holder.add_child(slot.viewmodel)


## `replace_primary` is the G key. Where an incoming weapon goes:
## - two-handed: alone in the primary slot, everything held is dropped;
## - one-handed, G: replaces the primary weapon;
## - one-handed, F: joins a one-handed primary as the secondary (replacing the
##   secondary if there already is one), or replaces a two-handed primary.
## A replaced weapon is always dropped with its ammo, even when it's the same type:
## ammo belongs to the weapon instance, not the weapon type.
func _try_pickup(replace_primary: bool) -> void:
	var best := _find_pickup()
	if best == null:
		return

	var incoming := best.definition
	var target := PRIMARY
	if not incoming.one_handed:
		_drop_slot(SECONDARY)
	elif not replace_primary and primary.definition.one_handed:
		target = SECONDARY
	_drop_slot(target)
	equip(target, incoming, best.ammo_in_mag, best.ammo_reserve)
	best.collect()
	picked_up.emit()


func _find_pickup() -> PickupArea:
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
	return best


## Throws the slot's weapon into the world and empties the slot (unless the
## caller refills it right away). Does nothing for an empty slot.
func _drop_slot(slot_index: int) -> void:
	var slot := _slots[slot_index]
	if slot.is_empty():
		return
	var dropped := dropped_weapon_scene.instantiate() as DroppedWeapon
	dropped.setup(slot.definition, slot.in_mag, slot.reserve)
	_player.get_parent().add_child(dropped)

	var forward := Vector3(-sin(_player.yaw), 0.0, -cos(_player.yaw))
	var right := Vector3(cos(_player.yaw), 0.0, -sin(_player.yaw))
	var side := THROW_SIDE_OFFSET * (1.0 if slot_index == PRIMARY else -1.0)
	dropped.global_position = _player.global_position + forward * THROW_FORWARD_OFFSET + right * side + Vector3.UP * THROW_ORIGIN_HEIGHT
	dropped.linear_velocity = forward * THROW_FORWARD_SPEED + Vector3.UP * THROW_UP_SPEED
	dropped.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * THROW_MAX_TUMBLE
	if slot_index == SECONDARY:
		_clear(SECONDARY)
