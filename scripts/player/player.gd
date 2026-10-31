class_name Player
extends CharacterBody3D
## First-person player: Quake-style accel/friction/slide on a CharacterBody3D.
##
## Yaw/pitch live as plain floats and drive a top-level Head node every render
## frame (positioned from the *interpolated* body transform), so mouse look is
## never tied to the physics tick.

signal jumped
signal stepped
signal health_changed(health: int, max_health: int)
signal damaged(amount: int, attacker: Node)
signal died(attacker: Node)
signal respawned

enum Stance { STANDING, CROUCHING, SLIDING }

const DEAD_EYE_HEIGHT := 0.4

# Networking (see the "Networking" section below).
const SNAPSHOT_SIZE := 11
## Remote players are drawn this far in the past so there is always a newer
## snapshot to blend towards.
const INTERPOLATION_DELAY_MS := 100
## The local player's prediction is corrected only when it differs from the server
## by more than this (metres); beyond SNAP_DISTANCE it is teleported instead.
const RECONCILE_EPSILON := 0.02
const RECONCILE_SNAP_DISTANCE := 2.0
## How fast the visible correction fades out (1/s).
const ERROR_SMOOTH_RATE := 12.0
const MAX_HISTORY := 120
const MAX_BUFFERED_SNAPSHOTS := 40

@export var settings: MovementSettings
@export var max_health := 100
@export var respawn_delay := 3.0

## Which peer controls this player (1 is the host/server and single player).
var peer_id := 1
## True on the machine whose human plays this body: it gets the camera, HUD and
## viewmodels. Everyone else sees a third-person stand-in.
var is_local := true

# State below is replicated by the StateSync node, so setters react on clients too.
var stance := Stance.STANDING:
	set(value):
		var crouch_changed := (value != Stance.STANDING) != (stance != Stance.STANDING)
		stance = value
		if crouch_changed and is_node_ready():
			_apply_body_height(value != Stance.STANDING)
var yaw := 0.0
var pitch := 0.0
var health := 100:
	set(value):
		health = value
		health_changed.emit(health, max_health)
## Match score, replicated for the scoreboard.
var kills := 0
var deaths := 0
var alive := true:
	set(value):
		if value == alive:
			return
		alive = value
		if is_node_ready():
			_on_alive_changed()

## Server state for everyone, published each tick by the server (see `_publish_snapshot`).
## Layout: [ack sequence, position xyz, velocity xyz, yaw, pitch, stance, slide time].
var snapshot := PackedFloat32Array():
	set(value):
		snapshot = value
		if not is_multiplayer_authority():
			_receive_snapshot(value)

var _frame := InputFrame.new()
var _snapshot_queue: Array = []  # predicting client: [ready ms, snapshot]
var _interpolation_buffer: Array = []  # remote player on a client: [ms, position, yaw, pitch]
var _history: Array = []  # predicting client: [sequence, InputFrame, position after the step]
var _synced := false
var _replaying := false
## Visible correction after a reconcile; fades to zero so the view never jumps.
var _error_offset := Vector3.ZERO
var _slide_elapsed := 0.0
var _distance_since_step := 0.0
var _eye_height := 0.0
var _eye_tween: Tween
var _capsule: CapsuleShape3D

@onready var input: PlayerInput = $PlayerInput
@onready var _visual: Node3D = $Visual
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_area: Area3D = $InteractArea
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _headroom_cast: ShapeCast3D = $HeadroomCast


func _ready() -> void:
	# Each player resizes its own capsule when crouching; the scene resource is shared.
	_capsule = (_collision_shape.shape as CapsuleShape3D).duplicate()
	_collision_shape.shape = _capsule
	input.mouse_sensitivity = settings.mouse_sensitivity
	_eye_height = settings.eye_height
	_apply_body_height(false)
	_visual.visible = not is_local and alive
	if is_local:
		camera.make_current()
	else:
		camera.clear_current()
	# Only the simulating side moves the body in physics ticks; elsewhere the
	# replicated position is applied as it arrives, so don't interpolate it.
	if not is_multiplayer_authority() and not is_local:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_update_camera()
	if is_multiplayer_authority():
		spawn()


## Places the player at a random `player_spawn` marker with full health. Used for
## the first spawn and for every respawn.
func spawn() -> void:
	var spawns := get_tree().get_nodes_in_group(&"player_spawn")
	if not spawns.is_empty():
		var marker := spawns.pick_random() as Node3D
		teleport(marker.global_position, marker.global_rotation.y)
	health = max_health
	alive = true
	stance = Stance.STANDING
	_apply_body_height(false)
	respawned.emit()


## Called by whatever hurt the player (hitscan today). Ignored while dead.
func take_damage(amount: int, attacker: Node = null) -> void:
	if not alive:
		return
	health = maxi(health - amount, 0)
	damaged.emit(amount, attacker)
	if health == 0:
		_die(attacker)


func _die(attacker: Node) -> void:
	alive = false
	deaths += 1
	var killer := attacker as Player
	if killer and killer != self:
		killer.kills += 1
	_slide_elapsed = 0.0
	died.emit(attacker)
	get_tree().create_timer(respawn_delay).timeout.connect(spawn)


## Dying lowers the camera and hides the stand-in body; coming back restores them.
## Runs on every peer, since `alive` is replicated.
func _on_alive_changed() -> void:
	_visual.visible = not is_local and alive
	if alive:
		_apply_body_height(stance != Stance.STANDING)
		return
	if _eye_tween:
		_eye_tween.kill()
	_eye_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_eye_tween.tween_property(self, "_eye_height", DEAD_EYE_HEIGHT, settings.eye_ease_time)


func teleport(to: Vector3, new_yaw: float) -> void:
	global_position = to
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0
	input.set_look(yaw, pitch)
	reset_physics_interpolation()
	_update_camera()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _process(delta: float) -> void:
	if is_local:
		# The view follows the live look angles, not the tick-sampled frame.
		yaw = input.look_yaw
		pitch = input.look_pitch
		_error_offset = _error_offset.lerp(Vector3.ZERO, 1.0 - exp(-ERROR_SMOOTH_RATE * delta))
	elif not is_multiplayer_authority():
		_interpolate_remote()
	if is_local or is_multiplayer_authority():
		_update_camera()
	if _visual.visible:
		_visual.global_rotation = Vector3(0.0, yaw, 0.0)
		_visual.scale.y = 1.0 if stance == Stance.STANDING else _crouch_visual_scale()


func _update_camera() -> void:
	var eye_position := get_global_transform_interpolated().origin + Vector3.UP * _eye_height + _error_offset
	head.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), eye_position)


func _crouch_visual_scale() -> float:
	return settings.crouch_height / settings.standing_height


func _physics_process(delta: float) -> void:
	# The server (or single player) simulates authoritatively. The human's own
	# client predicts the same simulation from its input and is corrected by the
	# server's snapshots; other peers just show interpolated snapshots.
	var authority := is_multiplayer_authority()
	var predicting := is_local and not authority
	if not authority and not predicting:
		return
	_frame = input.frame()
	if predicting:
		_reconcile(delta)
	elif not is_local:
		# A remote player's body and eyes follow its frame (the live look angles
		# are the local human's, and only exist on their machine).
		yaw = _frame.yaw
		pitch = _frame.pitch
		_update_camera()
	_simulate(delta)
	if predicting:
		_history.append([_frame.sequence, _frame, global_position])
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	if authority:
		_publish_snapshot()


## One tick of movement from `_frame`. Also used to replay inputs after a correction.
func _simulate(delta: float) -> void:
	var has_wish := _frame.move != Vector2.ZERO
	var wish_world := Basis(Vector3.UP, _frame.yaw) * Vector3(_frame.move.x, 0.0, _frame.move.y)
	var wish_dir := Vector2(wish_world.x, wish_world.z).normalized()
	var grounded := is_on_floor()

	if not alive:
		# Dead: no control, but still fall and settle.
		velocity.x = 0.0
		velocity.z = 0.0
		if not grounded:
			velocity += get_gravity() * delta
		move_and_slide()
		return

	_update_stance(has_wish, wish_dir, grounded, delta)

	var horizontal := Vector2(velocity.x, velocity.z)
	var result: Vector2
	if stance == Stance.SLIDING:
		# Momentum-locked: only friction acts, so a slide can't be steered back
		# up to full speed. Speed is held flat briefly before friction kicks in.
		var decaying := grounded and _slide_elapsed >= settings.slide_sustain_duration
		result = QuakeMovement.apply_friction(horizontal, settings.slide_friction, settings.stop_speed, delta) if decaying else horizontal
	else:
		result = _walk_velocity(horizontal, has_wish, wish_dir, grounded, delta)
	velocity.x = result.x
	velocity.z = result.y

	if not grounded:
		velocity += get_gravity() * delta

	if _frame.jump and grounded:
		velocity.y = settings.jump_speed
		if not _replaying:
			jumped.emit()
		if stance == Stance.SLIDING:
			stance = Stance.CROUCHING
		# Jumping out of a crouch stands you up unless something is overhead.
		if stance == Stance.CROUCHING and _can_stand():
			_set_stance(Stance.STANDING)

	move_and_slide()
	if not _replaying:
		_track_footsteps(has_wish, delta)


func _walk_velocity(horizontal: Vector2, has_wish: bool, wish_dir: Vector2, grounded: bool, delta: float) -> Vector2:
	# Grounded with no input stops instantly; friction still applies while
	# changing direction so turns stay snappy.
	var after_friction := horizontal
	if grounded:
		after_friction = QuakeMovement.apply_friction(horizontal, settings.ground_friction, settings.stop_speed, delta) if has_wish else Vector2.ZERO

	var max_speed := _max_speed(has_wish, grounded)
	var accel := settings.ground_accel if grounded else settings.air_accel
	var speed_before := after_friction.length()
	var result := QuakeMovement.accelerate(after_friction, wish_dir, max_speed if has_wish else 0.0, accel, delta)

	# accelerate() only caps the projection onto wish_dir, so a perpendicular
	# component (e.g. after a wall hit) can push total speed past the cap. Clamp
	# only what this call added, never momentum already carried in (sprint-jump,
	# slide exit).
	if has_wish:
		var clamp_speed := maxf(max_speed, speed_before)
		if result.length() > clamp_speed:
			result = result.normalized() * clamp_speed
	return result


func _max_speed(has_wish: bool, grounded: bool) -> float:
	if not grounded:
		return settings.max_air_speed
	if stance != Stance.STANDING:
		return settings.max_crouch_speed
	if has_wish and _frame.sprint:
		return settings.max_sprint_speed
	return settings.max_ground_speed


## Crouch is a held stance; a fresh press while sprinting, grounded and moving
## starts a slide instead. A slide ends when crouch is released (so slides can
## be chained with short sprints) or once it has bled off too much speed.
func _update_stance(has_wish: bool, wish_dir: Vector2, grounded: bool, delta: float) -> void:
	if _frame.crouch_pressed and stance == Stance.STANDING:
		_set_stance(Stance.CROUCHING)
		if grounded and has_wish and _frame.sprint:
			_start_slide(wish_dir)

	if stance == Stance.SLIDING:
		_slide_elapsed += delta
		if not grounded or horizontal_speed() <= settings.max_crouch_speed:
			stance = Stance.CROUCHING

	if stance != Stance.STANDING and not _frame.crouch and _can_stand():
		_set_stance(Stance.STANDING)


func _start_slide(wish_dir: Vector2) -> void:
	stance = Stance.SLIDING
	_slide_elapsed = 0.0
	var current := Vector2(velocity.x, velocity.z)
	var direction := current.normalized() if current.length() > 0.001 else wish_dir
	var entry := direction * maxf(current.length(), settings.slide_entry_speed)
	velocity.x = entry.x
	velocity.z = entry.y


func _set_stance(new_stance: Stance) -> void:
	stance = new_stance


func _apply_body_height(crouched: bool) -> void:
	var height := settings.crouch_height if crouched else settings.standing_height
	_capsule.height = height
	_collision_shape.position.y = height / 2.0

	if _eye_tween:
		_eye_tween.kill()
	_eye_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_eye_tween.tween_property(self, "_eye_height", settings.crouch_eye_height if crouched else settings.eye_height, settings.eye_ease_time)


func _can_stand() -> bool:
	_headroom_cast.force_shapecast_update()
	return not _headroom_cast.is_colliding()


func _track_footsteps(has_wish: bool, delta: float) -> void:
	if not (is_on_floor() and has_wish and stance != Stance.SLIDING):
		return
	_distance_since_step += horizontal_speed() * delta
	if _distance_since_step >= settings.footstep_distance:
		_distance_since_step = 0.0
		stepped.emit()


# --- Networking -------------------------------------------------------------

## Server: publishes the body's state for all peers (replicated by `StateSync`).
func _publish_snapshot() -> void:
	snapshot = PackedFloat32Array([
		_frame.sequence,
		global_position.x, global_position.y, global_position.z,
		velocity.x, velocity.y, velocity.z,
		yaw, pitch, stance, _slide_elapsed,
	])


## Client: a snapshot arrived (after the simulated lag, if any, for the predicting
## player; remote players are blended at render time).
func _receive_snapshot(data: PackedFloat32Array) -> void:
	if data.size() != SNAPSHOT_SIZE or NetSim.drops():
		return
	var ready_ms := Time.get_ticks_msec() + NetSim.lag_ms
	if is_local:
		_snapshot_queue.append([ready_ms, data])
		if _snapshot_queue.size() > MAX_BUFFERED_SNAPSHOTS:
			_snapshot_queue.pop_front()
		return
	stance = int(data[9]) as Stance
	_interpolation_buffer.append([ready_ms, Vector3(data[1], data[2], data[3]), data[7], data[8]])
	if _interpolation_buffer.size() > MAX_BUFFERED_SNAPSHOTS:
		_interpolation_buffer.pop_front()


## Remote player on a client: shows the body where it was `INTERPOLATION_DELAY_MS` ago.
func _interpolate_remote() -> void:
	if _interpolation_buffer.is_empty():
		return
	var render_ms := Time.get_ticks_msec() - INTERPOLATION_DELAY_MS
	while _interpolation_buffer.size() > 2 and _interpolation_buffer[1][0] <= render_ms:
		_interpolation_buffer.pop_front()
	var from: Array = _interpolation_buffer[0]
	var to: Array = _interpolation_buffer[1] if _interpolation_buffer.size() > 1 else from
	var span: float = to[0] - from[0]
	var t := clampf((render_ms - from[0]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	# A respawn teleports the body; blending across it would streak.
	if (from[1] as Vector3).distance_to(to[1]) > RECONCILE_SNAP_DISTANCE:
		t = 1.0 if t > 0.0 else 0.0
	global_position = (from[1] as Vector3).lerp(to[1], t)
	yaw = lerp_angle(from[2], to[2], t)
	pitch = lerpf(from[3], to[3], t)


## Predicting client: compares the newest server snapshot with what we predicted
## for the same input, and replays the inputs the server hasn't seen yet if they differ.
func _reconcile(delta: float) -> void:
	var latest := PackedFloat32Array()
	var now := Time.get_ticks_msec()
	while not _snapshot_queue.is_empty() and _snapshot_queue[0][0] <= now:
		latest = _snapshot_queue.pop_front()[1]
	if latest.is_empty():
		return

	var ack := int(latest[0])
	var server_position := Vector3(latest[1], latest[2], latest[3])
	var server_velocity := Vector3(latest[4], latest[5], latest[6])
	while not _history.is_empty() and _history[0][0] < ack:
		_history.pop_front()

	var distance := INF
	if _synced and not _history.is_empty() and _history[0][0] == ack:
		distance = server_position.distance_to(_history[0][2])
		_history.pop_front()
		if distance < RECONCILE_EPSILON:
			return
	elif _synced:
		return

	if distance > RECONCILE_SNAP_DISTANCE:
		# First snapshot, respawn or a large error: take the server's word.
		_synced = true
		global_position = server_position
		velocity = server_velocity
		stance = int(latest[9]) as Stance
		_slide_elapsed = latest[10]
		yaw = latest[7]
		pitch = latest[8]
		input.set_look(yaw, pitch)
		_history.clear()
		_error_offset = Vector3.ZERO
		reset_physics_interpolation()
		return

	var predicted_end := global_position
	global_position = server_position
	velocity = server_velocity
	stance = int(latest[9]) as Stance
	_slide_elapsed = latest[10]
	var current := _frame
	_replaying = true
	for entry in _history:
		_frame = entry[1]
		_simulate(delta)
		entry[2] = global_position
	_replaying = false
	_frame = current
	_error_offset += predicted_end - global_position
