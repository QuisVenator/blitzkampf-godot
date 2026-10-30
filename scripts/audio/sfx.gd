class_name Sfx
extends Node
## Plays the game's sound effects by name. Replace the .wav files in
## res://audio/sfx to change the sounds; nothing else needs to change.

const STREAMS := {
	&"fire": preload("res://audio/sfx/fire.wav"),
	&"hit": preload("res://audio/sfx/hit.wav"),
	&"jump": preload("res://audio/sfx/jump.wav"),
	&"footstep": preload("res://audio/sfx/footstep.wav"),
	&"pickup": preload("res://audio/sfx/pickup.wav"),
	&"reload": preload("res://audio/sfx/reload.wav"),
}
const POLYPHONY := 4

var _players: Dictionary[StringName, AudioStreamPlayer] = {}


func _ready() -> void:
	for sound_name: StringName in STREAMS:
		var player := AudioStreamPlayer.new()
		player.stream = STREAMS[sound_name]
		player.max_polyphony = POLYPHONY
		add_child(player)
		_players[sound_name] = player


func play(sound_name: StringName, pitch_scale := 1.0) -> void:
	var player := _players[sound_name]
	player.pitch_scale = pitch_scale
	player.play()
