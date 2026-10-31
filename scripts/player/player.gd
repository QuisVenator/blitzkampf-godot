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

const MAX_PITCH := PI / 2.0 - 0.01
const DEAD_EYE_HEIGHT := 0.4

@export var settings: MovementSettings
@export var max_health := 100
@export var respawn_delay := 3.0

var stance := Stance.STANDING
var yaw := 0.0
var pitch := 0.0
var health := 100
var alive := true

var _slide_elapsed := 0.0
var _distance_since_step := 0.0
var _eye_height := 0.0
var _eye_tween: Tween
var _capsule: CapsuleShape3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_area: Area3D = $InteractArea
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _headroom_cast: ShapeCast3D = $HeadroomCast


func _ready() -> void:
	_capsule = _collision_shape.shape as CapsuleShape3D
	_eye_height = settings.eye_height
	_apply_body_height(false)
	_update_camera()


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
	health_changed.emit(health, max_health)
	respawned.emit()


## Called by whatever hurt the player (hitscan today). Ignored while dead.
func take_damage(amount: int, attacker: Node = null) -> void:
	if not alive:
		return
	health = maxi(health - amount, 0)
	damaged.emit(amount, attacker)
	health_changed.emit(health, max_health)
	if health == 0:
		_die(attacker)


func _die(attacker: Node) -> void:
	alive = false
	_slide_elapsed = 0.0
	if _eye_tween:
		_eye_tween.kill()
	_eye_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_eye_tween.tween_property(self, "_eye_height", DEAD_EYE_HEIGHT, settings.eye_ease_time)
	died.emit(attacker)
	get_tree().create_timer(respawn_delay).timeout.connect(spawn)


func teleport(to: Vector3, new_yaw: float) -> void:
	global_position = to
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0
	reset_physics_interpolation()
	_update_camera()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and GameInput.is_active():
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * settings.mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * settings.mouse_sensitivity, -MAX_PITCH, MAX_PITCH)


func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	var eye_position := get_global_transform_interpolated().origin + Vector3.UP * _eye_height
	head.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), eye_position)


func _physics_process(delta: float) -> void:
	var input := GameInput.move_vector()
	var has_wish := input != Vector2.ZERO
	var wish_world := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
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

	if GameInput.held(&"jump") and grounded:
		velocity.y = settings.jump_speed
		jumped.emit()
		if stance == Stance.SLIDING:
			stance = Stance.CROUCHING
		# Jumping out of a crouch stands you up unless something is overhead.
		if stance == Stance.CROUCHING and _can_stand():
			_set_stance(Stance.STANDING)

	move_and_slide()
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
	if has_wish and GameInput.held(&"sprint"):
		return settings.max_sprint_speed
	return settings.max_ground_speed


## Crouch is a held stance; a fresh press while sprinting, grounded and moving
## starts a slide instead. A slide ends when crouch is released (so slides can
## be chained with short sprints) or once it has bled off too much speed.
func _update_stance(has_wish: bool, wish_dir: Vector2, grounded: bool, delta: float) -> void:
	if GameInput.just_pressed(&"crouch") and stance == Stance.STANDING:
		_set_stance(Stance.CROUCHING)
		if grounded and has_wish and GameInput.held(&"sprint"):
			_start_slide(wish_dir)

	if stance == Stance.SLIDING:
		_slide_elapsed += delta
		if not grounded or horizontal_speed() <= settings.max_crouch_speed:
			stance = Stance.CROUCHING

	if stance != Stance.STANDING and not GameInput.held(&"crouch") and _can_stand():
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
	var was_crouched := stance != Stance.STANDING
	stance = new_stance
	var crouched := new_stance != Stance.STANDING
	if crouched != was_crouched:
		_apply_body_height(crouched)


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
