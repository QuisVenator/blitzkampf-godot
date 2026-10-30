class_name QuakeMovement
extends RefCounted
## Quake/Source-style horizontal movement helpers (x = world X, y = world Z).


## Ground friction. Below stop_speed the drop is a flat rate, so the player
## comes to a full stop instead of ice-skating.
static func apply_friction(velocity: Vector2, friction: float, stop_speed: float, delta: float) -> Vector2:
	var speed := velocity.length()
	if speed < 0.000001:
		return Vector2.ZERO
	var control := stop_speed if speed < stop_speed else speed
	var new_speed := maxf(speed - control * friction * delta, 0.0)
	return velocity * (new_speed / speed)


## PM_Accelerate: only adds the speed missing along wish_dir (unit or zero),
## which is what allows air-strafing while capping straight-line speed.
static func accelerate(velocity: Vector2, wish_dir: Vector2, wish_speed: float, accel: float, delta: float) -> Vector2:
	var add_speed := wish_speed - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return velocity
	return velocity + wish_dir * minf(accel * delta * wish_speed, add_speed)
