class_name InputFrame
extends RefCounted
## Everything a player asked for during one physics tick. The simulation (movement,
## weapons) reads only this, so the source can be the local keyboard and mouse,
## a script or bot, or later the network.

## Move intent: x = right, y = back (same axes as `Input.get_vector`).
var move := Vector2.ZERO
## View angles in radians.
var yaw := 0.0
var pitch := 0.0

# Held buttons.
var jump := false
var sprint := false
var crouch := false
var fire := false
var fire_secondary := false
var aim := false

# Edge events: true only for the tick in which the button went down.
var crouch_pressed := false
var reload_pressed := false
var interact_pressed := false
var interact_alt_pressed := false


func clear_edges() -> void:
	crouch_pressed = false
	reload_pressed = false
	interact_pressed = false
	interact_alt_pressed = false
