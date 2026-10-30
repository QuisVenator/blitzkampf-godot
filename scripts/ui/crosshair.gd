class_name Crosshair
extends Control
## Accuracy crosshair: a dot at near-perfect accuracy, otherwise four lines
## whose gap grows with the current shot cone, so it never lies about spread.

const DOT_THRESHOLD_DEG := 0.3
const GAP_BASE_PX := 6.0
const GAP_PER_DEGREE_PX := 10.0
const GAP_MAX_PX := 60.0
const LINE_LENGTH := 8.0
const LINE_WIDTH := 2.0
const DOT_RADIUS := 3.0
const GAP_EASE_TIME := 0.1
const COLOR := Color(1.0, 1.0, 1.0, 0.85)

var _gap := GAP_BASE_PX
var _dot := true
var _spread := -1.0
var _tween: Tween


func set_spread(degrees: float) -> void:
	if degrees < 0.0 or is_equal_approx(degrees, _spread):
		return
	_spread = degrees
	_dot = degrees <= DOT_THRESHOLD_DEG
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_gap, _gap, minf(GAP_MAX_PX, GAP_BASE_PX + degrees * GAP_PER_DEGREE_PX), GAP_EASE_TIME)
	queue_redraw()


func _set_gap(value: float) -> void:
	_gap = value
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	if _dot:
		draw_circle(center, DOT_RADIUS, COLOR)
		return
	var half_width := LINE_WIDTH / 2.0
	draw_rect(Rect2(center.x - half_width, center.y - _gap - LINE_LENGTH, LINE_WIDTH, LINE_LENGTH), COLOR)
	draw_rect(Rect2(center.x - half_width, center.y + _gap, LINE_WIDTH, LINE_LENGTH), COLOR)
	draw_rect(Rect2(center.x - _gap - LINE_LENGTH, center.y - half_width, LINE_LENGTH, LINE_WIDTH), COLOR)
	draw_rect(Rect2(center.x + _gap, center.y - half_width, LINE_LENGTH, LINE_WIDTH), COLOR)
