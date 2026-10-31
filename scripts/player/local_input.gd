class_name LocalInput
extends InputSource
## Keyboard and mouse through the Input Map (via `GameInput`, which reports
## nothing while the mouse isn't captured).

const MAX_PITCH := PI / 2.0 - 0.01


func handle_event(event: InputEvent, input: PlayerInput) -> void:
	if event is InputEventMouseMotion and GameInput.is_active():
		var motion := event as InputEventMouseMotion
		input.look_yaw -= motion.relative.x * input.mouse_sensitivity
		input.look_pitch = clampf(input.look_pitch - motion.relative.y * input.mouse_sensitivity, -MAX_PITCH, MAX_PITCH)


func sample(input: PlayerInput) -> InputFrame:
	var frame := InputFrame.new()
	frame.move = GameInput.move_vector()
	frame.yaw = input.look_yaw
	frame.pitch = input.look_pitch
	frame.jump = GameInput.held(&"jump")
	frame.sprint = GameInput.held(&"sprint")
	frame.crouch = GameInput.held(&"crouch")
	frame.fire = GameInput.held(&"fire")
	frame.fire_secondary = GameInput.held(&"fire_secondary")
	frame.aim = GameInput.held(&"aim")
	frame.crouch_pressed = GameInput.just_pressed(&"crouch")
	frame.reload_pressed = GameInput.just_pressed(&"reload")
	frame.interact_pressed = GameInput.just_pressed(&"interact")
	frame.interact_alt_pressed = GameInput.just_pressed(&"interact_alt")
	return frame
