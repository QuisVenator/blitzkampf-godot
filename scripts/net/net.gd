extends Node
## Autoload "Net": connection setup for single player, host (listen server),
## dedicated server and client, plus the join handshake. Everything else uses
## Godot's high-level multiplayer (`multiplayer`), which is the offline peer in
## single player, so gameplay code has no single-player special case.
##
## Command-line options (after `--`): `--host`, `--server` (dedicated, headless),
## `--join=<address>`, `--port=<n>`, `--map=<id>`, `--cheats` (clients may use console commands), `--net-lag=<ms>` / `--net-loss=<percent>` (see
## `NetSim`), `--scenario=<name>` (network tests).

enum Role { OFFLINE, HOST, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 8
const REJECT_GRACE := 0.2

## A client is accepted only when this matches the server's (builds must agree).
var protocol_version := 13

var role := Role.OFFLINE
var address := "127.0.0.1"
var port := DEFAULT_PORT
## Something went wrong joining or hosting; the main menu shows it.
var last_error := ""
var scenario := ""
## Which map to play (`MapDefinition.id`; empty = the catalog's first). Chosen in the menu or with
## `--map=<id>`; a client takes the server's.
var map_id: StringName = &""
## Remote clients may run console commands (`--cheats`). The host and single
## player always may.
var cheats := false
## True when the command line already chose a role, so the menu is skipped.
var cli_autostart := false

## Server side: a client passed the handshake / left after passing it.
signal player_joined(peer_id: int)
## Client side: the server told us which map is being played (`map_id` is set); the game
## builds it and answers with `map_loaded()`.
signal map_received(id: StringName)
signal player_left(peer_id: int)
## Client side: the game can't continue (connection failed, dropped or rejected).
signal connection_lost(reason: String)

var _args := {}
var _joined: Array[int] = []
## Server side: peers that passed the version check and were told the map, but have not
## said they built it yet (a peer only joins, and gets replicated state, after that).
var _welcomed: Array[int] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	port = int(_args.get("port", DEFAULT_PORT))
	scenario = _args.get("scenario", "")
	map_id = StringName(_args.get("map", ""))
	cheats = _args.has("cheats")
	protocol_version = int(_args.get("protocol", protocol_version))
	NetSim.lag_ms = int(_args.get("net-lag", "0"))
	NetSim.loss = float(_args.get("net-loss", "0")) / 100.0
	if _args.has("server"):
		role = Role.SERVER
	elif _args.has("host"):
		role = Role.HOST
	elif _args.has("join"):
		role = Role.CLIENT
		address = _args["join"]
	cli_autostart = role != Role.OFFLINE

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: connection_lost.emit("Could not connect to %s:%d" % [address, port]))
	multiplayer.server_disconnected.connect(func() -> void: connection_lost.emit("The server closed the connection"))


func arg(key: String, default := "") -> String:
	return _args.get(key, default)


## True while hosting or connected (not in single player).
func is_online() -> bool:
	return not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


## Creates the network peer for the current `role`. Call when the game scene is ready,
## so replicated nodes can be found on both sides.
func start() -> Error:
	_joined.clear()
	_welcomed.clear()
	last_error = ""
	var peer := ENetMultiplayerPeer.new()
	var error := OK
	match role:
		Role.HOST, Role.SERVER:
			error = peer.create_server(port, MAX_CLIENTS)
		Role.CLIENT:
			error = peer.create_client(address, port)
		_:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			return OK
	if error != OK:
		last_error = "Could not %s on port %d (%s)" % ["host" if role != Role.CLIENT else "connect", port, error_string(error)]
		role = Role.OFFLINE
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		return error
	multiplayer.multiplayer_peer = peer
	return OK


## Back to single player (does not change scenes).
func leave() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	_joined.clear()
	_welcomed.clear()


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, protocol_version)


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	_welcomed.erase(id)
	if id in _joined:
		_joined.erase(id)
		player_left.emit(id)


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != protocol_version:
		_rejected.rpc_id(id, "Version mismatch (server %d, you %d)" % [protocol_version, version])
		await get_tree().create_timer(REJECT_GRACE).timeout
		if is_online() and id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_welcomed.append(id)
	_welcome.rpc_id(id, map_id)


## Server to client after the version check: which map to build.
@rpc("authority", "call_remote", "reliable")
func _welcome(map: StringName) -> void:
	map_id = map
	map_received.emit(map)


## Client: the map from `map_received` is built, the server may now spawn our player.
func map_loaded() -> void:
	_map_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _map_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not id in _welcomed or id in _joined:
		return
	_joined.append(id)
	player_joined.emit(id)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	last_error = reason
	connection_lost.emit(reason)
