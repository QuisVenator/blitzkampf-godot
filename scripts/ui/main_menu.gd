extends Control
## Entry scene: single player, host, join. A role chosen on the command line
## (`--host`, `--server`, `--join=`) skips straight into the game.

const GAME_SCENE := "res://scenes/main.tscn"

@onready var _address: LineEdit = %AddressEdit
@onready var _status: Label = %StatusLabel
@onready var _map: OptionButton = %MapOption


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_address.text = Net.address
	_status.text = Net.last_error
	_fill_maps()
	%SingleButton.pressed.connect(_start.bind(Net.Role.OFFLINE))
	%HostButton.pressed.connect(_start.bind(Net.Role.HOST))
	%JoinButton.pressed.connect(_start.bind(Net.Role.CLIENT))
	%QuitButton.pressed.connect(get_tree().quit)
	%SingleButton.grab_focus()
	if Net.cli_autostart:
		Net.cli_autostart = false
		_start.call_deferred(Net.role)


## Lists the catalog's maps and preselects `Net.map_id` (the `--map=` argument or the last game).
func _fill_maps() -> void:
	var maps := MapCatalog.get_default().maps
	for index in maps.size():
		_map.add_item(maps[index].display_name, index)
		if maps[index].id == Net.map_id:
			_map.select(index)


func _start(role: Net.Role) -> void:
	Net.role = role
	# Joining plays the server's map; otherwise the chosen one.
	if role != Net.Role.CLIENT:
		Net.map_id = MapCatalog.get_default().maps[_map.selected].id
	if role == Net.Role.CLIENT and Net.arg("join").is_empty():
		Net.address = _address.text.strip_edges()
	get_tree().change_scene_to_file(GAME_SCENE)
