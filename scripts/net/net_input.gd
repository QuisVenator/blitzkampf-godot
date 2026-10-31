class_name NetInput
extends Node
## Carries a client's `InputFrame`s to the server, once per physics tick.
## On the owning client it samples the player's `PlayerInput` and sends; on the
## server it installs a `RemoteInput` source for every other peer's player.
## Single player and the host's own player need neither.

var _remote: RemoteInput
var _counts: Array[int] = [0, 0, 0, 0]
## Packets waiting out the simulated lag (`NetSim`): [release time ms, packet].
var _delayed: Array = []

@onready var _player: Player = get_parent()
@onready var _input: PlayerInput = $"../PlayerInput"


func _ready() -> void:
	set_physics_process(false)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		if _player.peer_id != multiplayer.get_unique_id() and not _player.is_bot:
			_remote = RemoteInput.new()
			_input.source = _remote
	elif _player.is_local:
		set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var frame := _input.frame()
	_counts[0] += 1 if frame.crouch_pressed else 0
	_counts[1] += 1 if frame.reload_pressed else 0
	_counts[2] += 1 if frame.interact_pressed else 0
	_counts[3] += 1 if frame.interact_alt_pressed else 0
	if not NetSim.drops():
		_delayed.append([Time.get_ticks_msec() + NetSim.lag_ms, RemoteInput.pack(frame, _counts)])
	while not _delayed.is_empty() and _delayed[0][0] <= Time.get_ticks_msec():
		submit.rpc_id(1, _delayed.pop_front()[1])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit(packet: PackedFloat32Array) -> void:
	if _remote == null or multiplayer.get_remote_sender_id() != _player.peer_id:
		return
	_remote.receive(packet)
