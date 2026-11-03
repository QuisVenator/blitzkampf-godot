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
## Ledge climb: carried up the wall, then over the lip (see `_simulate_mantle`).
enum Mantle { NONE, RISING, FORWARD }

const DEAD_EYE_HEIGHT := 0.4
## Physics layer the ledge probes look for: the world.
const LEDGE_MASK := 1
## Bots get ids above this so they never collide with a real peer id.
const BOT_ID_BASE := 1_000_000

# Networking (see the "Networking" section below).
## Layout of `snapshot` (one float each; `SIZE` is the length). Index it with these,
## never with bare numbers.
enum Snap {
	ACK,  # sequence of the last input frame this state includes
	POS_X, POS_Y, POS_Z,
	VEL_X, VEL_Y, VEL_Z,
	YAW, PITCH, STANCE, SLIDE, ON_FLOOR,
	MANTLE, TARGET_X, TARGET_Y, TARGET_Z, MANTLE_SPEED,  # ledge climb: phase, where it ends, approach speed
	WALL_RUN, WALL_NX, WALL_NZ, WALL_TIME, WALL_COOLDOWN,  # wall run: running, wall normal (x, z), time on it, cooldown
	TICK,  # the server's physics tick
	SIZE,
}
## Layouts of the small arrays the networking code keeps (see the vars below).
enum Queued { READY_MS, DATA }
enum Blend { READY_MS, POSITION, YAW, PITCH, VELOCITY }
enum Step { SEQUENCE, FRAME, POSITION }
enum Pose { TICK, POSITION, HEIGHT }
## Remote players are drawn this far in the past so there is always a newer
## snapshot to blend towards.
const INTERPOLATION_DELAY_MS := 100
## The local player's prediction is corrected only when it differs from the server
## by more than this (metres); beyond SNAP_DISTANCE it is teleported instead.
## How fast the clock estimate drifts towards later-arriving snapshots (per snapshot).
const CLOCK_DRIFT := 0.02
const RECONCILE_EPSILON := 0.02
const RECONCILE_SNAP_DISTANCE := 2.0
## How fast the visible correction fades out (1/s).
const ERROR_SMOOTH_RATE := 12.0
const MAX_HISTORY := 120
const MAX_BUFFERED_SNAPSHOTS := 40
## Lag compensation: the server remembers this many ticks of every body's pose, and a
## shot is never rewound further than MAX_REWIND_TICKS (a cheater can't claim to have
## seen the past arbitrarily far back).
const POSE_HISTORY_TICKS := 60
const MAX_REWIND_TICKS := 30
const TICKS_PER_MS := 0.06  # physics ticks are 60 Hz

@export var settings: MovementSettings
@export var max_health := 100
@export var respawn_delay := 3.0

## Which peer controls this player (1 is the host/server and single player).
var peer_id := 1
## Server-driven AI player (no peer behind it); `peer_id` is just a unique id then.
var is_bot := false
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

## Server state for everyone, published each tick by the server (see `_publish_snapshot`;
## sent by RPC, not through `StateSync`, so it goes out exactly once per physics tick).
## Layout: see `Snap`.
var snapshot := PackedFloat32Array():
	set(value):
		snapshot = value
		if not is_multiplayer_authority():
			_receive_snapshot(value)

## Ids of the weapons in each hand (right, left), replicated so every peer can
## show them in the character's hands. Set by `WeaponManager` on the server.
var held_primary := &"":
	set(value):
		held_primary = value
		_show_held_weapons()
var held_secondary := &"":
	set(value):
		held_secondary = value
		_show_held_weapons()

var _frame := InputFrame.new()
## Remote players: last replicated "on the floor" flag (their body isn't simulated here).
var _remote_on_floor := true
## Server: peers that have asked for this player's snapshots (see `_rpc_want_snapshots`).
var _snapshot_peers: Array[int] = []
var _snapshot_queue: Array = []  # predicting client: [ready ms, snapshot] (`Queued`)
var _interpolation_buffer: Array = []  # remote player on a client, `Blend` layout
var _history: Array = []  # predicting client, `Step` layout: sequence, InputFrame, position after the step
var _synced := false
## Server: `Pose` entries (tick, position, capsule height) of this body after each of its recent ticks.
var _pose_history: Array = []
## Predicting client: the newest snapshot's server tick and when it was due to arrive.
## Newest snapshot tick seen, and the estimated `arrival - tick time` clock offset.
var _newest_tick := -1.0
var _clock_offset := 0.0
var _clock_synced := false
var _server_tick := 0.0
var _server_tick_ms := 0
var _replaying := false
## Visible correction after a reconcile; fades to zero so the view never jumps.
var _error_offset := Vector3.ZERO
var _step_offset := 0.0  # camera height offset hiding step lifts, a critically damped spring
var _step_velocity := 0.0
var _step_pending := 0.0  # offset from lifts in the latest physics tick, ramped in as the body interpolates
var _step_pending_tick := -1
var _slide_elapsed := 0.0
var _grounded := false  # on the floor, or just above one (stairs): see `_floor_height_below`
var _mantle := Mantle.NONE
var _mantle_target := Vector3.ZERO
var _mantle_speed := 0.0  # horizontal speed on approach
var _wall_run := false
var _wall_normal := Vector2.ZERO  # horizontal, pointing from the wall toward the body
var _wall_time := 0.0
var _wall_cooldown := 0.0
## Extra camera FOV (degrees) from speed (see `MovementSettings.speed_fov_boost`); the weapon manager adds it to the camera's FOV.
var speed_fov_boost := 0.0
var _view_roll := 0.0  # camera roll (radians) while wall running, local view only
var _distance_since_step := 0.0
var _eye_height := 0.0
var _eye_tween: Tween
var _capsule: CapsuleShape3D

@onready var input: PlayerInput = $PlayerInput
@onready var _visual: CharacterModel = $Visual
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
	floor_snap_length = settings.step_height
	_visual.visible = not is_local
	_show_held_weapons()
	if is_local:
		camera.make_current()
	else:
		camera.clear_current()
	# Only the simulating side moves the body in physics ticks; elsewhere the
	# replicated position is applied as it arrives, so don't interpolate it.
	if not is_multiplayer_authority():
		_rpc_want_snapshots.rpc_id(1)
	if not is_multiplayer_authority() and not is_local:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_update_camera()
	add_to_group(&"players")
	if is_multiplayer_authority():
		spawn()


func display_name() -> String:
	return "Bot %d" % (peer_id - BOT_ID_BASE) if is_bot else "Player %d" % peer_id


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
	if alive:
		_apply_body_height(stance != Stance.STANDING)
		return
	if _eye_tween:
		_eye_tween.kill()
	_eye_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_eye_tween.tween_property(self, "_eye_height", DEAD_EYE_HEIGHT, settings.eye_ease_time)


func teleport(to: Vector3, new_yaw: float) -> void:
	global_position = to
	# Nobody saw this body at its old place as being here: shots mustn't rewind across a teleport.
	_pose_history.clear()
	velocity = Vector3.ZERO
	_mantle = Mantle.NONE
	_wall_run = false
	_wall_cooldown = 0.0
	_step_offset = 0.0
	_step_velocity = 0.0
	_step_pending = 0.0
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
		_settle_step_offset(delta)
		_settle_view_roll(delta)
		_settle_speed_fov(delta)
	elif not is_multiplayer_authority():
		_interpolate_remote()
	if is_local or is_multiplayer_authority():
		_update_camera()
	if _visual.visible:
		_visual.global_rotation = Vector3(0.0, yaw, 0.0)
		var grounded := _grounded if is_multiplayer_authority() else _remote_on_floor
		_visual.update(horizontal_speed(), stance != Stance.STANDING, grounded, alive, pitch)


func _update_camera() -> void:
	var eye_position := get_global_transform_interpolated().origin + Vector3.UP * (_eye_height + _step_offset + _step_pending * Engine.get_physics_interpolation_fraction()) + _error_offset
	head.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, _view_roll), EULER_ORDER_YXZ), eye_position)


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
	if not _frame.idle:
		_simulate(delta)
	if authority and not predicting:
		var extra := input.extra_frame()
		if extra:
			_frame = extra
			if not is_local:
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
	# Walking off an edge or down stairs stays grounded (see `_floor_height_below`); a body that
	# was in the air does not become grounded just by being near the floor (no higher re-jumps).
	var grounded := is_on_floor() or (_grounded and _floor_just_below())
	_grounded = grounded

	_wall_cooldown = maxf(_wall_cooldown - delta, 0.0)
	if not alive:
		_wall_run = false
		# Dead: no control, but still fall and settle.
		velocity.x = 0.0
		velocity.z = 0.0
		if not grounded:
			velocity += get_gravity() * delta
		move_and_slide()
		return

	if _mantle != Mantle.NONE:
		_simulate_mantle(delta)
		return
	if _wall_run:
		_simulate_wall_run(delta, has_wish, wish_dir)
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
			_broadcast_sound(&"jump")
		if stance == Stance.SLIDING:
			stance = Stance.CROUCHING
		# Jumping out of a crouch stands you up unless something is overhead.
		if stance == Stance.CROUCHING and _can_stand():
			_set_stance(Stance.STANDING)

	if not grounded and has_wish and stance != Stance.SLIDING:
		var target := _find_ledge(wish_dir)
		if target.is_finite():
			_mantle = Mantle.RISING
			_mantle_target = target
			_mantle_speed = horizontal_speed()
			_simulate_mantle(delta)
			return

	if not grounded and has_wish and stance != Stance.SLIDING and _wall_cooldown <= 0.0:
		var wall := _find_wall()
		if wall != Vector3.ZERO:
			_wall_run = true
			_wall_normal = Vector2(wall.x, wall.z)
			_wall_time = 0.0
			velocity.y = settings.wallrun_entry_vertical_speed
			_simulate_wall_run(delta, has_wish, wish_dir)
			return

	var height_before := global_position.y
	var stepped := false
	if grounded:
		stepped = _step_up(delta)
	move_and_slide()
	if grounded and not is_on_floor():
		stepped = _step_down() or stepped
	if stepped:
		# What the body visibly jumped this tick, however it got there (the lift, then settling onto the step).
		_hide_step(global_position.y - height_before)
	if not _replaying:
		_track_footsteps(has_wish, delta)


## A wall beside a fast, airborne body that it could run on: returns its horizontal normal (pointing
## at the body), or `Vector3.ZERO`. Needs speed (`wallrun_min_speed`), height above the floor, and a
## near-vertical wall within `wallrun_reach` at knee and chest height on the left or right, roughly
## along the direction of travel (a head-on wall is not a run, it is a wall or a ledge).
func _find_wall() -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < settings.wallrun_min_speed:
		return Vector3.ZERO
	var forward := flat.normalized()
	var space := get_world_3d().direct_space_state
	var below := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * settings.wallrun_min_height, LEDGE_MASK)
	if not space.intersect_ray(below).is_empty():
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_distance := INF
	for side in [-1.0, 1.0]:
		var sideways: Vector3 = forward.cross(Vector3.UP) * side
		var normal := _wall_normal_toward(space, sideways)
		if normal == Vector3.ZERO or absf(normal.dot(forward)) > 0.6:
			continue
		var distance := _wall_distance(space, sideways)
		if distance < best_distance:
			best_distance = distance
			best = normal
	return best


## Normal of the wall in direction `toward` (horizontal, unit) if both the knee and the chest ray hit a
## near-vertical surface within reach, else `Vector3.ZERO`.
func _wall_normal_toward(space: PhysicsDirectSpaceState3D, toward: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for height: float in [0.5, 1.3]:
		var from := global_position + Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(from, from + toward * (_capsule.radius + settings.wallrun_reach), LEDGE_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or absf(hit.normal.y) > 0.25:
			return Vector3.ZERO
		total += hit.normal
	var flat := Vector3(total.x, 0.0, total.z)
	return flat.normalized() if flat.length() > 0.001 else Vector3.ZERO


func _wall_distance(space: PhysicsDirectSpaceState3D, toward: Vector3) -> float:
	var from := global_position + Vector3.UP * 0.9
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + toward * (_capsule.radius + settings.wallrun_reach), LEDGE_MASK))
	return from.distance_to(hit.position) if not hit.is_empty() else INF


## One tick of a wall run: gravity mostly off (growing over the run), speed along the wall
## accelerating to `wallrun_speed`, a little pressure into the wall. Ends when the wall ends, the
## run is too slow or too long, forward input stops, crouch is pressed, the body lands, or in a
## wall jump (jump pressed): off the wall with `wallrun_jump_push`, up with `wallrun_jump_up`,
## keeping the speed along the wall.
func _simulate_wall_run(delta: float, has_wish: bool, wish_dir: Vector2) -> void:
	var normal := Vector3(_wall_normal.x, 0.0, _wall_normal.y)
	_wall_time += delta
	var along := Vector3(velocity.x, 0.0, velocity.z)
	along -= normal * along.dot(normal)
	var speed := along.length()
	var heading := Vector2(along.x, along.z).normalized()

	if _frame.jump_pressed:
		var push := along.normalized() * speed + normal * settings.wallrun_jump_push
		velocity = Vector3(push.x, settings.wallrun_jump_up, push.z)
		if not _replaying:
			jumped.emit()
			_broadcast_sound(&"jump")
		_end_wall_run()
		move_and_slide()
		return
	var wall := _wall_normal_toward(get_world_3d().direct_space_state, -normal)
	if _frame.crouch_pressed or not has_wish or heading.dot(wish_dir) <= 0.0 \
			or wall == Vector3.ZERO or speed < settings.wallrun_stay_speed or _wall_time > settings.wallrun_max_duration:
		_end_wall_run()
		velocity.y += get_gravity().y * delta
		move_and_slide()
		return

	_wall_normal = Vector2(wall.x, wall.z)
	normal = wall
	var direction := along.normalized()
	speed = move_toward(speed, settings.wallrun_speed, settings.wallrun_accel * delta)
	velocity.x = direction.x * speed - normal.x * settings.wallrun_stick
	velocity.z = direction.z * speed - normal.z * settings.wallrun_stick
	var gravity_scale := lerpf(settings.wallrun_gravity_start, settings.wallrun_gravity_end, clampf(_wall_time / settings.wallrun_max_duration, 0.0, 1.0))
	velocity.y += get_gravity().y * gravity_scale * delta
	move_and_slide()
	if is_on_floor():
		_end_wall_run()


func _end_wall_run() -> void:
	_wall_run = false
	_wall_cooldown = settings.wallrun_cooldown


## Walking into a step (stairs, a curb) lifts the body onto it instead of stopping it, as
## `move_and_slide` has no step logic of its own. Only when something is in the way, the
## step is at most `step_height` high, there is room above and the floor on top is walkable;
## the move then continues from the raised position. The camera is eased through the lift
## (`_error_offset`), so stairs feel like a glide, not a staircase of pops.
func _step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.is_zero_approx():
		return false
	var from := global_transform
	if not test_move(from, motion):
		return false
	var up := Vector3.UP * settings.step_height
	if test_move(from, up):
		return false
	var raised := from.translated(up)
	# Look a little further ahead than this tick's move, so the probe reaches the tread.
	var reach := motion.normalized() * maxf(motion.length(), 0.15)
	if test_move(raised, reach):
		return false
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(reach), -up, landing) or landing.get_normal().y < cos(floor_max_angle):
		return false
	var lift := landing.get_position().y - global_position.y
	if lift < settings.step_min_height or lift > settings.step_height:
		return false
	global_position.y += lift + 0.001
	return true


## The body just moved up (`rise` > 0) or down by a step: the camera stays where it was and
## then glides to the new height (`_settle_step_offset`). The body is drawn interpolating from
## its previous tick's position, so the offset ramps in with the same fraction (`_step_pending`)
## and only joins the spring once that tick is over; applied at once, the camera would dip first.
func _hide_step(rise: float) -> void:
	if not is_local or _replaying:
		return
	var tick := Engine.get_physics_frames()
	if _step_pending_tick != tick:
		_commit_step_pending()
	_step_pending_tick = tick
	_step_pending -= rise


func _commit_step_pending() -> void:
	_step_offset += _step_pending
	_step_pending = 0.0


## Widens the field of view while moving faster than `speed_fov_threshold`, quickly on the way up and slowly back.
func _settle_speed_fov(delta: float) -> void:
	var amount := clampf(inverse_lerp(settings.speed_fov_threshold, settings.speed_fov_full_speed, horizontal_speed()), 0.0, 1.0)
	var target := settings.speed_fov_boost * amount if alive else 0.0
	var rate := settings.speed_fov_attack if target > speed_fov_boost else settings.speed_fov_release
	speed_fov_boost = lerpf(speed_fov_boost, target, 1.0 - exp(-rate * delta))


## Leans the view away from the wall during a wall run and back afterwards.
func _settle_view_roll(delta: float) -> void:
	var target := 0.0
	if _wall_run:
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		# Wall on the right: its normal points left (negative along `right`), and the view leans left (positive roll).
		target = -signf(Vector3(_wall_normal.x, 0.0, _wall_normal.y).dot(right)) * deg_to_rad(settings.wallrun_camera_roll)
	_view_roll = lerpf(_view_roll, target, 1.0 - exp(-10.0 * delta))


## Critically damped spring on `_step_offset` toward 0 (exact solution, so frame rate doesn't matter).
func _settle_step_offset(delta: float) -> void:
	if _step_pending != 0.0 and Engine.get_physics_frames() > _step_pending_tick:
		_commit_step_pending()
	if _step_offset == 0.0 and _step_velocity == 0.0:
		return
	var omega := settings.step_view_smoothing
	var decay := exp(-omega * delta)
	var push := _step_velocity + omega * _step_offset
	_step_offset = (_step_offset + push * delta) * decay
	_step_velocity = (_step_velocity - omega * push * delta) * decay
	if absf(_step_offset) < 0.0005 and absf(_step_velocity) < 0.005:
		_step_offset = 0.0
		_step_velocity = 0.0


## Height of the walkable floor less than `step_height` straight below a body that is not
## rising, else NAN. The engine's own idea of "on the
## floor" fails on stairs: the capsule rests on a step's edge at a steep angle, which doesn't
## count, so without this walking down stairs would be a chain of small falls.
func _floor_height_below() -> float:
	if velocity.y > 0.0:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * settings.step_height, LEDGE_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < cos(floor_max_angle):
		return NAN
	return hit.position.y


func _floor_just_below() -> bool:
	return not is_nan(_floor_height_below())


## After a move that left the engine floor but kept the body "grounded" (see above): settle
## onto the floor below, so the body follows the stairs down instead of hovering.
func _step_down() -> bool:
	var height := _floor_height_below()
	if is_nan(height):
		return false
	var drop := global_position.y - height
	if drop < 0.001:
		return false
	velocity.y = 0.0
	move_and_collide(Vector3.DOWN * drop)
	return true


## Where a ledge climb toward `direction` would end (the body's origin standing on top), or
## `Vector3.INF` if there is no climbable ledge. A ledge counts when a wall is within reach
## at hand height, its top is at least `mantle_min_height` above the feet but no higher than
## the 2/3 rule allows, and the standing body fits on it.
func _find_ledge(direction: Vector2) -> Vector3:
	var space := get_world_3d().direct_space_state
	var forward := Vector3(direction.x, 0.0, direction.y)
	var feet := global_position
	var radius := _capsule.radius
	var max_height := settings.standing_height * (1.0 - settings.mantle_body_above)

	var wall := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * settings.mantle_min_height,
		feet + Vector3.UP * settings.mantle_min_height + forward * (radius + settings.mantle_reach),
		LEDGE_MASK)
	var wall_hit := space.intersect_ray(wall)
	if wall_hit.is_empty() or absf(wall_hit.normal.y) > 0.3 or wall_hit.normal.dot(forward) > -0.5:
		return Vector3.INF

	# Straight down just behind the wall face: the first surface is the ledge's top. If the
	# ledge is higher than allowed the ray starts inside it and finds nothing.
	var over: Vector3 = wall_hit.position + forward * 0.05
	var top := PhysicsRayQueryParameters3D.create(
		Vector3(over.x, feet.y + max_height, over.z), Vector3(over.x, feet.y + settings.mantle_min_height * 0.5, over.z), LEDGE_MASK)
	var top_hit := space.intersect_ray(top)
	if top_hit.is_empty() or top_hit.normal.y < cos(floor_max_angle):
		return Vector3.INF

	var target: Vector3 = Vector3(over.x, top_hit.position.y, over.z) + forward * (radius + 0.02)
	target.y += 0.02
	# The body must fit standing on the ledge.
	var fit := PhysicsShapeQueryParameters3D.new()
	fit.shape = _capsule
	fit.transform = Transform3D(Basis.IDENTITY, target + Vector3.UP * (_capsule.height / 2.0 + 0.02))
	fit.collision_mask = LEDGE_MASK
	if not space.intersect_shape(fit, 1).is_empty():
		return Vector3.INF
	return target


## One tick of a ledge climb: no steering and no gravity. The body is carried up the wall
## (speeding up from whatever vertical speed it had, easing off near the lip) and, once close
## to the lip, over it at the approach speed, so the two blend into one arc. Crouch lets go;
## running into something that stops the climb aborts it.
func _simulate_mantle(delta: float) -> void:
	if _frame.crouch_pressed:
		_end_mantle(Vector3.ZERO)
		return
	var to_target := _mantle_target - global_position
	var rise_left := maxf(to_target.y, 0.0)
	var rise_speed := settings.mantle_rise_speed * clampf(sqrt(rise_left / settings.mantle_ease_distance), 0.25, 1.0)
	velocity.y = minf(move_toward(velocity.y, rise_speed, settings.mantle_accel * delta), rise_left / delta)
	if _mantle == Mantle.RISING and rise_left <= settings.mantle_overlap:
		_mantle = Mantle.FORWARD

	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var speed := 0.0
	var arrived := false
	if _mantle == Mantle.FORWARD:
		var carry := maxf(settings.mantle_forward_speed, _mantle_speed * settings.mantle_momentum)
		speed = move_toward(Vector2(velocity.x, velocity.z).length(), carry, settings.mantle_carry_accel * delta)
		arrived = flat.length() <= maxf(speed * delta, 0.02) and rise_left <= 0.02
		var horizontal := flat.limit_length(speed * delta) / delta
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if arrived:
		_end_mantle(flat.normalized() * speed)
		return

	var expected := velocity.length() * delta
	var before := global_position
	move_and_slide()
	if expected > 0.001 and global_position.distance_to(before) < expected * 0.1:
		_end_mantle(Vector3.ZERO)


func _end_mantle(exit_velocity: Vector3) -> void:
	_mantle = Mantle.NONE
	velocity = exit_velocity


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
	if not (_grounded and has_wish and stance != Stance.SLIDING):
		return
	_distance_since_step += horizontal_speed() * delta
	if _distance_since_step >= settings.footstep_distance:
		_distance_since_step = 0.0
		stepped.emit()
		_broadcast_sound(&"footstep")


# --- Networking -------------------------------------------------------------

## Server: publishes the body's state, once per physics tick, to every peer that has
## this player.
func _publish_snapshot() -> void:
	var tick := Engine.get_physics_frames()
	snapshot = PackedFloat32Array([
		_frame.sequence,
		global_position.x, global_position.y, global_position.z,
		velocity.x, velocity.y, velocity.z,
		yaw, pitch, stance, _slide_elapsed, 1.0 if _grounded else 0.0,
		_mantle, _mantle_target.x, _mantle_target.y, _mantle_target.z, _mantle_speed,
		1.0 if _wall_run else 0.0, _wall_normal.x, _wall_normal.y, _wall_time, _wall_cooldown,
		tick,
	])
	assert(snapshot.size() == Snap.SIZE)
	var connected := multiplayer.get_peers()
	for peer in _snapshot_peers.duplicate():
		if connected.has(peer):
			_rpc_snapshot.rpc_id(peer, snapshot)
		else:
			_snapshot_peers.erase(peer)
	_pose_history.append([tick, global_position, _capsule.height])
	if _pose_history.size() > POSE_HISTORY_TICKS:
		_pose_history.pop_front()


## Client: its copy of this player exists now, so the server may start sending it
## snapshots (earlier ones would hit a node that isn't there yet).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_want_snapshots() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if is_multiplayer_authority() and not _snapshot_peers.has(peer):
		_snapshot_peers.append(peer)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(data: PackedFloat32Array) -> void:
	snapshot = data


## Client: a snapshot arrived (after the simulated lag, if any, for the predicting
## player; remote players are blended at render time).
func _receive_snapshot(data: PackedFloat32Array) -> void:
	if data.size() != Snap.SIZE or NetSim.drops():
		return
	# The server sends on every frame it renders, which can be several times per
	# physics tick: keep only the first copy of each tick.
	var tick: float = data[Snap.TICK]
	if tick <= _newest_tick:
		return
	_newest_tick = tick
	var ready_ms := Time.get_ticks_msec() + NetSim.lag_ms
	if is_local:
		_snapshot_queue.append([ready_ms, data])
		if _snapshot_queue.size() > MAX_BUFFERED_SNAPSHOTS:
			_snapshot_queue.pop_front()
		return
	ready_ms = _steady_ms(tick, ready_ms)
	stance = int(data[Snap.STANCE]) as Stance
	_remote_on_floor = data[Snap.ON_FLOOR] > 0.5
	_interpolation_buffer.append([ready_ms, _snap_vector(data, Snap.POS_X), data[Snap.YAW], data[Snap.PITCH], _snap_vector(data, Snap.VEL_X)])
	if _interpolation_buffer.size() > MAX_BUFFERED_SNAPSHOTS:
		_interpolation_buffer.pop_front()


## When snapshot `tick` is due on this machine's clock. Snapshots reach us unevenly
## (the server sends per rendered frame, the network adds jitter), so the arrival
## time of each one would make remote players stutter. The ticks themselves are
## evenly spaced: follow the earliest arrivals and drift slowly towards later ones.
func _steady_ms(tick: float, arrival_ms: float) -> float:
	var tick_ms := tick / TICKS_PER_MS
	var offset := arrival_ms - tick_ms
	if not _clock_synced or offset < _clock_offset:
		_clock_offset = offset
		_clock_synced = true
	else:
		_clock_offset += (offset - _clock_offset) * CLOCK_DRIFT
	return tick_ms + _clock_offset


## Three consecutive snapshot floats starting at `first` as a vector.
static func _snap_vector(data: PackedFloat32Array, first: Snap) -> Vector3:
	return Vector3(data[first], data[first + 1], data[first + 2])


## Remote player on a client: shows the body where it was `INTERPOLATION_DELAY_MS` ago.
func _interpolate_remote() -> void:
	if _interpolation_buffer.is_empty():
		return
	var render_ms := Time.get_ticks_msec() - INTERPOLATION_DELAY_MS
	while _interpolation_buffer.size() > 2 and _interpolation_buffer[1][Blend.READY_MS] <= render_ms:
		_interpolation_buffer.pop_front()
	var from: Array = _interpolation_buffer[0]
	var to: Array = _interpolation_buffer[1] if _interpolation_buffer.size() > 1 else from
	var span: float = to[Blend.READY_MS] - from[Blend.READY_MS]
	var t := clampf((render_ms - from[Blend.READY_MS]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	# A respawn teleports the body; blending across it would streak.
	if (from[Blend.POSITION] as Vector3).distance_to(to[Blend.POSITION]) > RECONCILE_SNAP_DISTANCE:
		t = 1.0 if t > 0.0 else 0.0
	global_position = (from[Blend.POSITION] as Vector3).lerp(to[Blend.POSITION], t)
	yaw = lerp_angle(from[Blend.YAW], to[Blend.YAW], t)
	pitch = lerpf(from[Blend.PITCH], to[Blend.PITCH], t)
	velocity = (from[Blend.VELOCITY] as Vector3).lerp(to[Blend.VELOCITY], t)


## Predicting client: compares the newest server snapshot with what we predicted
## for the same input, and replays the inputs the server hasn't seen yet if they differ.
func _reconcile(delta: float) -> void:
	var latest := PackedFloat32Array()
	var latest_ms := 0
	var now := Time.get_ticks_msec()
	while not _snapshot_queue.is_empty() and _snapshot_queue[0][Queued.READY_MS] <= now:
		var entry: Array = _snapshot_queue.pop_front()
		latest_ms = entry[Queued.READY_MS]
		latest = entry[Queued.DATA]
	if latest.is_empty():
		return

	_server_tick = latest[Snap.TICK]
	_server_tick_ms = latest_ms
	var ack := int(latest[Snap.ACK])
	var server_position := _snap_vector(latest, Snap.POS_X)
	var server_velocity := _snap_vector(latest, Snap.VEL_X)
	while not _history.is_empty() and _history[0][Step.SEQUENCE] < ack:
		_history.pop_front()

	var distance := INF
	if _synced and not _history.is_empty() and _history[0][Step.SEQUENCE] == ack:
		distance = server_position.distance_to(_history[0][Step.POSITION])
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
		_restore_state(latest)
		yaw = latest[Snap.YAW]
		pitch = latest[Snap.PITCH]
		input.set_look(yaw, pitch)
		_history.clear()
		_error_offset = Vector3.ZERO
		reset_physics_interpolation()
		return

	var predicted_end := global_position
	global_position = server_position
	velocity = server_velocity
	_restore_state(latest)
	var current := _frame
	_replaying = true
	for entry in _history:
		_frame = entry[Step.FRAME]
		_simulate(delta)
		entry[Step.POSITION] = global_position
	_replaying = false
	_frame = current
	_error_offset += predicted_end - global_position


## Predicting client: the movement state (besides position and velocity) of a snapshot.
func _restore_state(data: PackedFloat32Array) -> void:
	stance = int(data[Snap.STANCE]) as Stance
	_slide_elapsed = data[Snap.SLIDE]
	_mantle = int(data[Snap.MANTLE]) as Mantle
	_grounded = data[Snap.ON_FLOOR] > 0.5
	_mantle_target = _snap_vector(data, Snap.TARGET_X)
	_mantle_speed = data[Snap.MANTLE_SPEED]
	_wall_run = data[Snap.WALL_RUN] > 0.5
	_wall_normal = Vector2(data[Snap.WALL_NX], data[Snap.WALL_NZ])
	_wall_time = data[Snap.WALL_TIME]
	_wall_cooldown = data[Snap.WALL_COOLDOWN]


## Predicting client: the server tick whose state other players are drawn at right
## now (they are shown `INTERPOLATION_DELAY_MS` in the past). Sent with each input
## so the server can rewind targets to what this player saw when shooting.
func view_tick() -> float:
	if _server_tick_ms == 0:
		return 0.0
	var ahead := (Time.get_ticks_msec() - _server_tick_ms - INTERPOLATION_DELAY_MS) * TICKS_PER_MS
	return _server_tick + ahead


## Server: where this body was at `tick` (fractional ticks blend), as
## a `Pose` entry (foot position, capsule height). Lag compensation tests shots
## against this.
func pose_at(tick: float) -> Array:
	if _pose_history.size() < 2:
		return [tick, global_position, _capsule.height]
	var newest: float = _pose_history[-1][Pose.TICK]
	tick = clampf(tick, maxf(newest - MAX_REWIND_TICKS, _pose_history[0][Pose.TICK]), newest)
	var before: Array = _pose_history[0]
	var after: Array = _pose_history[-1]
	for i in range(_pose_history.size() - 1, 0, -1):
		if _pose_history[i - 1][Pose.TICK] <= tick:
			before = _pose_history[i - 1]
			after = _pose_history[i]
			break
	var span: float = after[Pose.TICK] - before[Pose.TICK]
	var t := clampf((tick - before[Pose.TICK]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	return [tick, (before[Pose.POSITION] as Vector3).lerp(after[Pose.POSITION], t), after[Pose.HEIGHT] if t > 0.5 else before[Pose.HEIGHT]]


func body_radius() -> float:
	return _capsule.radius


## Server: lets every other peer hear this player's jump or step; their copy of
## the body doesn't simulate, so it can't emit `jumped`/`stepped` itself.
func _broadcast_sound(sound: StringName) -> void:
	if is_multiplayer_authority():
		_rpc_sound.rpc(sound)


@rpc("authority", "call_remote", "unreliable")
func _rpc_sound(sound: StringName) -> void:
	if is_local:
		return
	if sound == &"jump":
		jumped.emit()
	else:
		stepped.emit()


func _show_held_weapons() -> void:
	if not is_node_ready():
		return
	var catalog := WeaponCatalog.get_default()
	_visual.set_weapons(catalog.find(held_primary), catalog.find(held_secondary))
