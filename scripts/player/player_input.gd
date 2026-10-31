class_name PlayerInput
extends Node
## Where a player's input comes from. Gameplay code asks `frame()` for the
## current tick's `InputFrame` and never touches `Input` directly; swap `source`
## to drive the same player from a script, a bot or the network.
##
## `look_yaw`/`look_pitch` are the live view angles. For the local player they
## change with every mouse event (so looking is never tied to the physics tick);
## each sampled frame carries a snapshot for the simulation.

var source: InputSource = LocalInput.new()
var mouse_sensitivity := 0.0022
var look_yaw := 0.0
var look_pitch := 0.0

var _frame := InputFrame.new()
var _frame_tick := -1


## The frame for this physics tick; sampled once per tick, so every consumer sees
## the same one and edge events aren't consumed twice.
func frame() -> InputFrame:
	var tick := Engine.get_physics_frames()
	if tick != _frame_tick:
		_frame_tick = tick
		_frame = source.sample(self)
		look_yaw = _frame.yaw
		look_pitch = _frame.pitch
	return _frame


func set_look(yaw: float, pitch: float) -> void:
	look_yaw = yaw
	look_pitch = pitch


func _unhandled_input(event: InputEvent) -> void:
	source.handle_event(event, self)
