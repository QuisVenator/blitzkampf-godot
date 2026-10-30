class_name PauseMenu
extends CanvasLayer
## Esc pauses the game (the scene tree) and shows this menu; Esc or Resume
## continues. Runs while paused (process mode "Always" in the scene).

@onready var _resume: Button = %ResumeButton
@onready var _resolution: OptionButton = %ResolutionOption
@onready var _fullscreen: CheckButton = %FullscreenCheck
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	hide()
	_resume.pressed.connect(resume)
	_quit.pressed.connect(get_tree().quit)
	_resolution.item_selected.connect(_on_resolution_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_refresh_options()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if get_tree().paused:
			resume()
		else:
			pause()


func pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_options()
	show()
	_resume.grab_focus()


func resume() -> void:
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_options() -> void:
	_resolution.clear()
	var selected := 0
	for size in GameSettings.available_resolutions():
		_resolution.add_item("%d x %d" % [size.x, size.y])
		_resolution.set_item_metadata(_resolution.item_count - 1, size)
		if size == GameSettings.resolution:
			selected = _resolution.item_count - 1
	_resolution.select(selected)
	_resolution.disabled = GameSettings.fullscreen
	_fullscreen.set_pressed_no_signal(GameSettings.fullscreen)


func _on_resolution_selected(index: int) -> void:
	GameSettings.set_resolution(_resolution.get_item_metadata(index))


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.set_fullscreen(enabled)
	_resolution.disabled = enabled
