class_name InputSource
extends RefCounted
## Produces `InputFrame`s for a `PlayerInput`. Subclass it: `LocalInput` (keyboard
## and mouse), `ScriptedInput` (tests, bots).


## Raw input events reach the source here; it may change `input.look_yaw/look_pitch`.
func handle_event(_event: InputEvent, _input: PlayerInput) -> void:
	pass


## A second frame to simulate in the same tick, to catch up on a backlog (network
## sources only). Ask only after `sample()` for the tick; null = none.
func extra_frame() -> InputFrame:
	return null


## Called once per physics tick.
func sample(_input: PlayerInput) -> InputFrame:
	return InputFrame.new()
