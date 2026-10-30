class_name Hitmarker
extends Control
## Red "X" flashed at screen centre when a shot hits a target.

const HOLD_TIME := 0.12
const FADE_TIME := 0.06
const HALF_EXTENT := 8.5
const WIDTH := 2.0
const COLOR := Color("ff3b3b")

var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0


func flash() -> void:
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)


func _draw() -> void:
	var center := size / 2.0
	draw_line(center + Vector2(-HALF_EXTENT, -HALF_EXTENT), center + Vector2(HALF_EXTENT, HALF_EXTENT), COLOR, WIDTH)
	draw_line(center + Vector2(-HALF_EXTENT, HALF_EXTENT), center + Vector2(HALF_EXTENT, -HALF_EXTENT), COLOR, WIDTH)
