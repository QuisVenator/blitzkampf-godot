class_name GameInput
extends RefCounted
## Input queries that only report while the mouse is captured, so gameplay is
## inert while the cursor is freed (Esc).


## Lets automated tests drive input under the headless display server, which
## doesn't keep the mouse mode.
static var force_active := false


static func is_active() -> bool:
	return force_active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


static func held(action: StringName) -> bool:
	return is_active() and Input.is_action_pressed(action)


static func just_pressed(action: StringName) -> bool:
	return is_active() and Input.is_action_just_pressed(action)


static func move_vector() -> Vector2:
	if not is_active():
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
