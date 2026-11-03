class_name ScriptedInput
extends InputSource
## Input set from code: tests and (later) bots poke `frame` directly. Edge events
## (`*_pressed`) are delivered for one tick and then cleared.

var frame := InputFrame.new()


func sample(_input: PlayerInput) -> InputFrame:
	var result := InputFrame.new()
	result.move = frame.move
	result.yaw = frame.yaw
	result.pitch = frame.pitch
	result.jump = frame.jump
	result.sprint = frame.sprint
	result.crouch = frame.crouch
	result.fire = frame.fire
	result.fire_secondary = frame.fire_secondary
	result.aim = frame.aim
	result.jump_pressed = frame.jump_pressed
	result.crouch_pressed = frame.crouch_pressed
	result.reload_pressed = frame.reload_pressed
	result.interact_pressed = frame.interact_pressed
	result.interact_alt_pressed = frame.interact_alt_pressed
	frame.clear_edges()
	return result
