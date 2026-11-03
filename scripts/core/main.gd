class_name Main
extends Node3D
## The game scene for single player, host, dedicated server and client alike.
## Starts networking (`Net`), spawns a `Player` for every participant through the
## `MultiplayerSpawner`, and wires the local player's signals to the HUD and sounds.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MAP_SETTINGS := "res://resources/maps/map_settings.tres"
const DROPPED_WEAPON_SCENE := preload("res://scenes/weapons/dropped_weapon.tscn")

## The player this machine's human controls (null on a dedicated server).
var local_player: Player

var _next_bot_id := Player.BOT_ID_BASE
var _commands := DebugCommands.new()

@onready var _map: Node3D = $Map
@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _drop_spawner: MultiplayerSpawner = $DropSpawner
@onready var _console: DebugConsole = $DebugConsole
@onready var _hud: Hud = $Hud
@onready var _sfx: Sfx = $Sfx


func _ready() -> void:
	_spawner.spawn_function = _spawn_player
	_drop_spawner.spawn_function = WeaponManager.spawn_dropped.bind(DROPPED_WEAPON_SCENE)
	_players.child_entered_tree.connect(_on_player_entered)
	_console.command_submitted.connect(submit_command)
	Net.connection_lost.connect(_return_to_menu)
	if Net.role == Net.Role.CLIENT:
		# The server decides the map; replicated nodes need it built before they arrive.
		Net.map_received.connect(_on_map_received)
	else:
		_load_map(Net.map_id)

	if Net.start() != OK:
		_return_to_menu.call_deferred(Net.last_error)
		return
	if multiplayer.is_server():
		Net.player_joined.connect(_on_peer_joined)
		Net.player_left.connect(_on_peer_left)
		# Single player and the host play too; a dedicated server doesn't.
		if Net.role != Net.Role.SERVER:
			_spawner.spawn({"peer": 1})
	if Net.scenario != "":
		_start_scenario.call_deferred()


## Puts the map into the `Map` node: a scene is instanced, a TrenchBroom `.map` is built by
## FuncGodot (synchronously). Done before any player exists, so spawn markers and weapon
## spawners are there when they are needed. An unknown id means the first map, unless
## `strict` (a client asked for the server's map): then it fails. Sets `Net.map_id` to the
## map actually loaded.
func _load_map(id: StringName, strict := false) -> bool:
	var catalog := MapCatalog.get_default()
	var definition := catalog.find(id) if strict else catalog.find_or_default(id)
	if definition == null:
		return false
	Net.map_id = definition.id
	if definition.scene:
		_map.add_child(definition.scene.instantiate())
		return true
	var builder := FuncGodotMap.new()
	builder.name = "MapBuilder"  # replicated nodes below it are found by path, so no auto-generated name
	builder.map_settings = load(MAP_SETTINGS)
	builder.local_map_file = definition.map_file
	_map.add_child(builder)
	builder.build()
	return true


func _on_map_received(id: StringName) -> void:
	if _load_map(id, true):
		Net.map_loaded()
	else:
		_return_to_menu("The server plays the map '%s', which this version does not have" % id)


## Runs on every peer with the same data, so the replicated tree matches.
func _spawn_player(data: Dictionary) -> Node:
	var peer: int = data["peer"]
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = str(peer)
	player.peer_id = peer
	player.is_local = peer == multiplayer.get_unique_id()
	player.is_bot = data.get("bot", false)
	if player.is_bot and multiplayer.is_server():
		player.get_node("PlayerInput").source = BotInput.new()
	# The player body belongs to the server; each owner's client sends it input.
	player.get_node("PlayerInput").set_multiplayer_authority(peer)
	player.get_node("NetInput").set_multiplayer_authority(peer)
	return player


## Server: adds an AI player.
func spawn_bot() -> Player:
	_next_bot_id += 1
	return _spawner.spawn({"peer": _next_bot_id, "bot": true}) as Player


## Server: removes every bot; returns how many.
func clear_bots() -> int:
	var removed := 0
	for player in players():
		if player.is_bot:
			player.queue_free()
			removed += 1
	return removed


func players() -> Array[Player]:
	var result: Array[Player] = []
	for child in _players.get_children():
		if child is Player and not child.is_queued_for_deletion():
			result.append(child)
	return result


## Runs a console line on the server (here, if this is the server) and prints the reply.
func submit_command(line: String) -> void:
	if multiplayer.is_server():
		_execute_command(line, multiplayer.get_unique_id())
	else:
		_rpc_command.rpc_id(1, line)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(line: String) -> void:
	_execute_command(line, multiplayer.get_remote_sender_id())


func _execute_command(line: String, sender: int) -> void:
	var own := sender == multiplayer.get_unique_id()
	var output := ""
	if not own and not Net.cheats:
		output = "Console commands from clients are disabled on this server (it needs --cheats)"
	else:
		output = _commands.run(self, _players.get_node_or_null(str(sender)) as Player, line)
	if own:
		_console.print_line(output)
	else:
		_rpc_output.rpc_id(sender, output)


@rpc("authority", "call_remote", "reliable")
func _rpc_output(text: String) -> void:
	_console.print_line(text)


func _on_peer_joined(peer: int) -> void:
	# The peer built the map, so the map's replicated nodes can reach it now.
	get_tree().call_group(&"weapon_spawner", "show_to", peer)
	_spawner.spawn({"peer": peer})


func _on_peer_left(peer: int) -> void:
	var player := _players.get_node_or_null(str(peer))
	if player:
		player.queue_free()


func _on_player_entered(node: Node) -> void:
	var player := node as Player
	if player == null:
		return
	if not player.is_local:
		_hear_player(player)
		return
	local_player = player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await player.ready
	var weapons := player.get_node("WeaponManager") as WeaponManager
	_hud.bind(player, weapons)
	player.jumped.connect(_sfx.play.bind(&"jump"))
	player.stepped.connect(_sfx.play.bind(&"footstep"))
	weapons.fired.connect(func(definition: WeaponDefinition) -> void: _sfx.play(&"fire", definition.fire_pitch_scale))
	weapons.hit_confirmed.connect(_sfx.play.bind(&"hit"))
	weapons.reload_started.connect(func(_definition: WeaponDefinition) -> void: _sfx.play(&"reload"))
	weapons.picked_up.connect(_sfx.play.bind(&"pickup"))


## Another player's jumps, steps, shots and reloads are heard from where they happen.
func _hear_player(player: Player) -> void:
	player.jumped.connect(func() -> void: _sfx.play_at(&"jump", player.global_position))
	player.stepped.connect(func() -> void: _sfx.play_at(&"footstep", player.global_position))
	await player.ready
	var weapons := player.get_node("WeaponManager") as WeaponManager
	weapons.heard.connect(_sfx.play_at)


## A window that starts unfocused (a second local instance, alt-tab) can't grab the
## mouse; capture it once the window gets focus, unless the pause menu is open.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and local_player and not $PauseMenu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_menu(reason: String) -> void:
	Net.leave()
	Net.last_error = reason
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


## Network tests: a scenario script drives this process (see tools/net_test.gd).
func _start_scenario() -> void:
	var scenario_script := load("res://tools/net_scenarios/%s.gd" % Net.scenario) as GDScript
	var scenario := scenario_script.new() as Node
	add_child(scenario)
	scenario.call("start", self)
