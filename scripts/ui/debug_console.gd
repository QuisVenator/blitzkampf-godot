class_name DebugConsole
extends CanvasLayer
## In-game command console (F1). Lines you submit go out through
## `command_submitted`; `Main` runs them on the server and prints the reply here.
## While open the mouse is free, so gameplay input is inert (see `GameInput`).

signal command_submitted(line: String)

const MAX_HISTORY := 50

var _history: Array[String] = []
var _history_index := 0

@onready var _log: RichTextLabel = $Panel/Box/Log
@onready var _line: LineEdit = $Panel/Box/Input


func _ready() -> void:
	visible = false
	_line.text_submitted.connect(_on_text_submitted)


func print_line(text: String) -> void:
	if text != "":
		_log.append_text(text.replace("[", "[lb]") + "\n")


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_line.grab_focus()


func close() -> void:
	visible = false
	_line.release_focus()
	var pause_menu := get_parent().get_node_or_null("PauseMenu") as CanvasLayer
	if pause_menu == null or not pause_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## `_input` (not `_unhandled_input`) so F1 and Esc work while the line edit has focus,
## and Esc closes the console instead of opening the pause menu.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_console"):
		get_viewport().set_input_as_handled()
		close() if visible else open()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif visible and event.is_action_pressed(&"ui_up"):
		get_viewport().set_input_as_handled()
		_browse_history(-1)
	elif visible and event.is_action_pressed(&"ui_down"):
		get_viewport().set_input_as_handled()
		_browse_history(1)


func _on_text_submitted(line: String) -> void:
	_line.clear()
	if line.strip_edges().is_empty():
		return
	print_line("> " + line)
	_history.append(line)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_history_index = _history.size()
	if line.strip_edges() == "clear":
		_log.clear()
		return
	command_submitted.emit(line)


func _browse_history(direction: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + direction, 0, _history.size())
	_line.text = _history[_history_index] if _history_index < _history.size() else ""
	_line.caret_column = _line.text.length()
