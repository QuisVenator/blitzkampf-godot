class_name InputSource
extends RefCounted
## Produces `InputFrame`s for a `PlayerInput`. Subclass it: `LocalInput` (keyboard
## and mouse), `ScriptedInput` (tests, bots).


## Raw input events reach the source here; it may change `input.look_yaw/look_pitch`.
func handle_event(_event: InputEvent, _input: PlayerInput) -> void:
	pass


## Called once per physics tick.
func sample(_input: PlayerInput) -> InputFrame:
	return InputFrame.new()
