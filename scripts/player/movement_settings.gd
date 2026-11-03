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
@export var slide_entry_speed := 12.0
## Much lower than ground friction: a slide should coast, not stop.
@export var slide_friction := 2.5
## Seconds at the start of a slide where speed is held flat.
@export var slide_sustain_duration := 0.15

@export_group("Ledge climb")
## Jumping toward a ledge climbs it once at least this fraction of the standing body is
## above the ledge's top (so the top is at most `(1 - fraction) * standing_height` above the feet).
@export_range(0.0, 1.0) var mantle_body_above := 0.667
## Ledges lower than this above the feet are not climbed (nothing to grab).
@export var mantle_min_height := 0.2
## How far in front of the body a wall still counts as "toward the ledge".
@export var mantle_reach := 0.4
## Speed of the vertical part of the climb, then of the part that carries you over the lip.
@export var mantle_rise_speed := 7.0
@export var mantle_forward_speed := 4.5
## Horizontal speed you keep when the climb ends.
@export var mantle_exit_speed := 3.0

@export_group("Body")
@export var standing_height := 1.8
@export var crouch_height := 0.9
@export var eye_height := 1.6
@export var crouch_eye_height := 1.0
@export var eye_ease_time := 0.12

@export_group("Look and feedback")
@export var mouse_sensitivity := 0.0022
@export var footstep_distance := 2.2
