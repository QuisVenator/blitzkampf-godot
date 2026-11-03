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

@export_group("Stairs")
## Highest step the body walks up without jumping (stairs, curbs). Also how far down it
## stays glued to the floor, so walking down stairs doesn't turn into a series of falls.
@export var step_height := 0.35
## Steps lower than this are left to the engine (ramps and bumps need no lift).
@export var step_min_height := 0.08
## How tightly the camera follows steps (spring frequency, 1/s). Lower is smoother but the view
## sags further behind on a long staircase (about 2 x climb speed / this); higher is crisper.
@export var step_view_smoothing := 28.0

@export_group("Ledge climb")
## Jumping toward a ledge climbs it once at least this fraction of the standing body is
## above the ledge's top (so the top is at most `(1 - fraction) * standing_height` above the feet).
@export_range(0.0, 1.0) var mantle_body_above := 0.667
## Ledges lower than this above the feet are not climbed (nothing to grab).
@export var mantle_min_height := 0.2
## How far in front of the body a wall still counts as "toward the ledge".
@export var mantle_reach := 0.4
## Speed of the climb up the wall; it eases off over the last `mantle_ease_distance` below the lip.
@export var mantle_rise_speed := 7.0
@export var mantle_ease_distance := 0.6
## The carry over the lip starts this far below the lip, so up and forward blend into one arc.
@export var mantle_overlap := 0.15
## How quickly the climb speeds up and slows down (m/s per second); this is the easing.
@export var mantle_accel := 60.0
## The same for the carry over the lip (horizontal): high, or a sprint loses time getting going again.
@export var mantle_carry_accel := 130.0
## Slowest the carry over the lip may be, and the share of your approach speed it keeps
## (a sprint into a ledge stays fast).
@export var mantle_forward_speed := 5.0
@export_range(0.0, 1.0) var mantle_momentum := 1.0

@export_group("Wall run")
## Jump or fall along a wall at this horizontal speed to start running on it.
@export var wallrun_min_speed := 6.0
## The run ends when the speed along the wall drops below this.
@export var wallrun_stay_speed := 3.0
## A wall this close to the body's side counts.
@export var wallrun_reach := 0.35
## The feet must be at least this high above the floor to start a run.
@export var wallrun_min_height := 0.6
@export var wallrun_max_duration := 4.0
## Speed along the wall, which the run accelerates toward.
@export var wallrun_speed := 10.0
@export var wallrun_accel := 25.0
## Gravity multiplier at the start and at the end of a run (it grows over the duration).
@export var wallrun_gravity_start := 0.0
@export var wallrun_gravity_end := 0.25
## Vertical speed when a run starts (0 = purely horizontal; positive hops up onto the wall).
@export var wallrun_entry_vertical_speed := 0.0
## Speed pressing the body into the wall, so it keeps contact.
@export var wallrun_stick := 1.5
## Wall jump: up speed and speed away from the wall (the speed along it is kept).
@export var wallrun_jump_up := 6.5
@export var wallrun_jump_push := 6.0
## Seconds after leaving a wall before any wall can be grabbed again.
@export var wallrun_cooldown := 0.4
## Camera roll (degrees) away from the wall while running.
@export var wallrun_camera_roll := 10.0

@export_group("Body")
@export var standing_height := 1.8
## Matches the character model's crouch pose (its head reaches about 1.2 m), so the hitbox covers it.
@export var crouch_height := 1.2
@export var eye_height := 1.6
@export var crouch_eye_height := 1.0
@export var eye_ease_time := 0.12

@export_group("Speed FOV")
## Extra vertical field of view (degrees) at `speed_fov_full_speed`, none at `speed_fov_threshold`
## (in between it scales): the view widens while you are faster than a sprint (a slide's boost),
## and relaxes back as the speed falls. Not while aiming down sights.
@export var speed_fov_boost := 10.0
@export var speed_fov_threshold := 10.0
@export var speed_fov_full_speed := 12.0
## How quickly the view widens and relaxes (rates, 1/s; higher = faster).
@export var speed_fov_attack := 14.0
@export var speed_fov_release := 3.5

@export_group("Look and feedback")
@export var mouse_sensitivity := 0.0022
@export var footstep_distance := 2.2
