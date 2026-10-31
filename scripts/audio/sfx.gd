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
## Positional sounds: loudness falls off from this distance (m), silent beyond the max.
const SPATIAL_UNIT_SIZE := 6.0
const SPATIAL_MAX_DISTANCE := 80.0

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


## A sound in the world (another player's shot, footstep...). Frees itself when done.
func play_at(sound_name: StringName, position: Vector3, pitch_scale := 1.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = STREAMS[sound_name]
	player.pitch_scale = pitch_scale
	player.top_level = true
	player.unit_size = SPATIAL_UNIT_SIZE
	player.max_distance = SPATIAL_MAX_DISTANCE
	add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
