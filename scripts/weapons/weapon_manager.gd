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
##
## Networking: the server runs all of this logic. The owning client holds a
## mirror: the server tells it what changed (weapons, ammo, reloads, aiming,
## spread, shots fired, hits) over the `_rpc_*` methods below, and the mirror
## re-emits the same signals, so HUD, viewmodel and sounds work unchanged. Every
## other peer only gets the `_rpc_shot` tracer/impact. Clients do not predict.

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
## The local player's nearest pickup in reach changed (null when none). With
## `choice` both hands are possible, so F and G do different things.
signal pickup_hint_changed(definition: WeaponDefinition, choice: bool)
## A sound made by *another* player's weapon, to be played at `position` (the
## owner hears their own through the signals above). Emitted on every peer.
signal heard(sound: StringName, position: Vector3, pitch: float)

const VIEWMODEL_VIEW := preload("res://scenes/player/viewmodel_view.tscn")

const PRIMARY := 0
const SECONDARY := 1

const MAX_RANGE := 100.0
## Horizontal speed (m/s) above which hip-fire uses the "moving" spread.
const MOVING_SPEED_THRESHOLD := 0.5
const MUZZLE_FALLBACK_DISTANCE := 0.3
## Physics layers a bullet hits: world (1), player (2, the body capsule is the
## hitbox) and target (3). The shooter's own body is excluded from the ray.
const BULLET_MASK := (1 << 0) | (1 << 1) | (1 << 2)
const PLAYER_LAYER := 1 << 1
## Owning client: a predicted shot the server hasn't confirmed by now was refused.
const PENDING_SHOT_TIMEOUT_MS := 1500
## Payloads of `_rpc_event`.
const EVENT_HIT := 0
const EVENT_PICKED_UP := 1
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

var primary: WeaponSlot
var secondary: WeaponSlot

var _slots: Array[WeaponSlot] = []
var _frame := InputFrame.new()
var _hint_definition: WeaponDefinition
var _hint_choice := false
## Slots waiting for the reload in progress to finish (left hand goes first).
var _reload_queue: Array[int] = []
var _crosshair_spread_deg := -1.0
## Slot of the shot being fired, so the `fired` forwarder knows which hand.
var _last_fired_slot := PRIMARY
## Server: set once the owning client has its player node and asked for the state;
## updates sent earlier would hit a node that doesn't exist there yet.
var _mirror_ready := false
var _aiming := false
var _pose_tween: Tween
var _hip_fov := 75.0
var _view_fov := 75.0  # the aim tween's FOV; the camera shows it plus the player's speed boost

@onready var _player: Player = get_parent()
@onready var _camera: Camera3D = $"../Head/Camera3D"
@onready var _effects: ShotEffects = $ShotEffects


func _ready() -> void:
	_hip_fov = _camera.fov
	_view_fov = _hip_fov
	if _player.is_local:
		# Weapons are drawn by a camera of their own (see `ViewmodelView`).
		var view := VIEWMODEL_VIEW.instantiate() as ViewmodelView
		add_child(view)  # (the player is still setting up its children)
		view.bind(_camera)
		primary = WeaponSlot.new(view.primary_holder)
		secondary = WeaponSlot.new(view.secondary_holder)
	else:
		primary = WeaponSlot.new(null)
		secondary = WeaponSlot.new(null)
	_slots = [primary, secondary]
	reloading_changed.connect(_on_reloading_changed)
	_show_holders(true)
	_player.died.connect(_on_player_died)
	_player.respawned.connect(_on_player_respawned)
	if is_multiplayer_authority():
		weapon_changed.connect(_publish_held_weapons)
		equip(PRIMARY, starting_weapon)
		_connect_owner_updates()
	elif _player.is_local:
		_rpc_request_state.rpc_id(1)


## The camera shows the aim tween's FOV plus the player's speed boost.
func _process(_delta: float) -> void:
	if not _player.is_local:
		return
	# The boost fades out as the sights come up.
	var hip_share := 1.0
	if primary and primary.definition:
		hip_share = clampf(inverse_lerp(primary.definition.ads_fov, _hip_fov, _view_fov), 0.0, 1.0)
	_camera.fov = _view_fov + _player.speed_fov_boost * hip_share


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
	slot.shots = 0
	_reload_queue.erase(slot_index)
	_rebuild_viewmodel(slot)
	_advance_reload_queue()
	_move_to_pose(_aiming)
	_update_spread()
	weapon_changed.emit(slot_index, new_definition)
	ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
	reloading_changed.emit(slot_index, false)


## Debug/console: puts a fresh weapon into a slot without dropping what was there.
## Returns an error message, or "" on success.
func give(slot_index: int, definition: WeaponDefinition) -> String:
	if slot_index == SECONDARY:
		if not definition.one_handed:
			return "%s is two-handed; it only fits the primary slot" % definition.display_name
		if primary.is_empty() or not primary.definition.one_handed:
			return "The primary weapon must be one-handed to hold a second one"
	elif not definition.one_handed:
		_clear(SECONDARY)
	equip(slot_index, definition)
	return ""


## Debug/console: refills every held weapon's magazine and reserve.
func refill() -> void:
	for slot_index in 2:
		var slot := _slots[slot_index]
		if slot.is_empty():
			continue
		equip(slot_index, slot.definition)


## Viewmodels exist only for the human playing this body.
func _show_holders(shown: bool) -> void:
	for slot in _slots:
		if slot.holder:
			slot.holder.visible = shown


## Dying drops everything held; respawning starts over with the starting weapon.
func _on_player_died(_attacker: Node) -> void:
	_show_holders(false)
	if not is_multiplayer_authority():
		return
	_drop_slot(SECONDARY)
	_drop_slot(PRIMARY)
	_player.held_primary = &""
	_reload_queue.clear()


func _on_player_respawned() -> void:
	_show_holders(true)
	if not is_multiplayer_authority():
		return
	_clear(SECONDARY)
	equip(PRIMARY, starting_weapon)


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
	# Only the simulating side (server / single player) runs weapon logic.
	if not _player.is_multiplayer_authority():
		if _player.is_local:
			_predict_feedback(delta)
			_update_pickup_hint()
		return
	_frame = _player.input.frame()
	if _player.is_local:
		_update_pickup_hint()
	_update_aiming()
	_update_spread()
	if not _player.alive:
		return

	if _frame.interact_pressed:
		_try_pickup(false)
	elif _frame.interact_alt_pressed:
		_try_pickup(true)
	if _frame.reload_pressed:
		_start_reload()

	_tick_slot(PRIMARY, _frame.fire, delta)
	_tick_slot(SECONDARY, _frame.fire_secondary, delta)


## Predicting client: shows aiming, recoil, the shot sound, the tracer and the
## ammo count at once instead of waiting a round trip for the server. Damage and
## hit confirmation still come from the server, and its aiming, "fired", spread
## and shot messages are ignored here (see `_rpc_aiming`, `_rpc_fired`,
## `_rpc_spread`, `_rpc_shot`). Predicted shots are subtracted from the magazine
## until the server's shot count (`_rpc_ammo`) covers them.
func _predict_feedback(delta: float) -> void:
	_frame = _player.input.frame()
	_update_aiming()
	_update_spread()
	if not _player.alive:
		return
	for slot_index in 2:
		var slot := _slots[slot_index]
		_expire_pending_shots(slot_index)
		if slot.is_empty() or slot.reload_left > 0.0:
			continue
		slot.cooldown -= delta
		var firing := _frame.fire if slot_index == PRIMARY else _frame.fire_secondary
		if firing and not is_reloading() and slot.cooldown <= COOLDOWN_EPSILON and slot.in_mag > 0:
			slot.cooldown = slot.definition.fire_cooldown
			slot.pending_shots.append(Time.get_ticks_msec())
			slot.in_mag -= 1
			ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
			var shots := _trace(slot, false)
			for index in shots.size():
				var shot: Dictionary = shots[index]
				_show_shot(slot.definition.id, shot["muzzle"], shot["end"], shot["normal"], index == 0)
			_kick_recoil(slot)
			fired.emit(slot.definition)


## A predicted shot the server never counted (it was refused, e.g. a reload had
## started) stops being subtracted after a while.
func _expire_pending_shots(slot_index: int) -> void:
	var slot := _slots[slot_index]
	var expired := 0
	while not slot.pending_shots.is_empty() and Time.get_ticks_msec() - slot.pending_shots[0] > PENDING_SHOT_TIMEOUT_MS:
		slot.pending_shots.pop_front()
		expired += 1
	if expired:
		slot.in_mag += expired
		ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)


func _tick_slot(slot_index: int, firing: bool, delta: float) -> void:
	var slot := _slots[slot_index]
	if slot.is_empty():
		return
	if slot.reload_left > 0.0:
		slot.reload_left -= delta
		if slot.reload_left <= 0.0:
			_finish_reload(slot_index)
		return

	slot.cooldown -= delta
	if firing and not is_reloading() and slot.cooldown <= COOLDOWN_EPSILON and slot.in_mag > 0:
		slot.cooldown = slot.definition.fire_cooldown
		slot.in_mag -= 1
		slot.shots += 1
		ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
		_fire(slot)


## Sights come up while the aim button is held. They drop for a reload and are
## unavailable while wielding two weapons (the aim button's role there is firing).
func _update_aiming() -> void:
	var wants_aim := _player.alive and _frame.aim and not is_akimbo() and not primary.is_reloading()
	if wants_aim == _aiming:
		return
	_aiming = wants_aim
	_player.aiming = wants_aim
	_move_to_pose(_aiming)
	aiming_changed.emit(_aiming)


## Tweens the primary weapon holder and camera FOV to the hip or the aiming pose.
## Aiming puts the model's "Sight" marker on the camera axis. The secondary
## weapon always rests at its hip pose.
func _move_to_pose(aiming: bool) -> void:
	if primary.holder == null:
		return  # nobody sees this body's viewmodel
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
	_pose_tween.tween_property(self, "_view_fov", target_fov, definition.ads_time)


func _update_spread() -> void:
	var widest := 0.0
	for slot in _slots:
		if slot.is_empty():
			continue
		slot.pellet_spread_deg = slot.definition.pellet_spread_deg
		if _aiming and slot == primary:
			slot.spread_deg = slot.definition.ads_spread_deg
			if slot.definition.ads_pellet_spread_deg >= 0.0:
				slot.pellet_spread_deg = slot.definition.ads_pellet_spread_deg
		elif _player.horizontal_speed() > MOVING_SPEED_THRESHOLD:
			slot.spread_deg = slot.definition.hip_spread_moving_deg
		else:
			slot.spread_deg = slot.definition.hip_spread_standing_deg
		widest = maxf(widest, slot.spread_deg + slot.pellet_spread_deg)
	if not is_equal_approx(widest, _crosshair_spread_deg):
		_crosshair_spread_deg = widest
		spread_changed.emit(widest)


func _fire(slot: WeaponSlot) -> void:
	var shots := _trace(slot, true)
	var id := slot.definition.id
	# A shot's pellets hitting the same target add up to one hit (one `take_damage`, one hit marker).
	var damage_dealt := {}
	for index in shots.size():
		var shot: Dictionary = shots[index]
		_show_shot(id, shot["muzzle"], shot["end"], shot["normal"], index == 0)
		_rpc_shot.rpc(id, shot["muzzle"], shot["end"], shot["normal"], index == 0)
		var hit: Dictionary = shot["hit"]
		if not hit.is_empty():
			var collider: Object = hit["collider"]
			if collider.has_method(&"take_damage"):
				damage_dealt[collider] = damage_dealt.get(collider, 0) + slot.definition.damage
	for collider: Object in damage_dealt:
		collider.take_damage(damage_dealt[collider], _player)
	if not damage_dealt.is_empty():
		hit_confirmed.emit()

	_last_fired_slot = _slots.find(slot)
	_kick_recoil(slot)
	fired.emit(slot.definition)


## Where a shot from `slot` goes: one entry per pellet with its muzzle, end point, surface
## normal (zero = no hit) and the raw ray hit. The spread rolls are seeded by the frame's
## sequence number and the hand, so the owning client's predicted shot takes exactly the
## paths the server's will (the aim roll first, then each pellet's). `compensated` is for
## the server (see `_cast_ray`).
func _trace(slot: WeaponSlot, compensated: bool) -> Array[Dictionary]:
	var origin := _camera.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_frame.sequence * 2 + _slots.find(slot))  # hashed: nearby seeds give similar first rolls
	var aim := _apply_spread(-_camera.global_basis.z, _camera.global_basis, slot.spread_deg, rng)
	var muzzle := origin + aim * MUZZLE_FALLBACK_DISTANCE
	var muzzle_marker := slot.muzzle_marker()
	if muzzle_marker:
		muzzle = muzzle_marker.global_position

	var definition := slot.definition
	var pellet_basis := Basis.looking_at(aim, _camera.global_basis.y)
	var shots: Array[Dictionary] = []
	for i in definition.pellets:
		var direction := _apply_spread(aim, pellet_basis, slot.pellet_spread_deg, rng)
		var hit := _cast_ray(origin, direction, compensated)
		if hit.is_empty():
			shots.append({"muzzle": muzzle, "end": origin + direction * MAX_RANGE, "normal": Vector3.ZERO, "hit": hit})
		else:
			shots.append({"muzzle": muzzle, "end": hit["position"], "normal": hit["normal"], "hit": hit})
	return shots


## The first thing a bullet hits, shaped like `intersect_ray`'s result. For a shooter
## on another machine (`view_tick` set) other players are tested at the pose the
## shooter saw them in, not where they are now (lag compensation); the world and
## targets are static or authoritative, so the physics query still handles them.
func _cast_ray(origin: Vector3, direction: Vector3, compensated: bool) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_RANGE, BULLET_MASK)
	query.exclude = [_player.get_rid()]
	if not compensated or _frame.view_tick <= 0.0:
		return _player.get_world_3d().direct_space_state.intersect_ray(query)

	query.collision_mask = BULLET_MASK & ~PLAYER_LAYER
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var nearest := origin.distance_to(hit["position"]) if not hit.is_empty() else MAX_RANGE
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == _player or not other.alive:
			continue
		var pose := other.pose_at(_frame.view_tick)
		var strike := CapsuleRay.intersect(origin, direction, pose[Player.Pose.POSITION], pose[Player.Pose.HEIGHT], other.body_radius())
		if not strike.is_empty() and strike["distance"] < nearest:
			nearest = strike["distance"]
			hit = {"position": origin + direction * nearest, "normal": strike["normal"], "collider": other}
	return hit


## Random direction inside the shot cone (half-angle `spread_deg`).
func _apply_spread(forward: Vector3, basis: Basis, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return forward
	var spread := deg_to_rad(spread_deg)
	var spin := rng.randf() * TAU
	# sqrt() samples the cone's circular cross-section uniformly instead of
	# bunching shots toward the centre.
	var cone := sqrt(rng.randf()) * spread
	return (forward * cos(cone) + basis.x * sin(cone) * cos(spin) + basis.y * sin(cone) * sin(spin)).normalized()


## Plays an animation of the slot's viewmodel scene, if it has one.
func _play_viewmodel(slot: WeaponSlot, animation: StringName, duration := 0.0) -> void:
	var scene := slot.viewmodel as WeaponViewmodel
	if scene:
		scene.play(animation, duration)


## With two weapons each hand has its own gun (the left one mirrored); a lone
## weapon is held with both hands.
func _update_hands() -> void:
	for slot in _slots:
		var scene := slot.viewmodel as WeaponViewmodel
		if scene:
			scene.set_akimbo(is_akimbo(), slot == secondary)


func _on_reloading_changed(slot_index: int, reloading: bool) -> void:
	var slot := _slots[slot_index]
	if reloading and slot.definition:
		_play_viewmodel(slot, &"reload", slot.definition.reload_duration)


## Kicks the weapon: the viewmodel scene's own "fire" animation if it has one, else
## the bare model by a tween (not the holder, so recoil never fights the aim tween).
func _kick_recoil(slot: WeaponSlot) -> void:
	if slot.viewmodel == null:
		return
	var scene := slot.viewmodel as WeaponViewmodel
	var ads_animation: StringName = &"fire_ads" if _aiming and slot == primary else &"fire"
	if scene and scene.has_animation(ads_animation):
		# The kick must be over by the next shot, or a fast weapon restarts it halfway through every time.
		scene.play(ads_animation, minf(scene.animation_length(ads_animation), slot.definition.fire_cooldown))
		return
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
		_announce(&"reload")
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
	if slot.definition and slot.holder:
		var scene := slot.definition.viewmodel if slot.definition.viewmodel else slot.definition.model
		slot.viewmodel = scene.instantiate()
		ViewmodelView.assign_layer(slot.viewmodel)
		slot.holder.add_child(slot.viewmodel)
		_play_viewmodel(slot, &"draw")
	_update_hands()


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
	_announce(&"pickup")


## Tells the HUD what F/G would take right now. Uses the same reach test as the
## pickup itself, on this machine's view of the world (the server decides).
func _update_pickup_hint() -> void:
	var best := _find_pickup() if _player.alive else null
	var definition := best.definition if best else null
	var choice := best != null and best.definition.one_handed and not primary.is_empty() and primary.definition.one_handed
	if definition == _hint_definition and choice == _hint_choice:
		return
	_hint_definition = definition
	_hint_choice = choice
	pickup_hint_changed.emit(definition, choice)


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
	var forward := Vector3(-sin(_player.yaw), 0.0, -cos(_player.yaw))
	var right := Vector3(cos(_player.yaw), 0.0, -sin(_player.yaw))
	var side := THROW_SIDE_OFFSET * (1.0 if slot_index == PRIMARY else -1.0)
	var data := {
		"id": slot.definition.id,
		"mag": slot.in_mag,
		"reserve": slot.reserve,
		"position": _player.global_position + forward * THROW_FORWARD_OFFSET + right * side + Vector3.UP * THROW_ORIGIN_HEIGHT,
		"velocity": forward * THROW_FORWARD_SPEED + Vector3.UP * THROW_UP_SPEED,
		"spin": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * THROW_MAX_TUMBLE,
	}
	var spawner := get_tree().get_first_node_in_group(&"drop_spawner") as MultiplayerSpawner
	spawner.spawn(data)
	if slot_index == SECONDARY:
		_clear(SECONDARY)


## Builds a thrown weapon from `_drop_slot`'s data. Used as the drop spawner's
## spawn function, so it runs on every peer.
static func spawn_dropped(data: Dictionary, scene: PackedScene) -> DroppedWeapon:
	var dropped := scene.instantiate() as DroppedWeapon
	dropped.setup(WeaponCatalog.get_default().find(data["id"]), data["mag"], data["reserve"])
	dropped.position = data["position"]
	dropped.linear_velocity = data["velocity"]
	dropped.angular_velocity = data["spin"]
	return dropped


## Server: tells every peer which weapons this player holds (for the third-person model).
func _publish_held_weapons(_slot: int, _definition: WeaponDefinition) -> void:
	_player.held_primary = primary.definition.id if primary.definition else &""
	_player.held_secondary = secondary.definition.id if secondary.definition else &""


# --- Networking -------------------------------------------------------------

## The owning client's peer id, or 0 if the owner is this process (single player,
## host) or not connected.
func _remote_owner() -> int:
	var peer := _player.peer_id
	return peer if _mirror_ready and peer != multiplayer.get_unique_id() and multiplayer.get_peers().has(peer) else 0


## Server: forwards every state change to the owning client's mirror.
func _connect_owner_updates() -> void:
	weapon_changed.connect(func(slot: int, definition: WeaponDefinition) -> void:
		var peer := _remote_owner()
		if peer:
			var held := _slots[slot]
			_rpc_weapon.rpc_id(peer, slot, definition.id if definition else &"", held.in_mag, held.reserve, held.shots))
	ammo_changed.connect(func(slot: int, in_mag: int, reserve: int) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_ammo.rpc_id(peer, slot, in_mag, reserve, _slots[slot].shots))
	reloading_changed.connect(func(slot: int, reloading: bool) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_reloading.rpc_id(peer, slot, reloading))
	aiming_changed.connect(func(aiming: bool) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_aiming.rpc_id(peer, aiming))
	spread_changed.connect(func(degrees: float) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_spread.rpc_id(peer, degrees))
	fired.connect(func(definition: WeaponDefinition) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_fired.rpc_id(peer, definition.id, _last_fired_slot))
	reload_started.connect(func(definition: WeaponDefinition) -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_reload_started.rpc_id(peer, definition.id))
	hit_confirmed.connect(func() -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_event.rpc_id(peer, EVENT_HIT))
	picked_up.connect(func() -> void:
		var peer := _remote_owner()
		if peer:
			_rpc_event.rpc_id(peer, EVENT_PICKED_UP))


## `with_sound`: only the first pellet of a shot makes the (positional) shot sound.
func _show_shot(id: StringName, from: Vector3, to: Vector3, normal: Vector3, with_sound: bool) -> void:
	_effects.spawn_tracer(from, to)
	if normal != Vector3.ZERO:
		_effects.spawn_impact(to, normal)
	if with_sound and not _player.is_local:
		var definition := WeaponCatalog.get_default().find(id)
		heard.emit(&"fire", from, definition.fire_pitch_scale if definition else 1.0)


## Everyone but the server: a bullet's tracer and impact (zero normal = no hit),
## and the shot's sound for players other than the shooter (a shotgun sends one per pellet).
@rpc("authority", "call_remote", "unreliable")
func _rpc_shot(id: StringName, from: Vector3, to: Vector3, normal: Vector3, with_sound: bool) -> void:
	if _player.is_local:
		return  # the owner already saw its own predicted tracer
	_show_shot(id, from, to, normal, with_sound)


## Server: other players hear this too (reloads, pickups).
func _announce(sound: StringName) -> void:
	var position := _camera.global_position
	if not _player.is_local:
		heard.emit(sound, position, 1.0)
	_rpc_heard.rpc(sound, position)


@rpc("authority", "call_remote", "unreliable")
func _rpc_heard(sound: StringName, position: Vector3) -> void:
	if not _player.is_local:
		heard.emit(sound, position, 1.0)


## A freshly spawned local player asks the server for its whole weapon state,
## because the server's earlier updates were sent before this node existed.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if multiplayer.get_remote_sender_id() != _player.peer_id:
		return
	_mirror_ready = true
	var peer := _player.peer_id
	for slot_index in 2:
		var slot := _slots[slot_index]
		_rpc_weapon.rpc_id(peer, slot_index, slot.definition.id if slot.definition else &"", slot.in_mag, slot.reserve, slot.shots)
		_rpc_reloading.rpc_id(peer, slot_index, slot.is_reloading())
	_rpc_aiming.rpc_id(peer, _aiming)
	_rpc_spread.rpc_id(peer, _crosshair_spread_deg)


@rpc("authority", "call_remote", "reliable")
func _rpc_weapon(slot_index: int, id: StringName, in_mag: int, reserve: int, shots: int) -> void:
	var slot := _slots[slot_index]
	slot.definition = WeaponCatalog.get_default().find(id) if id != &"" else null
	slot.shots = shots
	slot.pending_shots.clear()
	slot.in_mag = in_mag
	slot.reserve = reserve
	slot.reload_left = 0.0
	_rebuild_viewmodel(slot)
	_move_to_pose(_aiming)
	weapon_changed.emit(slot_index, slot.definition)
	ammo_changed.emit(slot_index, in_mag, reserve)
	reloading_changed.emit(slot_index, false)


@rpc("authority", "call_remote", "reliable")
func _rpc_ammo(slot_index: int, in_mag: int, reserve: int, shots: int) -> void:
	var slot := _slots[slot_index]
	# Shots the server has now counted are no longer "pending".
	for i in mini(maxi(shots - slot.shots, 0), slot.pending_shots.size()):
		slot.pending_shots.pop_front()
	slot.shots = shots
	slot.in_mag = in_mag - slot.pending_shots.size()
	slot.reserve = reserve
	ammo_changed.emit(slot_index, slot.in_mag, reserve)


@rpc("authority", "call_remote", "reliable")
func _rpc_reloading(slot_index: int, reloading: bool) -> void:
	var slot := _slots[slot_index]
	slot.reload_left = slot.definition.reload_duration if reloading and slot.definition else 0.0
	if reloading:
		slot.in_mag += slot.pending_shots.size()  # shots fired after this are refused
		slot.pending_shots.clear()
		ammo_changed.emit(slot_index, slot.in_mag, slot.reserve)
	reloading_changed.emit(slot_index, reloading)


@rpc("authority", "call_remote", "reliable")
func _rpc_reload_started(id: StringName) -> void:
	reload_started.emit(WeaponCatalog.get_default().find(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_aiming(aiming: bool) -> void:
	# The human's own client decides this from its input (`_predict_feedback`); a
	# late echo of an earlier state would make the sights flicker.
	if _player.is_local or aiming == _aiming:
		return
	_aiming = aiming
	_move_to_pose(aiming)
	aiming_changed.emit(aiming)


@rpc("authority", "call_remote", "reliable")
func _rpc_spread(degrees: float) -> void:
	if _player.is_local:
		return  # worked out locally (`_predict_feedback`)
	_crosshair_spread_deg = degrees
	spread_changed.emit(degrees)


@rpc("authority", "call_remote", "unreliable")
func _rpc_fired(id: StringName, slot_index: int) -> void:
	if _player.is_local:
		return  # already shown when the trigger was pulled (`_predict_feedback`)
	var slot := _slots[slot_index]
	if slot.viewmodel:
		_kick_recoil(slot)
	fired.emit(WeaponCatalog.get_default().find(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_event(event: int) -> void:
	match event:
		EVENT_HIT:
			hit_confirmed.emit()
		EVENT_PICKED_UP:
			picked_up.emit()
