extends Node
## Autoload "GameSettings": user-facing options that persist between runs
## (`user://settings.cfg`) and are applied to the window at startup.
## Resolution applies to windowed mode; fullscreen uses the display's own size.

const PATH := "user://settings.cfg"
const SECTION := "display"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var fullscreen := false
var resolution := RESOLUTIONS[0]


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
		resolution = config.get_value(SECTION, "resolution", resolution)
	_apply()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply()
	_save()


func set_resolution(size: Vector2i) -> void:
	resolution = size
	_apply()
	_save()


## Resolutions the current display can show, plus the chosen one.
func available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size(get_window().current_screen)
	var result: Array[Vector2i] = []
	for candidate in RESOLUTIONS:
		if candidate == resolution or (candidate.x <= screen_size.x and candidate.y <= screen_size.y):
			result.append(candidate)
	return result


func _apply() -> void:
	# The headless display server (tests) has no real window.
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	window.size = resolution
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = usable.position + (usable.size - resolution) / 2


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "resolution", resolution)
	config.save(PATH)
