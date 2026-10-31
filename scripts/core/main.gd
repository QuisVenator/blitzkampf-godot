class_name Main
extends Node3D
## The game scene for single player, host, dedicated server and client alike.
## Starts networking (`Net`), spawns a `Player` for every participant through the
## `MultiplayerSpawner`, and wires the local player's signals to the HUD and sounds.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## The player this machine's human controls (null on a dedicated server).
var local_player: Player

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _hud: Hud = $Hud
@onready var _sfx: Sfx = $Sfx


func _ready() -> void:
	_spawner.spawn_function = _spawn_player
	_players.child_entered_tree.connect(_on_player_entered)
	Net.connection_lost.connect(_return_to_menu)

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


## Runs on every peer with the same data, so the replicated tree matches.
func _spawn_player(data: Dictionary) -> Node:
	var peer: int = data["peer"]
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = str(peer)
	player.peer_id = peer
	player.is_local = peer == multiplayer.get_unique_id()
	# The player body belongs to the server; each owner's client sends it input.
	player.get_node("PlayerInput").set_multiplayer_authority(peer)
	player.get_node("NetInput").set_multiplayer_authority(peer)
	return player


func _on_peer_joined(peer: int) -> void:
	_spawner.spawn({"peer": peer})


func _on_peer_left(peer: int) -> void:
	var player := _players.get_node_or_null(str(peer))
	if player:
		player.queue_free()


func _on_player_entered(node: Node) -> void:
	var player := node as Player
	if player == null or not player.is_local:
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
