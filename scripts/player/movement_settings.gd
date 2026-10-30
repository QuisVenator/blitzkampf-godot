class_name MovementSettings
extends Resource
## Tuning for the player's Quake-style movement. Gravity comes from the
## project's 3D physics settings.

@export_group("Ground")
@export var max_ground_speed := 7.0
@export var max_sprint_speed := 11.0
@export var max_crouch_speed := 3.5
@export var ground_accel := 70.0
@export var ground_friction := 8.0
@export var stop_speed := 1.5

@export_group("Air")
@export var air_accel := 30.0
@export var max_air_speed := 7.0
@export var jump_speed := 7.0

@export_group("Slide")
@export var slide_entry_speed := 11.0
## Much lower than ground friction: a slide should coast, not stop.
@export var slide_friction := 2.5
## Seconds at the start of a slide where speed is held flat.
@export var slide_sustain_duration := 0.15

@export_group("Body")
@export var standing_height := 1.8
@export var crouch_height := 0.9
@export var eye_height := 1.6
@export var crouch_eye_height := 1.0
@export var eye_ease_time := 0.12

@export_group("Look and feedback")
@export var mouse_sensitivity := 0.0022
@export var footstep_distance := 2.2
